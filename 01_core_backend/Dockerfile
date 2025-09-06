# StudyAI API Gateway - Multi-stage Production Dockerfile
# Optimized for production deployment with development capabilities

# =====================================
# Stage 1: Base Dependencies
# =====================================
FROM node:20-alpine AS base

# Set working directory
WORKDIR /app

# Install system dependencies for native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    git \
    curl

# Copy package files for dependency installation
COPY package*.json ./

# =====================================
# Stage 2: Development Dependencies
# =====================================
FROM base AS development

# Install all dependencies (including devDependencies)
RUN npm ci --include=dev

# Copy source code
COPY . .

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S studyai -u 1001 -G nodejs

# Change ownership of app directory
RUN chown -R studyai:nodejs /app
USER studyai

# Expose development port
EXPOSE 3001

# Health check for development
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1

# Development command with hot reload
CMD ["npm", "run", "dev"]

# =====================================
# Stage 3: Production Dependencies
# =====================================
FROM base AS production-deps

# Set production environment
ENV NODE_ENV=production

# Install only production dependencies
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# =====================================
# Stage 4: Production Build
# =====================================
FROM node:20-alpine AS production

# Set production environment variables
ENV NODE_ENV=production
ENV PORT=3001
ENV HOST=0.0.0.0

# Install runtime dependencies
RUN apk add --no-cache \
    curl \
    dumb-init

# Create app directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S studyai -u 1001 -G nodejs

# Copy production dependencies
COPY --from=production-deps --chown=studyai:nodejs /app/node_modules ./node_modules

# Copy application code
COPY --chown=studyai:nodejs . .

# Remove development files
RUN rm -rf \
    tests/ \
    scripts/test-* \
    .eslintrc* \
    .gitignore \
    *.md \
    docker-compose.*.yml

# Create directories for logs and reports
RUN mkdir -p logs reports && \
    chown -R studyai:nodejs logs reports

# Switch to non-root user
USER studyai

# Expose application port
EXPOSE 3001

# Health check for production
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1

# Use dumb-init for proper signal handling
ENTRYPOINT ["dumb-init", "--"]

# Production command
CMD ["node", "src/gateway/index.js"]

# =====================================
# Stage 5: Testing (Optional)
# =====================================
FROM development AS testing

# Install testing dependencies if not already present
RUN npm ci --include=dev

# Copy test files
COPY tests/ ./tests/
COPY scripts/ ./scripts/

# Run tests
RUN npm test

# This stage can be used in CI/CD for testing before production build