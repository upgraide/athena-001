// Quick local test for authentication
const express = require('express');
const app = express();
app.use(express.json());

// Mock JWT service for testing
const users = new Map();
const tokens = new Map();

app.post('/api/v1/auth/register', (req, res) => {
  const { email, password, firstName, lastName } = req.body;
  
  if (users.has(email)) {
    return res.status(409).json({ error: 'Email already registered' });
  }
  
  const userId = 'user_' + Date.now();
  users.set(email, { userId, password, firstName, lastName });
  
  const token = 'mock_token_' + userId;
  tokens.set(token, { userId, email });
  
  res.status(201).json({
    message: 'Registration successful',
    user: { id: userId, email, firstName, lastName, role: 'user' },
    tokens: { accessToken: token, refreshToken: 'refresh_' + token }
  });
});

app.post('/api/v1/auth/login', (req, res) => {
  const { email, password } = req.body;
  const user = users.get(email);
  
  if (!user || user.password !== password) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  
  const token = 'mock_token_' + user.userId;
  tokens.set(token, { userId: user.userId, email });
  
  res.json({
    message: 'Login successful',
    user: { id: user.userId, email, firstName: user.firstName, lastName: user.lastName },
    tokens: { accessToken: token, refreshToken: 'refresh_' + token }
  });
});

app.get('/api/v1/auth/health', (req, res) => {
  res.json({ service: 'auth-service', status: 'healthy' });
});

const PORT = 8081;
app.listen(PORT, () => {
  console.log(`Mock auth service running on port ${PORT}`);
  console.log('Test with: ./scripts/testing/test-auth.sh local');
});