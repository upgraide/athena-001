import { Request, Response, NextFunction } from 'express';
import { jwtService } from './jwt';
import { logger } from '../logger';

export interface AuthRequest extends Request {
  user?: {
    userId: string;
    email: string;
    role?: string;
  };
}

export const authenticateToken = (req: AuthRequest, res: Response, next: NextFunction): Response | void => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

    if (!token) {
      return res.status(401).json({ error: 'Access token required' });
    }

    const payload = jwtService.verifyAccessToken(token);
    req.user = {
      userId: payload.userId,
      email: payload.email
    };
    if (payload.role) {
      req.user.role = payload.role;
    }
    next();
  } catch (error) {
    logger.error('Authentication failed', { error, path: req.path });
    return res.status(403).json({ error: 'Invalid or expired token' });
  }
};

export const authorizeRole = (requiredRole: string) => {
  return (req: AuthRequest, res: Response, next: NextFunction): Response | void => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    if (req.user.role !== requiredRole && req.user.role !== 'admin') {
      logger.warn('Authorization failed', { 
        userId: req.user.userId,
        requiredRole,
        userRole: req.user.role 
      });
      return res.status(403).json({ error: 'Insufficient permissions' });
    }

    next();
  };
};

export const optionalAuth = (req: AuthRequest, res: Response, next: NextFunction) => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader && authHeader.split(' ')[1];

    if (token) {
      const payload = jwtService.verifyAccessToken(token);
      req.user = {
        userId: payload.userId,
        email: payload.email
      };
      if (payload.role) {
        req.user.role = payload.role;
      }
    }
    next();
  } catch (error) {
    // Invalid token, but continue without user context
    logger.debug('Optional auth token invalid', { error });
    next();
  }
};