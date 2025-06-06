import jwt from 'jsonwebtoken';
import { logger } from '../logger';

interface TokenPayload {
  userId: string;
  email: string;
  role?: string;
}

export class JWTService {
  private readonly accessTokenSecret: string;
  private readonly refreshTokenSecret: string;
  private readonly accessTokenExpiry: string = '15m';
  private readonly refreshTokenExpiry: string = '7d';

  constructor() {
    // In production, these will be set via Cloud Run environment variables from Secret Manager
    this.accessTokenSecret = process.env.JWT_ACCESS_SECRET || 'dev-access-secret-change-in-production';
    this.refreshTokenSecret = process.env.JWT_REFRESH_SECRET || 'dev-refresh-secret-change-in-production';
    
    if (!process.env.JWT_ACCESS_SECRET || !process.env.JWT_REFRESH_SECRET) {
      logger.warn('JWT secrets not found in environment, using development defaults');
    }
  }

  generateAccessToken(payload: TokenPayload): string {
    return jwt.sign(payload as any, this.accessTokenSecret, {
      expiresIn: this.accessTokenExpiry,
      issuer: 'athena-finance',
      audience: 'athena-api'
    } as jwt.SignOptions);
  }

  generateRefreshToken(payload: TokenPayload): string {
    return jwt.sign(payload as any, this.refreshTokenSecret, {
      expiresIn: this.refreshTokenExpiry,
      issuer: 'athena-finance',
      audience: 'athena-api'
    } as jwt.SignOptions);
  }

  generateTokenPair(payload: TokenPayload): { accessToken: string; refreshToken: string } {
    return {
      accessToken: this.generateAccessToken(payload),
      refreshToken: this.generateRefreshToken(payload)
    };
  }

  verifyAccessToken(token: string): TokenPayload {
    try {
      const decoded = jwt.verify(token, this.accessTokenSecret, {
        issuer: 'athena-finance',
        audience: 'athena-api'
      }) as TokenPayload;
      return decoded;
    } catch (error) {
      logger.error('Access token verification failed', { error });
      throw new Error('Invalid access token');
    }
  }

  verifyRefreshToken(token: string): TokenPayload {
    try {
      const decoded = jwt.verify(token, this.refreshTokenSecret, {
        issuer: 'athena-finance',
        audience: 'athena-api'
      }) as TokenPayload;
      return decoded;
    } catch (error) {
      logger.error('Refresh token verification failed', { error });
      throw new Error('Invalid refresh token');
    }
  }

  refreshAccessToken(refreshToken: string): string {
    const payload = this.verifyRefreshToken(refreshToken);
    // Generate new access token with same payload
    const tokenPayload: TokenPayload = {
      userId: payload.userId,
      email: payload.email
    };
    if (payload.role) {
      tokenPayload.role = payload.role;
    }
    return this.generateAccessToken(tokenPayload);
  }
}

export const jwtService = new JWTService();