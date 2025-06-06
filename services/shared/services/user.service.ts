import { Firestore } from '@google-cloud/firestore';
import { User, CreateUserDto, UpdateUserDto } from '../models/user';
import { logger } from '../logger';
import { passwordService } from '../auth/password';

export class UserService {
  private readonly usersCollection = 'users';

  constructor(private firestore: Firestore) {}

  async createUser(data: CreateUserDto): Promise<User> {
    try {
      // Check if user already exists
      const existingUser = await this.findByEmail(data.email);
      if (existingUser) {
        throw new Error('User with this email already exists');
      }

      const userId = this.firestore.collection(this.usersCollection).doc().id;
      
      const userDoc: any = {
        id: userId,
        email: data.email.toLowerCase(),
        firstName: data.firstName,
        lastName: data.lastName,
        role: 'user',
        authProvider: data.authProvider,
        emailVerified: data.authProvider !== 'local', // Auto-verify OAuth users
        createdAt: new Date(),
        updatedAt: new Date(),
        isActive: true,
        settings: {
          timezone: 'Europe/Lisbon',
          currency: 'EUR',
          language: 'en',
          notifications: {
            email: true,
            push: true,
            billReminders: true,
            weeklyReports: true
          }
        }
      };

      // Only add optional fields if they have values
      if (data.password) {
        userDoc.passwordHash = await passwordService.hashPassword(data.password);
      }
      if (data.googleId) {
        userDoc.googleId = data.googleId;
      }

      const user: User = userDoc;

      await this.firestore.collection(this.usersCollection).doc(userId).set(user);
      
      logger.info('User created successfully', { userId, email: user.email });
      return user;
    } catch (error) {
      logger.error('Failed to create user', { error, email: data.email });
      throw error;
    }
  }

  async findById(userId: string): Promise<User | null> {
    try {
      const doc = await this.firestore.collection(this.usersCollection).doc(userId).get();
      
      if (!doc.exists) {
        return null;
      }

      return { id: doc.id, ...doc.data() } as User;
    } catch (error) {
      logger.error('Failed to find user by ID', { error, userId });
      throw error;
    }
  }

  async findByEmail(email: string): Promise<User | null> {
    try {
      const snapshot = await this.firestore
        .collection(this.usersCollection)
        .where('email', '==', email.toLowerCase())
        .limit(1)
        .get();

      if (snapshot.empty) {
        return null;
      }

      const doc = snapshot.docs[0]!;
      return { id: doc.id, ...doc.data() } as User;
    } catch (error) {
      logger.error('Failed to find user by email', { error, email });
      throw error;
    }
  }

  async findByGoogleId(googleId: string): Promise<User | null> {
    try {
      const snapshot = await this.firestore
        .collection(this.usersCollection)
        .where('googleId', '==', googleId)
        .limit(1)
        .get();

      if (snapshot.empty) {
        return null;
      }

      const doc = snapshot.docs[0]!;
      return { id: doc.id, ...doc.data() } as User;
    } catch (error) {
      logger.error('Failed to find user by Google ID', { error, googleId });
      throw error;
    }
  }

  async updateUser(userId: string, data: UpdateUserDto): Promise<User> {
    try {
      const user = await this.findById(userId);
      if (!user) {
        throw new Error('User not found');
      }

      const updateData = {
        ...data,
        updatedAt: new Date()
      };

      await this.firestore.collection(this.usersCollection).doc(userId).update(updateData);
      
      logger.info('User updated successfully', { userId });
      return { ...user, ...updateData } as User;
    } catch (error) {
      logger.error('Failed to update user', { error, userId });
      throw error;
    }
  }

  async updateLastLogin(userId: string): Promise<void> {
    try {
      await this.firestore.collection(this.usersCollection).doc(userId).update({
        lastLoginAt: new Date()
      });
    } catch (error) {
      logger.error('Failed to update last login', { error, userId });
      throw error;
    }
  }

  async verifyEmail(userId: string): Promise<void> {
    try {
      await this.firestore.collection(this.usersCollection).doc(userId).update({
        emailVerified: true,
        updatedAt: new Date()
      });
      logger.info('Email verified', { userId });
    } catch (error) {
      logger.error('Failed to verify email', { error, userId });
      throw error;
    }
  }

  async deactivateUser(userId: string): Promise<void> {
    try {
      await this.firestore.collection(this.usersCollection).doc(userId).update({
        isActive: false,
        updatedAt: new Date()
      });
      logger.info('User deactivated', { userId });
    } catch (error) {
      logger.error('Failed to deactivate user', { error, userId });
      throw error;
    }
  }
}