const pinoHttp = require('pino-http');
const logger = require('../utils/logger');

// HTTP request logging middleware
const httpLogger = pinoHttp({
  logger,
  customLogLevel: (req, res, err) => {
    if (res.statusCode >= 500 || err) {
      return 'error';
    } else if (res.statusCode >= 400) {
      return 'warn';
    }
    return 'info';
  },
  customSuccessMessage: (req, res) => {
    return `${req.method} ${req.url} ${res.statusCode}`;
  },
  customErrorMessage: (req, res, err) => {
    return `${req.method} ${req.url} ${res.statusCode} - ${err.message}`;
  },
  serializers: {
    req: (req) => ({
      method: req.method,
      url: req.url,
      path: req.path,
      user_ip: req.headers['x-forwarded-for'] || req.connection.remoteAddress,
      user_agent: req.headers['user-agent']
    }),
    res: (res) => ({
      status_code: res.statusCode
    })
  }
});

module.exports = httpLogger;
