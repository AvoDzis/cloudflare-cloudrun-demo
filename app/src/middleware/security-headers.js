// Baseline browser security headers for every response.
const HEADERS = {
  'Content-Security-Policy': "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'Strict-Transport-Security': 'max-age=31536000',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer'
};

const securityHeaders = (req, res, next) => {
  res.set(HEADERS);
  next();
};

module.exports = securityHeaders;
