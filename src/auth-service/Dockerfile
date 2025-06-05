# Multi-stage build for secure authentication service
FROM --platform=linux/amd64 node:18-alpine AS base

# Install security updates
RUN apk update && apk upgrade && apk add --no-cache \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -g 1001 -S athena && \
    adduser -S athena -u 1001

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Development stage
FROM base AS dev
RUN npm ci
COPY . .
RUN npm run build

# Production dependencies
FROM base AS prod-deps
RUN npm ci --only=production

# Production stage
FROM base AS production
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=dev /app/dist ./dist
COPY --from=dev /app/package.json ./

# Security hardening
RUN chown -R athena:athena /app
USER athena

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://localhost:8081/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

# Expose port
EXPOSE 8081

# Start service
CMD ["node", "dist/src/auth-service/index.js"]