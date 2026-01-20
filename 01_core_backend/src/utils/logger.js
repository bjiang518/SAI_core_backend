/**
 * Production-Safe Logger Utility
 *
 * Provides structured logging with automatic level control based on environment.
 *
 * - Development: DEBUG level (all logs visible)
 * - Production: WARN level (only warnings and errors)
 *
 * Usage:
 *   const logger = require('./utils/logger');
 *   logger.debug('Debug information');  // Only in development
 *   logger.info('Info message');        // Only in development
 *   logger.warn('Warning message');     // Always logged
 *   logger.error('Error message');      // Always logged
 */

const pino = require('pino');

// Determine log level based on environment
const getLogLevel = () => {
  if (process.env.LOG_LEVEL) {
    return process.env.LOG_LEVEL;
  }
  return process.env.NODE_ENV === 'production' ? 'warn' : 'debug';
};

// Configure Pino logger
const logger = pino({
  level: getLogLevel(),

  // Pretty printing in development only
  transport: process.env.NODE_ENV !== 'production' ? {
    target: 'pino-pretty',
    options: {
      colorize: true,
      translateTime: 'HH:MM:ss',
      ignore: 'pid,hostname'
    }
  } : undefined,

  // Base configuration
  base: {
    env: process.env.NODE_ENV || 'development'
  },

  // Timestamp in ISO format
  timestamp: () => `,"time":"${new Date().toISOString()}"`
});

// Log startup configuration
logger.info({
  logLevel: getLogLevel(),
  nodeEnv: process.env.NODE_ENV || 'development',
  productionMode: process.env.NODE_ENV === 'production'
}, 'Logger initialized');

module.exports = logger;
