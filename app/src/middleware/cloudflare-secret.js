const crypto = require('crypto');

const HEADER = 'x-cloudflare-secret';

// Cloudflare adds this header to every proxied request (Transform Rule in
// terraform/modules/cloudflare). Requests that reach the origin without it
// did not come through our Cloudflare zone and are rejected.
const requireCloudflareSecret = (secret) => {
  const expected = crypto.createHash('sha256').update(secret).digest();

  return (req, res, next) => {
    const provided = crypto.createHash('sha256').update(req.get(HEADER) || '').digest();
    if (crypto.timingSafeEqual(provided, expected)) {
      return next();
    }
    res.status(403).json({ error: 'Forbidden' });
  };
};

module.exports = requireCloudflareSecret;
