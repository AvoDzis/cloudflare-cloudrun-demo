const express = require('express');

module.exports = ({ pool, logger }) => {
  const router = express.Router();

  // GET /livez - process is up (Cloud Run liveness probe, Docker HEALTHCHECK).
  // Deliberately does not touch the database, so a DB outage doesn't restart instances.
  router.get('/livez', (req, res) => {
    res.set('Cache-Control', 'no-cache');
    res.status(200).json({ status: 'alive' });
  });

  // GET /health - app can reach the database (startup probe, uptime check)
  router.get('/health', async (req, res) => {
    const healthcheck = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      database: 'connected'
    };

    res.set('Cache-Control', 'no-cache');
    try {
      await pool.query('SELECT 1');
      res.status(200).json(healthcheck);
    } catch (err) {
      logger.error({ err }, 'Health check failed - database connection error');
      healthcheck.status = 'unhealthy';
      healthcheck.database = 'disconnected';
      res.status(503).json(healthcheck);
    }
  });

  return router;
};
