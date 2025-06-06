# Athena Finance - Authentication System Documentation

## Overview

The Athena Finance platform uses JWT-based authentication with support for both local (email/password) and OAuth providers. All API endpoints (except health checks and auth endpoints) require valid authentication tokens.

## Authentication Flow

### 1. Registration
```bash
POST /api/v1/auth/register
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "firstName": "John",
  "lastName": "Doe"
}

Response:
{
  "user": { "id", "email", "firstName", "lastName", "role" },
  "tokens": { "accessToken", "refreshToken" }
}
```

### 2. Login
```bash
POST /api/v1/auth/login
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}

Response:
{
  "user": { ... },
  "tokens": { "accessToken", "refreshToken" }
}
```

### 3. Using Protected Endpoints
Include the access token in the Authorization header:
```bash
Authorization: Bearer <access_token>
```

### 4. Refresh Token
```bash
POST /api/v1/auth/refresh
{
  "refreshToken": "<refresh_token>"
}

Response:
{
  "accessToken": "<new_access_token>"
}
```

## Security Features

1. **Password Requirements**:
   - Minimum 8 characters
   - At least one uppercase letter
   - At least one lowercase letter
   - At least one number
   - At least one special character

2. **Token Security**:
   - Access tokens expire in 15 minutes
   - Refresh tokens expire in 7 days
   - Tokens are signed with secrets from Google Secret Manager
   - JWT tokens include issuer and audience validation

3. **Rate Limiting**:
   - 100 requests per minute per IP
   - Uses X-Forwarded-For header for Cloud Run compatibility

4. **Audit Logging**:
   - All authentication events are logged
   - Failed login attempts are marked as high priority
   - User registration and successful logins are tracked

## Integration with Services

### Finance Master Service
All finance endpoints now require authentication:
- `POST /api/v1/accounts` - Create account (protected)
- `POST /api/v1/transactions/categorize` - Categorize transaction (protected)
- `POST /api/v1/documents/process` - Process document (protected)
- `GET /api/v1/insights` - Get insights (protected)

The user ID is automatically extracted from the JWT token, so you don't need to pass it in the request body.

## Testing Authentication

Run the authentication test suite:
```bash
./scripts/testing/test-auth.sh
```

This tests:
- Registration with strong password validation
- Login with credentials
- Access to protected endpoints
- Invalid token rejection
- Token refresh flow
- Logout

## Deployment

The authentication service is deployed as a separate Cloud Run service:
- Service: `auth-service`
- Port: 8081
- Memory: 512Mi
- URL: https://auth-service-[hash].europe-west3.run.app

JWT secrets are stored in Google Secret Manager and accessed via environment variables.

## Development

For local development, the service uses default JWT secrets. In production, secrets are loaded from Google Secret Manager.

To run locally:
```bash
NODE_ENV=development \
JWT_ACCESS_SECRET=dev-secret \
JWT_REFRESH_SECRET=dev-refresh \
npm run dev
```

## Monitoring and Alerts

### Overview

Athena Finance uses Google Cloud Monitoring with custom metrics, alerts, and dashboards to ensure platform reliability.

### Metrics Collection

1. **Default Metrics**:
   - Request count and latency
   - CPU and memory usage
   - Error rates
   - Container restarts

2. **Custom Metrics** (via Prometheus):
   - `http_requests_total` - Total HTTP requests by method, route, status
   - `http_request_duration_seconds` - Request duration histogram
   - `auth_failures_total` - Authentication failures by reason
   - `business_events_total` - Business events by type and status

3. **Metrics Endpoint**:
   All services expose metrics at `/metrics` for Prometheus format:
   ```bash
   curl https://service-url/metrics
   ```

### Alert Policies

1. **Service Downtime** - Triggers when uptime checks fail
2. **High Request Latency** - P95 latency > 2 seconds for 5 minutes
3. **High Error Rate** - Error rate > 5% for 5 minutes
4. **Memory Usage** - Memory utilization > 80% for 5 minutes
5. **Authentication Failures** - > 10 failures per minute
6. **Firestore Latency** - Read latency > 500ms
7. **Budget Alerts** - At 50%, 80%, and 100% of monthly budget

### Monitoring Dashboard

Access the dashboard at: https://console.cloud.google.com/monitoring/dashboards

Dashboard includes:
- Service health overview
- Request latency (P95)
- Error rates
- Memory usage
- Authentication metrics
- Business event tracking

### Log-Based Metrics

- `auth_failures` - Count of authentication failures
- `high_latency_requests` - Requests taking > 2 seconds
- `error_responses` - HTTP 5xx responses

### Deployment

Deploy monitoring infrastructure:
```bash
./scripts/deployment/deploy-monitoring.sh
```

Test monitoring:
```bash
./scripts/testing/test-monitoring.sh
```

### Custom Monitoring in Code

```typescript
// Track business events
this.monitoring.trackBusinessEvent('user_registration', 'success', {
  authProvider: 'local'
});

// Track authentication failures
this.monitoring.trackAuthFailure('invalid_password', email);

// Create alerts
this.monitoring.createAlert('security', 'Suspicious activity detected', 'high', {
  ip: req.ip,
  attempts: failedAttempts
});
```

### Alert Notifications

Alerts are sent to the configured email address. To update:
```bash
ALERT_EMAIL=newemail@example.com ./scripts/deployment/deploy-monitoring.sh
```

## Future Enhancements

1. **Google OAuth Integration** - Structure is ready, just needs implementation
2. **Email Verification** - Send verification emails for local registrations
3. **Password Reset** - Implement forgot password flow
4. **2FA Support** - Add two-factor authentication
5. **Session Management** - Add ability to view/revoke active sessions
6. **Slack/PagerDuty Integration** - Additional alert channels
7. **SLO Monitoring** - Service Level Objective tracking
8. **Distributed Tracing** - End-to-end request tracing