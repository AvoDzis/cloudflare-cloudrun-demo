const express = require('express');
const { randomQuote } = require('../quotes');

// GET /api/quote - Get random quote as JSON
module.exports = ({ pool, logger }) => {
  const router = express.Router();

  router.get('/api/quote', async (req, res) => {
    try {
      const quote = await randomQuote(pool);

      if (!quote) {
        logger.warn('No quotes found in database');
        return res.status(404).json({
          error: 'No quotes found',
          message: 'The database is empty'
        });
      }

      res.set('Cache-Control', 'public, max-age=300');
      res.status(200).json(quote);

      logger.info({ quoteId: quote.id }, 'Served random quote via API');
    } catch (err) {
      logger.error({ err }, 'Error fetching quote via API');
      res.status(500).json({
        error: 'Internal server error',
        message: 'Unable to fetch quote'
      });
    }
  });

  return router;
};
