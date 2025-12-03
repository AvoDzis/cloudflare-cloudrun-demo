const express = require('express');
const { pool } = require('../config/database');
const logger = require('../utils/logger');

const router = express.Router();

// GET /health - Health check endpoint
router.get('/health', async (req, res) => {
  const healthcheck = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    database: 'unknown'
  };

  try {
    // Test database connectivity
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();

    healthcheck.database = 'connected';

    res.set('Cache-Control', 'no-cache');
    res.status(200).json(healthcheck);

  } catch (err) {
    logger.error({ err }, 'Health check failed - database connection error');

    healthcheck.status = 'unhealthy';
    healthcheck.database = 'disconnected';
    healthcheck.error = err.message;

    res.set('Cache-Control', 'no-cache');
    res.status(503).json(healthcheck);
  }
});

module.exports = router;
