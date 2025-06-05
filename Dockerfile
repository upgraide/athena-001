# Multi-stage Docker build for security and efficiency
FROM --platform=linux/amd64 node:18-alpine AS base

# Install security updates and required packages
RUN apk update && apk upgrade && \
    apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S athena -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Install dependencies stage
FROM base AS deps
COPY package*.json ./
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# Build stage
FROM base AS build
COPY package*.json ./
COPY tsconfig.json ./
RUN npm ci --ignore-scripts
COPY . .
RUN npm run build && \
    npm prune --production

# Runtime stage
FROM base AS runtime

# Copy built application
COPY --from=deps --chown=athena:nodejs /app/node_modules ./node_modules
COPY --from=build --chown=athena:nodejs /app/dist ./dist
COPY --from=build --chown=athena:nodejs /app/package.json ./

# Security: Run as non-root user
USER athena

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# Expose port
EXPOSE 8080

# Service-specific entry point
ARG SERVICE_NAME=finance-master
ENV SERVICE_NAME=$SERVICE_NAME

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["sh", "-c", "node dist/src/${SERVICE_NAME}/index.js"]