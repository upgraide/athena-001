import { businessMetrics, authFailures } from './secure-base';
import winston from 'winston';

export class MonitoringHelper {
  constructor(private logger: winston.Logger) {}

  // Track business events
  trackBusinessEvent(eventType: string, status: 'success' | 'failure', metadata?: any) {
    businessMetrics.inc({
      event_type: eventType,
      status
    });

    this.logger.info('Business event tracked', {
      eventType,
      status,
      metadata,
      timestamp: new Date().toISOString()
    });
  }

  // Track authentication failures
  trackAuthFailure(reason: string, email?: string) {
    authFailures.inc({ reason });

    this.logger.warn('Authentication failure', {
      reason,
      email: email || 'unknown',
      timestamp: new Date().toISOString(),
      priority: 'high'
    });
  }

  // Track financial transactions
  trackTransaction(type: string, amount: number, currency: string, status: string) {
    this.trackBusinessEvent('transaction', status === 'success' ? 'success' : 'failure', {
      type,
      amount,
      currency,
      status
    });
  }

  // Track document processing
  trackDocumentProcessing(documentType: string, processingTime: number, success: boolean) {
    this.trackBusinessEvent('document_processing', success ? 'success' : 'failure', {
      documentType,
      processingTime,
      success
    });
  }

  // Track API integration calls
  trackApiCall(service: string, endpoint: string, duration: number, success: boolean) {
    this.trackBusinessEvent('api_call', success ? 'success' : 'failure', {
      service,
      endpoint,
      duration,
      success
    });
  }

  // Create alert-worthy log entries
  createAlert(alertType: string, message: string, severity: 'low' | 'medium' | 'high' | 'critical', metadata?: any) {
    const logLevel = severity === 'critical' || severity === 'high' ? 'error' : 'warn';
    
    this.logger[logLevel](`ALERT: ${message}`, {
      alertType,
      severity,
      metadata,
      timestamp: new Date().toISOString(),
      requiresAction: severity === 'critical' || severity === 'high'
    });
  }

  // Security event tracking
  trackSecurityEvent(eventType: string, details: any, riskLevel: 'low' | 'medium' | 'high') {
    this.logger.warn('Security event detected', {
      eventType,
      riskLevel,
      details,
      timestamp: new Date().toISOString()
    });

    if (riskLevel === 'high') {
      this.createAlert('security', `High-risk security event: ${eventType}`, 'high', details);
    }
  }

  // Performance tracking
  trackPerformance(operation: string, duration: number, threshold: number) {
    if (duration > threshold) {
      this.logger.warn('Performance threshold exceeded', {
        operation,
        duration,
        threshold,
        exceeded: duration - threshold
      });
    }
  }

  // Resource usage tracking
  trackResourceUsage() {
    const usage = process.memoryUsage();
    const cpuUsage = process.cpuUsage();

    this.logger.info('Resource usage', {
      memory: {
        rss: `${Math.round(usage.rss / 1024 / 1024)}MB`,
        heapTotal: `${Math.round(usage.heapTotal / 1024 / 1024)}MB`,
        heapUsed: `${Math.round(usage.heapUsed / 1024 / 1024)}MB`,
        external: `${Math.round(usage.external / 1024 / 1024)}MB`
      },
      cpu: {
        user: cpuUsage.user,
        system: cpuUsage.system
      },
      uptime: process.uptime()
    });
  }
}

// Custom error classes for better tracking
export class MonitoredError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly severity: 'low' | 'medium' | 'high' | 'critical',
    public readonly metadata?: any
  ) {
    super(message);
    this.name = 'MonitoredError';
  }
}

export class BusinessLogicError extends MonitoredError {
  constructor(message: string, metadata?: any) {
    super(message, 'BUSINESS_LOGIC_ERROR', 'medium', metadata);
    this.name = 'BusinessLogicError';
  }
}

export class SecurityError extends MonitoredError {
  constructor(message: string, metadata?: any) {
    super(message, 'SECURITY_ERROR', 'high', metadata);
    this.name = 'SecurityError';
  }
}

export class IntegrationError extends MonitoredError {
  constructor(message: string, service: string, metadata?: any) {
    super(message, 'INTEGRATION_ERROR', 'medium', { service, ...metadata });
    this.name = 'IntegrationError';
  }
}