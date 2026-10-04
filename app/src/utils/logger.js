const pino = require('pino');

// pino level -> Cloud Logging severity (https://cloud.google.com/logging/docs/structured-logging)
const SEVERITY = {
  trace: 'DEBUG',
  debug: 'DEBUG',
  info: 'INFO',
  warn: 'WARNING',
  error: 'ERROR',
  fatal: 'CRITICAL'
};

// JSON logs on stdout. Cloud Run forwards them to Cloud Logging, which reads
// `severity` and `message` as the entry's severity and summary.
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  messageKey: 'message',
  formatters: {
    level: (label) => ({ severity: SEVERITY[label] || 'DEFAULT' })
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  base: {
    environment: process.env.ENVIRONMENT || 'development'
  }
});

module.exports = logger;
