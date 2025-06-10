import { Firestore } from '@google-cloud/firestore';
import winston from 'winston';
import { Transaction, Subscription } from '../models/transaction.model';
import { differenceInDays, addDays, addWeeks, addMonths, addYears } from 'date-fns';

interface RecurringPattern {
  frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
  amount: number;
  currency: string;
  nextDate: Date;
  confidence: number;
}

interface MerchantTransactions {
  [merchant: string]: Transaction[];
}

export class SubscriptionDetectorService {
  constructor(
    private firestore: Firestore,
    private logger: winston.Logger
  ) {}

  async detectSubscriptions(userId: string): Promise<Subscription[]> {
    try {
      // Get last 6 months of transactions
      const transactions = await this.getTransactionHistory(userId, 180);
      
      // Group by merchant
      const merchantGroups = this.groupByMerchant(transactions);
      
      // Analyze each merchant for patterns
      const subscriptions: Subscription[] = [];
      
      for (const [merchant, txns] of Object.entries(merchantGroups)) {
        const pattern = this.analyzeRecurringPattern(txns);
        
        if (pattern) {
          const subscription = await this.createOrUpdateSubscription({
            userId,
            merchantName: merchant,
            amount: pattern.amount,
            currency: pattern.currency,
            frequency: pattern.frequency,
            nextExpected: pattern.nextDate,
            confidence: pattern.confidence,
            transactionIds: txns.map(t => t.id),
            lastCharged: txns[txns.length - 1].date
          });
          
          subscriptions.push(subscription);
        }
      }
      
      this.logger.info('Subscription detection completed', {
        userId,
        subscriptionsFound: subscriptions.length
      });
      
      return subscriptions;
    } catch (error) {
      this.logger.error('Failed to detect subscriptions', { userId, error });
      throw error;
    }
  }

  private async getTransactionHistory(userId: string, days: number): Promise<Transaction[]> {
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - days);
    
    // First get transactions by user and date
    const snapshot = await this.firestore
      .collection('transactions')
      .where('userId', '==', userId)
      .where('date', '>=', startDate)
      .orderBy('date', 'asc')
      .get();
    
    // Then filter for expenses in memory
    const transactions = snapshot.docs
      .map(doc => ({
        ...doc.data(),
        id: doc.id,
        date: doc.data().date.toDate()
      })) as Transaction[];
    
    return transactions.filter(t => t.amount < 0); // Only expenses
  }

  private groupByMerchant(transactions: Transaction[]): MerchantTransactions {
    const groups: MerchantTransactions = {};
    
    transactions.forEach(txn => {
      const merchant = txn.merchantName || 'Unknown';
      if (!groups[merchant]) {
        groups[merchant] = [];
      }
      groups[merchant].push(txn);
    });
    
    // Filter out merchants with less than 2 transactions
    return Object.fromEntries(
      Object.entries(groups).filter(([_, txns]) => txns.length >= 2)
    );
  }

  private analyzeRecurringPattern(transactions: Transaction[]): RecurringPattern | null {
    if (transactions.length < 2) return null;
    
    // Sort by date
    const sorted = transactions.sort((a, b) => a.date.getTime() - b.date.getTime());
    
    // Calculate intervals between transactions
    const intervals: number[] = [];
    for (let i = 1; i < sorted.length; i++) {
      const days = differenceInDays(sorted[i].date, sorted[i-1].date);
      intervals.push(days);
    }
    
    // Detect frequency pattern
    const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
    const frequency = this.detectFrequency(avgInterval);
    
    if (frequency && this.isConsistentAmount(sorted) && this.isConsistentInterval(intervals, avgInterval)) {
      const lastTransaction = sorted[sorted.length - 1];
      
      return {
        frequency,
        amount: this.getAverageAmount(sorted),
        currency: lastTransaction.currency,
        nextDate: this.predictNextDate(lastTransaction.date, frequency),
        confidence: this.calculatePatternConfidence(intervals, sorted)
      };
    }
    
    return null;
  }

  private detectFrequency(avgInterval: number): 'daily' | 'weekly' | 'monthly' | 'yearly' | null {
    // Allow some variance in intervals
    if (avgInterval >= 0.8 && avgInterval <= 1.2) return 'daily';
    if (avgInterval >= 6 && avgInterval <= 8) return 'weekly';
    if (avgInterval >= 28 && avgInterval <= 32) return 'monthly';
    if (avgInterval >= 360 && avgInterval <= 370) return 'yearly';
    
    // Check for bi-weekly
    if (avgInterval >= 13 && avgInterval <= 15) return 'weekly'; // Treat as weekly
    
    // Check for quarterly
    if (avgInterval >= 88 && avgInterval <= 92) return 'monthly'; // Treat as monthly
    
    return null;
  }

  private isConsistentAmount(transactions: Transaction[]): boolean {
    const amounts = transactions.map(t => Math.abs(t.amount));
    const avgAmount = amounts.reduce((a, b) => a + b, 0) / amounts.length;
    
    // Check if all amounts are within 5% of average
    return amounts.every(amount => {
      const variance = Math.abs(amount - avgAmount) / avgAmount;
      return variance <= 0.05;
    });
  }

  private isConsistentInterval(intervals: number[], avgInterval: number): boolean {
    // Check if at least 80% of intervals are within 20% of average
    const consistentIntervals = intervals.filter(interval => {
      const variance = Math.abs(interval - avgInterval) / avgInterval;
      return variance <= 0.2;
    });
    
    return consistentIntervals.length / intervals.length >= 0.8;
  }

  private getAverageAmount(transactions: Transaction[]): number {
    const amounts = transactions.map(t => Math.abs(t.amount));
    return amounts.reduce((a, b) => a + b, 0) / amounts.length;
  }

  private predictNextDate(lastDate: Date, frequency: 'daily' | 'weekly' | 'monthly' | 'yearly'): Date {
    switch (frequency) {
      case 'daily':
        return addDays(lastDate, 1);
      case 'weekly':
        return addWeeks(lastDate, 1);
      case 'monthly':
        return addMonths(lastDate, 1);
      case 'yearly':
        return addYears(lastDate, 1);
    }
  }

  private calculatePatternConfidence(intervals: number[], transactions: Transaction[]): number {
    // Base confidence on consistency of intervals and amounts
    const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
    const intervalVariance = intervals.reduce((sum, interval) => {
      return sum + Math.abs(interval - avgInterval) / avgInterval;
    }, 0) / intervals.length;
    
    const amounts = transactions.map(t => Math.abs(t.amount));
    const avgAmount = amounts.reduce((a, b) => a + b, 0) / amounts.length;
    const amountVariance = amounts.reduce((sum, amount) => {
      return sum + Math.abs(amount - avgAmount) / avgAmount;
    }, 0) / amounts.length;
    
    // Calculate confidence (higher variance = lower confidence)
    const intervalConfidence = Math.max(0, 1 - intervalVariance);
    const amountConfidence = Math.max(0, 1 - amountVariance);
    
    // Weight based on number of transactions (more data = higher confidence)
    const dataConfidence = Math.min(1, transactions.length / 12); // Max confidence at 12 transactions
    
    return (intervalConfidence * 0.4 + amountConfidence * 0.4 + dataConfidence * 0.2);
  }

  private async createOrUpdateSubscription(data: {
    userId: string;
    merchantName: string;
    amount: number;
    currency: string;
    frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
    nextExpected: Date;
    confidence: number;
    transactionIds: string[];
    lastCharged?: Date;
  }): Promise<Subscription> {
    try {
      // Check if subscription already exists
      const existingSnapshot = await this.firestore
        .collection('subscriptions')
        .where('userId', '==', data.userId)
        .where('merchantName', '==', data.merchantName)
        .limit(1)
        .get();
      
      if (!existingSnapshot.empty) {
        // Update existing subscription
        const doc = existingSnapshot.docs[0];
        const subscription: Subscription = {
          ...doc.data() as Subscription,
          ...data,
          id: doc.id,
          updatedAt: new Date()
        };
        
        await doc.ref.update({
          ...data,
          updatedAt: new Date()
        });
        
        // Update related transactions
        await this.updateTransactionsAsRecurring(data.transactionIds, doc.id);
        
        return subscription;
      }
      
      // Create new subscription
      const subscriptionRef = this.firestore.collection('subscriptions').doc();
      const subscription: Subscription = {
        ...data,
        id: subscriptionRef.id,
        status: 'active',
        createdAt: new Date(),
        updatedAt: new Date()
      };
      
      await subscriptionRef.set(subscription);
      
      // Update related transactions
      await this.updateTransactionsAsRecurring(data.transactionIds, subscriptionRef.id);
      
      this.logger.info('Subscription created', {
        subscriptionId: subscription.id,
        merchantName: subscription.merchantName,
        frequency: subscription.frequency
      });
      
      return subscription;
    } catch (error) {
      this.logger.error('Failed to create/update subscription', { error });
      throw error;
    }
  }

  private async updateTransactionsAsRecurring(transactionIds: string[], subscriptionId: string): Promise<void> {
    const batch = this.firestore.batch();
    
    transactionIds.forEach(id => {
      const ref = this.firestore.collection('transactions').doc(id);
      batch.update(ref, {
        isRecurring: true,
        subscriptionId,
        lastModified: new Date()
      });
    });
    
    await batch.commit();
  }

  async getSubscriptions(userId: string): Promise<{
    subscriptions: Subscription[];
    totalMonthly: number;
    totalYearly: number;
    recommendations: string[];
  }> {
    try {
      const snapshot = await this.firestore
        .collection('subscriptions')
        .where('userId', '==', userId)
        .where('status', '==', 'active')
        .get();
      
      const subscriptions = snapshot.docs.map(doc => ({
        ...doc.data(),
        id: doc.id
      })) as Subscription[];
      
      // Calculate totals
      let totalMonthly = 0;
      let totalYearly = 0;
      
      subscriptions.forEach(sub => {
        const monthlyAmount = this.calculateMonthlyAmount(sub);
        totalMonthly += monthlyAmount;
        totalYearly += monthlyAmount * 12;
      });
      
      // Generate recommendations
      const recommendations = this.generateRecommendations(subscriptions, totalMonthly);
      
      return {
        subscriptions,
        totalMonthly,
        totalYearly,
        recommendations
      };
    } catch (error) {
      this.logger.error('Failed to get subscriptions', { userId, error });
      throw error;
    }
  }

  private calculateMonthlyAmount(subscription: Subscription): number {
    switch (subscription.frequency) {
      case 'daily':
        return subscription.amount * 30;
      case 'weekly':
        return subscription.amount * 4.33;
      case 'monthly':
        return subscription.amount;
      case 'yearly':
        return subscription.amount / 12;
    }
  }

  private generateRecommendations(subscriptions: Subscription[], totalMonthly: number): string[] {
    const recommendations: string[] = [];
    
    // Check for high subscription spending
    if (totalMonthly > 500) {
      recommendations.push('Your subscription spending is high. Consider reviewing and canceling unused services.');
    }
    
    // Check for duplicate services
    const entertainmentSubs = subscriptions.filter(s => 
      s.merchantName.toLowerCase().match(/netflix|hulu|disney|spotify|apple music/)
    );
    if (entertainmentSubs.length > 3) {
      recommendations.push('You have multiple entertainment subscriptions. Consider consolidating to save money.');
    }
    
    // Check for annual payment opportunities
    const monthlyHighValue = subscriptions.filter(s => 
      s.frequency === 'monthly' && s.amount > 20
    );
    if (monthlyHighValue.length > 0) {
      recommendations.push('Some of your monthly subscriptions might offer annual discounts. Check for yearly payment options.');
    }
    
    return recommendations;
  }
}