const logger = require('./src/utils/logger');
const { createPool } = require('./src/config/database');
const { createApp } = require('./src/app');

const PORT = Number(process.env.PORT) || 8080;

const pool = createPool();
const app = createApp({ pool, cloudflareSecret: process.env.CLOUDFLARE_SECRET });

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info({
    port: PORT,
    environment: process.env.ENVIRONMENT || 'development',
    nodeVersion: process.version
  }, 'Server started');
});

// Graceful shutdown: Cloud Run sends SIGTERM and allows 10 seconds
const gracefulShutdown = (signal) => {
  logger.info({ signal }, 'Received shutdown signal, closing server gracefully');

  server.close(async () => {
    logger.info('HTTP server closed');
    try {
      await pool.end();
      logger.info('PostgreSQL pool closed');
    } catch (err) {
      logger.error({ err }, 'Error closing PostgreSQL pool');
    }
    process.exit(0);
  });

  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 9000).unref();
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
