const express = require('express');
const { escapeHtml, renderPage } = require('../utils/html');
const { randomQuote } = require('../quotes');

// GET / - Main page with random quote
module.exports = ({ pool, logger }) => {
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      const quote = await randomQuote(pool);

      if (!quote) {
        logger.warn('No quotes found in database');
        return res.status(404).send(renderPage('Quote App', `
          <h1>No Quotes Found</h1>
          <p>The database is empty. Please initialize it with quotes.</p>`));
      }

      res.set('Cache-Control', 'public, max-age=300');
      res.send(renderPage('Quote of the Moment', `
          <h1>Quote of the Moment</h1>
          <div class="quote-card">
            <blockquote>
              <p class="quote-text">"${escapeHtml(quote.quote)}"</p>
              <footer class="quote-author">— ${escapeHtml(quote.author || 'Anonymous')}</footer>
            </blockquote>
          </div>
          <div class="actions">
            <button type="button" id="another-quote">Get Another Quote</button>
            <a href="/api/quote">View as JSON</a>
          </div>`));

      logger.info({ quoteId: quote.id }, 'Served random quote');
    } catch (err) {
      logger.error({ err }, 'Error fetching quote');
      res.status(500).send(renderPage('Error', `
          <h1>Error</h1>
          <p>Unable to fetch quote. Please try again later.</p>`));
    }
  });

  return router;
};
