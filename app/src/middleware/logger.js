const crypto = require('crypto');
const pinoHttp = require('pino-http');

// Behind Cloudflare the client address is in CF-Connecting-IP; otherwise take
// the first X-Forwarded-For hop added by the load balancer.
const clientIp = (req) => req.headers['cf-connecting-ip']
  || (req.headers['x-forwarded-for'] || '').split(',')[0].trim()
  || req.socket.remoteAddress;

// HTTP request logging middleware: one JSON line per request
const createHttpLogger = (logger) => pinoHttp({
  logger,
  genReqId: (req, res) => {
    const id = req.headers['x-request-id'] || crypto.randomUUID();
    res.setHeader('X-Request-Id', id);
    return id;
  },
  customLogLevel: (req, res, err) => {
    if (res.statusCode >= 500 || err) {
      return 'error';
    } else if (res.statusCode >= 400) {
      return 'warn';
    }
    return 'info';
  },
  customSuccessMessage: (req, res) => `${req.method} ${req.url} ${res.statusCode}`,
  customErrorMessage: (req, res, err) => `${req.method} ${req.url} ${res.statusCode} - ${err.message}`,
  customAttributeKeys: {
    responseTime: 'latency_ms'
  },
  serializers: {
    req: (req) => ({
      request_id: req.id,
      method: req.method,
      url: req.url,
      user_ip: clientIp(req.raw || req),
      user_agent: req.headers['user-agent']
    }),
    res: (res) => ({
      status_code: res.statusCode
    })
  }
});

module.exports = createHttpLogger;
