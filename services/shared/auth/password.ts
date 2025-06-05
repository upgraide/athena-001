import bcryptjs from 'bcryptjs';
import { logger } from '../logger';

export class PasswordService {
  private readonly saltRounds: number = 12;

  async hashPassword(password: string): Promise<string> {
    try {
      const salt = await bcryptjs.genSalt(this.saltRounds);
      const hash = await bcryptjs.hash(password, salt);
      return hash;
    } catch (error) {
      logger.error('Password hashing failed', { error });
      throw new Error('Failed to hash password');
    }
  }

  async verifyPassword(password: string, hash: string): Promise<boolean> {
    try {
      return await bcryptjs.compare(password, hash);
    } catch (error) {
      logger.error('Password verification failed', { error });
      return false;
    }
  }

  validatePasswordStrength(password: string): { valid: boolean; errors: string[] } {
    const errors: string[] = [];

    if (password.length < 8) {
      errors.push('Password must be at least 8 characters long');
    }

    if (!/[A-Z]/.test(password)) {
      errors.push('Password must contain at least one uppercase letter');
    }

    if (!/[a-z]/.test(password)) {
      errors.push('Password must contain at least one lowercase letter');
    }

    if (!/[0-9]/.test(password)) {
      errors.push('Password must contain at least one number');
    }

    if (!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(password)) {
      errors.push('Password must contain at least one special character');
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }
}

export const passwordService = new PasswordService();