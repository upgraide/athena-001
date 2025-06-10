import { Request, Response, NextFunction } from 'express';
import { authenticateToken as originalAuthenticateToken, AuthRequest } from '../shared/auth/middleware';

// Wrapper to fix TypeScript issues with middleware
export const authenticateToken = (req: Request, res: Response, next: NextFunction) => {
  return originalAuthenticateToken(req as AuthRequest, res, next);
};

export { AuthRequest };