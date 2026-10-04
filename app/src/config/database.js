const { Pool } = require('pg');
const logger = require('../utils/logger');

// PostgreSQL connection pool. Connections are opened lazily, so the app starts
// even when the database is down; /health reports the outage.
const createPool = (env = process.env) => {
  const pool = new Pool({
    host: env.DB_HOST,
    port: Number(env.DB_PORT) || 5432,
    database: env.DB_NAME || 'labdb',
    user: env.DB_USER || 'labuser',
    password: env.DB_PASSWORD,
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  pool.on('error', (err) => {
    logger.error({ err }, 'Unexpected PostgreSQL pool error');
  });

  return pool;
};

module.exports = { createPool };
