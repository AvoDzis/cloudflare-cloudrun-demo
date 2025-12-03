const express = require('express');
const path = require('path');
const logger = require('./src/utils/logger');
const httpLogger = require('./src/middleware/logger');
const { testConnection, closePool } = require('./src/config/database');

// Routes
const indexRouter = require('./src/routes/index');
const healthRouter = require('./src/routes/health');
const apiRouter = require('./src/routes/api');

const app = express();
const PORT = process.env.PORT || 8080;

// HTTP request logging middleware
app.use(httpLogger);

// Serve static files
app.use('/static', express.static(path.join(__dirname, 'static'), {
  maxAge: '1h',
  setHeaders: (res, filePath) => {
    res.set('Cache-Control', 'public, max-age=3600');
  }
}));

// Routes
app.use('/', indexRouter);
app.use('/', healthRouter);
app.use('/', apiRouter);

// 404 handler
app.use((req, res) => {
  res.status(404).send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>404 Not Found</title>
      <link rel="stylesheet" href="/static/style.css">
    </head>
    <body>
      <div class="container">
        <h1>404 - Not Found</h1>
        <p>The page you're looking for doesn't exist.</p>
        <a href="/">Go Home</a>
      </div>
    </body>
    </html>
  `);
});

// Error handler
app.use((err, req, res, next) => {
  logger.error({ err }, 'Unhandled error');
  res.status(500).json({
    error: 'Internal server error',
    message: err.message
  });
});

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  logger.info({ signal }, 'Received shutdown signal, closing server gracefully');

  server.close(async () => {
    logger.info('HTTP server closed');
    await closePool();
    process.exit(0);
  });

  // Force shutdown after 10 seconds
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start server
let server;

const startServer = async () => {
  try {
    // Test database connection before starting server
    const dbConnected = await testConnection();

    if (!dbConnected) {
      logger.error('Failed to connect to database on startup');
      process.exit(1);
    }

    server = app.listen(PORT, '0.0.0.0', () => {
      logger.info({
        port: PORT,
        environment: process.env.ENVIRONMENT || 'development',
        nodeVersion: process.version
      }, 'Server started successfully');
    });
  } catch (err) {
    logger.error({ err }, 'Failed to start server');
    process.exit(1);
  }
};

startServer();
