export interface User {
  id: string;
  email: string;
  passwordHash?: string | undefined; // Optional for OAuth users
  firstName: string;
  lastName: string;
  role: 'user' | 'admin' | 'premium';
  authProvider: 'local' | 'google' | 'oauth';
  googleId?: string | undefined;
  emailVerified: boolean;
  createdAt: Date;
  updatedAt: Date;
  lastLoginAt?: Date | undefined;
  isActive: boolean;
  settings?: UserSettings | undefined;
}

export interface UserSettings {
  timezone: string;
  currency: string;
  language: string;
  notifications: {
    email: boolean;
    push: boolean;
    billReminders: boolean;
    weeklyReports: boolean;
  };
}

export interface CreateUserDto {
  email: string;
  password?: string;
  firstName: string;
  lastName: string;
  authProvider: 'local' | 'google' | 'oauth';
  googleId?: string;
}

export interface UpdateUserDto {
  firstName?: string;
  lastName?: string;
  settings?: Partial<UserSettings>;
}

export interface LoginDto {
  email: string;
  password: string;
}

export interface RegisterDto {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
}