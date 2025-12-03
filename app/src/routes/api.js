const express = require('express');
const { pool } = require('../config/database');
const logger = require('../utils/logger');

const router = express.Router();

// GET /api/quote - Get random quote as JSON
router.get('/api/quote', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, quote, author, created_at FROM quotes ORDER BY RANDOM() LIMIT 1'
    );

    if (result.rows.length === 0) {
      logger.warn('No quotes found in database');
      return res.status(404).json({
        error: 'No quotes found',
        message: 'The database is empty'
      });
    }

    const quote = result.rows[0];

    res.set('Cache-Control', 'public, max-age=300');
    res.status(200).json({
      id: quote.id,
      quote: quote.quote,
      author: quote.author,
      created_at: quote.created_at
    });

    logger.info({ quoteId: quote.id }, 'Served random quote via API');
  } catch (err) {
    logger.error({ err }, 'Error fetching quote via API');
    res.status(500).json({
      error: 'Internal server error',
      message: 'Unable to fetch quote'
    });
  }
});

module.exports = router;
