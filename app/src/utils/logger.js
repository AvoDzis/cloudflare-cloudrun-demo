const pino = require('pino');

// Create Pino logger with JSON output for Cloud Logging
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => {
      return { severity: label.toUpperCase() };
    }
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  base: {
    environment: process.env.ENVIRONMENT || 'development'
  }
});

module.exports = logger;
