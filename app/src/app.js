const express = require('express');
const path = require('path');
const defaultLogger = require('./utils/logger');
const createHttpLogger = require('./middleware/logger');
const securityHeaders = require('./middleware/security-headers');
const requireCloudflareSecret = require('./middleware/cloudflare-secret');
const { renderPage } = require('./utils/html');
const indexRoutes = require('./routes/index');
const apiRoutes = require('./routes/api');
const healthRoutes = require('./routes/health');

// Builds the Express app. The pool is injected so tests can pass a fake one.
const createApp = ({ pool, cloudflareSecret, logger = defaultLogger }) => {
  const app = express();
  app.disable('x-powered-by');

  app.use(createHttpLogger(logger));
  app.use(securityHeaders);

  // Health endpoints are reached directly (DNS-only record, uptime checks),
  // so they are registered before the Cloudflare secret check.
  app.use(healthRoutes({ pool, logger }));

  if (cloudflareSecret) {
    app.use(requireCloudflareSecret(cloudflareSecret));
  } else {
    logger.warn('CLOUDFLARE_SECRET is not set; requests are not checked for the Cloudflare origin header');
  }

  app.use('/static', express.static(path.join(__dirname, '..', 'static'), {
    setHeaders: (res) => {
      res.set('Cache-Control', 'public, max-age=3600');
    }
  }));

  app.use(indexRoutes({ pool, logger }));
  app.use(apiRoutes({ pool, logger }));

  app.use((req, res) => {
    res.status(404).send(renderPage('404 - Not Found', `
      <h1>404 - Not Found</h1>
      <p>The page you're looking for doesn't exist.</p>
      <a href="/">Go Home</a>`));
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    logger.error({ err }, 'Unhandled error');
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
};

module.exports = { createApp };
