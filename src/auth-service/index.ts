import { SecureMicroservice } from '../../services/shared/secure-base';
import { UserService } from '../../services/shared/services/user.service';
import { jwtService } from '../../services/shared/auth/jwt';
import { passwordService } from '../../services/shared/auth/password';
import { RegisterDto, LoginDto } from '../../services/shared/models/user';
import { authenticateToken, AuthRequest } from '../../services/shared/auth/middleware';
import { MonitoringHelper } from '../../services/shared/monitoring';
import { GDPRService } from '../../services/shared/gdpr/gdpr.service';
import cors from 'cors';
import compression from 'compression';

class AuthService extends SecureMicroservice {
  private userService: UserService;
  private monitoring: MonitoringHelper;
  private gdprService: GDPRService;

  constructor() {
    super('auth-service');
    this.userService = new UserService(this.firestore);
    this.monitoring = new MonitoringHelper(this.logger);
    this.gdprService = new GDPRService();
    this.setupMiddleware();
    this.setupRoutes();
  }

  private setupMiddleware() {
    // Enable CORS for API access
    const corsOptions = {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
      credentials: true,
      optionsSuccessStatus: 200
    };
    this.app.use(cors(corsOptions));
    this.app.use(compression());
  }

  private setupRoutes() {
    // Registration endpoint
    this.app.post('/api/v1/auth/register', async (req: any, res: any) => {
      try {
        const { email, password, firstName, lastName }: RegisterDto = req.body;

        // Validate input
        if (!email || !password || !firstName || !lastName) {
          return res.status(400).json({ error: 'All fields are required' });
        }

        // Validate email format
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
          return res.status(400).json({ error: 'Invalid email format' });
        }

        // Validate password strength
        const passwordValidation = passwordService.validatePasswordStrength(password);
        if (!passwordValidation.valid) {
          return res.status(400).json({ 
            error: 'Password does not meet requirements',
            details: passwordValidation.errors 
          });
        }

        // Create user
        const user = await this.userService.createUser({
          email,
          password,
          firstName,
          lastName,
          authProvider: 'local'
        });

        // Generate tokens
        const tokens = jwtService.generateTokenPair({
          userId: user.id,
          email: user.email,
          role: user.role
        });

        // Audit log and monitoring
        await this.auditLog('user_registered', {
          userId: user.id,
          email: user.email,
          authProvider: 'local'
        }, 'medium');
        
        this.monitoring.trackBusinessEvent('user_registration', 'success', {
          authProvider: 'local',
          emailDomain: email.split('@')[1]
        });

        res.status(201).json({
          message: 'Registration successful',
          user: {
            id: user.id,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            role: user.role
          },
          tokens
        });
      } catch (error: any) {
        this.logger.error('Registration failed', { error });
        
        if (error.message === 'User with this email already exists') {
          this.monitoring.trackBusinessEvent('user_registration', 'failure', {
            reason: 'duplicate_email'
          });
          return res.status(409).json({ error: 'Email already registered' });
        }
        
        this.monitoring.trackBusinessEvent('user_registration', 'failure', {
          reason: 'internal_error'
        });
        res.status(500).json({ error: 'Registration failed' });
      }
    });

    // Login endpoint
    this.app.post('/api/v1/auth/login', async (req: any, res: any) => {
      try {
        const { email, password }: LoginDto = req.body;

        // Validate input
        if (!email || !password) {
          return res.status(400).json({ error: 'Email and password are required' });
        }

        // Find user
        const user = await this.userService.findByEmail(email);
        if (!user || !user.passwordHash) {
          this.monitoring.trackAuthFailure('user_not_found', email);
          return res.status(401).json({ error: 'Invalid credentials' });
        }

        // Check if user is active
        if (!user.isActive) {
          this.monitoring.trackAuthFailure('account_deactivated', email);
          return res.status(403).json({ error: 'Account deactivated' });
        }

        // Verify password
        const isValidPassword = await passwordService.verifyPassword(password, user.passwordHash);
        if (!isValidPassword) {
          await this.auditLog('login_failed', {
            email,
            reason: 'invalid_password'
          }, 'high');
          this.monitoring.trackAuthFailure('invalid_password', email);
          return res.status(401).json({ error: 'Invalid credentials' });
        }

        // Update last login
        await this.userService.updateLastLogin(user.id);

        // Generate tokens
        const tokens = jwtService.generateTokenPair({
          userId: user.id,
          email: user.email,
          role: user.role
        });

        // Audit log and monitoring
        await this.auditLog('user_login', {
          userId: user.id,
          email: user.email,
          authProvider: 'local'
        }, 'low');
        
        this.monitoring.trackBusinessEvent('user_login', 'success', {
          authProvider: 'local',
          emailDomain: email.split('@')[1]
        });

        res.json({
          message: 'Login successful',
          user: {
            id: user.id,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            role: user.role,
            emailVerified: user.emailVerified
          },
          tokens
        });
      } catch (error) {
        this.logger.error('Login failed', { error });
        res.status(500).json({ error: 'Login failed' });
      }
    });

    // Refresh token endpoint
    this.app.post('/api/v1/auth/refresh', async (req: any, res: any) => {
      try {
        const { refreshToken } = req.body;

        if (!refreshToken) {
          return res.status(400).json({ error: 'Refresh token required' });
        }

        // Verify refresh token and generate new access token
        const newAccessToken = jwtService.refreshAccessToken(refreshToken);

        res.json({
          accessToken: newAccessToken
        });
      } catch (error) {
        this.logger.error('Token refresh failed', { error });
        res.status(401).json({ error: 'Invalid refresh token' });
      }
    });

    // Get current user endpoint (protected)
    this.app.get('/api/v1/auth/me', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const user = await this.userService.findById(req.user.userId);
        if (!user) {
          return res.status(404).json({ error: 'User not found' });
        }

        res.json({
          user: {
            id: user.id,
            email: user.email,
            firstName: user.firstName,
            lastName: user.lastName,
            role: user.role,
            emailVerified: user.emailVerified,
            settings: user.settings
          }
        });
      } catch (error) {
        this.logger.error('Failed to get user profile', { error });
        res.status(500).json({ error: 'Failed to get user profile' });
      }
    });

    // Update profile endpoint (protected)
    this.app.patch('/api/v1/auth/profile', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { firstName, lastName, settings } = req.body;

        const updatedUser = await this.userService.updateUser(req.user.userId, {
          firstName,
          lastName,
          settings
        });

        res.json({
          message: 'Profile updated successfully',
          user: {
            id: updatedUser.id,
            email: updatedUser.email,
            firstName: updatedUser.firstName,
            lastName: updatedUser.lastName,
            settings: updatedUser.settings
          }
        });
      } catch (error) {
        this.logger.error('Failed to update profile', { error });
        res.status(500).json({ error: 'Failed to update profile' });
      }
    });

    // Logout endpoint (protected)
    this.app.post('/api/v1/auth/logout', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        // Audit log
        await this.auditLog('user_logout', {
          userId: req.user.userId,
          email: req.user.email
        }, 'low');

        // In a production app, you might want to blacklist the token here
        res.json({ message: 'Logout successful' });
      } catch (error) {
        this.logger.error('Logout failed', { error });
        res.status(500).json({ error: 'Logout failed' });
      }
    });

    // Health check for auth service
    this.app.get('/api/v1/auth/health', (_req: any, res: any) => {
      res.json({
        service: 'auth-service',
        status: 'healthy',
        timestamp: new Date().toISOString()
      });
    });

    // GDPR Endpoints

    // Export user data (protected)
    this.app.post('/api/v1/gdpr/export', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const exportRequest = await this.gdprService.exportUserData(req.user.userId);

        await this.auditLog('gdpr_export_requested', {
          userId: req.user.userId,
          requestId: exportRequest.id
        }, 'high');

        res.json({
          message: 'Export request created. You will receive a download link when ready.',
          request: exportRequest
        });
      } catch (error) {
        this.logger.error('GDPR export request failed', { error });
        res.status(500).json({ error: 'Failed to create export request' });
      }
    });

    // Delete user data (protected)
    this.app.post('/api/v1/gdpr/delete', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        // Require password confirmation
        const { password } = req.body;
        if (!password) {
          return res.status(400).json({ error: 'Password confirmation required' });
        }

        // Verify password
        const user = await this.userService.findById(req.user.userId);
        if (!user || !user.passwordHash) {
          return res.status(404).json({ error: 'User not found' });
        }

        const isValidPassword = await passwordService.verifyPassword(password, user.passwordHash);
        if (!isValidPassword) {
          return res.status(401).json({ error: 'Invalid password' });
        }

        const deleteRequest = await this.gdprService.deleteUserData(req.user.userId);

        await this.auditLog('gdpr_deletion_requested', {
          userId: req.user.userId,
          requestId: deleteRequest.id
        }, 'critical');

        res.json({
          message: 'Deletion request created. Your data will be permanently removed.',
          request: deleteRequest
        });
      } catch (error) {
        this.logger.error('GDPR deletion request failed', { error });
        res.status(500).json({ error: 'Failed to create deletion request' });
      }
    });

    // Update consent (protected)
    this.app.post('/api/v1/gdpr/consent', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const { dataProcessing, marketing, analytics } = req.body;

        await this.gdprService.recordConsent(req.user.userId, {
          dataProcessing,
          marketing,
          analytics,
          ipAddress: req.ip || undefined
        });

        await this.auditLog('consent_updated', {
          userId: req.user.userId,
          consent: { dataProcessing, marketing, analytics }
        }, 'medium');

        res.json({
          message: 'Consent preferences updated successfully'
        });
      } catch (error) {
        this.logger.error('Failed to update consent', { error });
        res.status(500).json({ error: 'Failed to update consent preferences' });
      }
    });

    // Get consent history (protected)
    this.app.get('/api/v1/gdpr/consent/history', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const history = await this.gdprService.getConsentHistory(req.user.userId);

        res.json({
          consents: history
        });
      } catch (error) {
        this.logger.error('Failed to get consent history', { error });
        res.status(500).json({ error: 'Failed to retrieve consent history' });
      }
    });

    // Get GDPR requests (protected)
    this.app.get('/api/v1/gdpr/requests', authenticateToken, async (req: AuthRequest, res: any) => {
      try {
        if (!req.user) {
          return res.status(401).json({ error: 'Not authenticated' });
        }

        const requests = await this.gdprService.getGDPRRequests(req.user.userId);

        res.json({
          requests
        });
      } catch (error) {
        this.logger.error('Failed to get GDPR requests', { error });
        res.status(500).json({ error: 'Failed to retrieve GDPR requests' });
      }
    });

    // Privacy policy endpoint (public)
    this.app.get('/api/v1/gdpr/privacy-policy', (_req: any, res: any) => {
      res.json({
        version: '1.0.0',
        lastUpdated: '2025-01-06',
        dataController: 'Athena Finance Ltd',
        contactEmail: 'privacy@athena-finance.com',
        dataProcessing: {
          purposes: [
            'Provide financial management services',
            'Process transactions and documents',
            'Generate financial insights',
            'Ensure security and prevent fraud',
            'Comply with legal obligations'
          ],
          legalBasis: [
            'Contract performance',
            'Legitimate interests',
            'Legal compliance',
            'User consent'
          ],
          retention: 'Data is retained for 7 years after account closure for legal compliance',
          rights: [
            'Access your personal data',
            'Rectify inaccurate data',
            'Delete your data (right to be forgotten)',
            'Export your data (data portability)',
            'Object to processing',
            'Withdraw consent'
          ]
        }
      });
    });
  }
}

// Start the service
const authService = new AuthService();
const port = parseInt(process.env.PORT || process.env.AUTH_SERVICE_PORT || '8080');
authService.start(port);

export { AuthService };