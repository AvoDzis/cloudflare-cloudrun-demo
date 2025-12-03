const { Pool } = require('pg');
const logger = require('../utils/logger');

// PostgreSQL connection pool configuration
const pool = new Pool({
  host: process.env.DB_HOST,
  port: 5432,
  database: process.env.DB_NAME || 'labdb',
  user: process.env.DB_USER || 'labuser',
  password: process.env.DB_PASSWORD,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

// Test connection on startup
pool.on('connect', () => {
  logger.info('Connected to PostgreSQL database');
});

pool.on('error', (err) => {
  logger.error({ err }, 'Unexpected PostgreSQL pool error');
});

// Test database connectivity
const testConnection = async () => {
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();
    logger.info('Database connection test successful');
    return true;
  } catch (err) {
    logger.error({ err }, 'Database connection test failed');
    return false;
  }
};

// Graceful shutdown
const closePool = async () => {
  try {
    await pool.end();
    logger.info('PostgreSQL pool closed');
  } catch (err) {
    logger.error({ err }, 'Error closing PostgreSQL pool');
  }
};

module.exports = {
  pool,
  testConnection,
  closePool
};
