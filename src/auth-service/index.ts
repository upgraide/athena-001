import { SecureMicroservice } from '../../services/shared/secure-base';
import { UserService } from '../../services/shared/services/user.service';
import { jwtService } from '../../services/shared/auth/jwt';
import { passwordService } from '../../services/shared/auth/password';
import { RegisterDto, LoginDto } from '../../services/shared/models/user';
import { authenticateToken, AuthRequest } from '../../services/shared/auth/middleware';
import cors from 'cors';
import compression from 'compression';

class AuthService extends SecureMicroservice {
  private userService: UserService;

  constructor() {
    super('auth-service');
    this.userService = new UserService(this.firestore);
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

        // Audit log
        await this.auditLog('user_registered', {
          userId: user.id,
          email: user.email,
          authProvider: 'local'
        }, 'medium');

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
          return res.status(409).json({ error: 'Email already registered' });
        }
        
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
          return res.status(401).json({ error: 'Invalid credentials' });
        }

        // Check if user is active
        if (!user.isActive) {
          return res.status(403).json({ error: 'Account deactivated' });
        }

        // Verify password
        const isValidPassword = await passwordService.verifyPassword(password, user.passwordHash);
        if (!isValidPassword) {
          await this.auditLog('login_failed', {
            email,
            reason: 'invalid_password'
          }, 'high');
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

        // Audit log
        await this.auditLog('user_login', {
          userId: user.id,
          email: user.email,
          authProvider: 'local'
        }, 'low');

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
  }
}

// Start the service
const authService = new AuthService();
const port = parseInt(process.env.AUTH_SERVICE_PORT || '8081');
authService.start(port);

export { AuthService };