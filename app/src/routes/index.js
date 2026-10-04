const express = require('express');
const { pool } = require('../config/database');
const logger = require('../utils/logger');

const router = express.Router();

// Escape database values before putting them into HTML
const escapeHtml = (value) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

// GET / - Main page with random quote
router.get('/', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, quote, author, created_at FROM quotes ORDER BY RANDOM() LIMIT 1'
    );

    if (result.rows.length === 0) {
      logger.warn('No quotes found in database');
      return res.status(404).send(`
        <!DOCTYPE html>
        <html>
        <head>
          <title>Quote App</title>
          <link rel="stylesheet" href="/static/style.css">
        </head>
        <body>
          <div class="container">
            <h1>No Quotes Found</h1>
            <p>The database is empty. Please initialize it with quotes.</p>
          </div>
        </body>
        </html>
      `);
    }

    const quote = result.rows[0];

    res.set('Cache-Control', 'public, max-age=300');
    res.send(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>Quote of the Moment</title>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="/static/style.css">
      </head>
      <body>
        <div class="container">
          <h1>Quote of the Moment</h1>
          <div class="quote-card">
            <blockquote>
              <p class="quote-text">"${escapeHtml(quote.quote)}"</p>
              <footer class="quote-author">— ${escapeHtml(quote.author || 'Anonymous')}</footer>
            </blockquote>
          </div>
          <div class="actions">
            <button onclick="location.reload()">Get Another Quote</button>
            <a href="/api/quote">View as JSON</a>
          </div>
        </div>
        <script src="/static/app.js"></script>
      </body>
      </html>
    `);

    logger.info({ quoteId: quote.id }, 'Served random quote');
  } catch (err) {
    logger.error({ err }, 'Error fetching quote');
    res.status(500).send(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>Error</title>
        <link rel="stylesheet" href="/static/style.css">
      </head>
      <body>
        <div class="container">
          <h1>Error</h1>
          <p>Unable to fetch quote. Please try again later.</p>
        </div>
      </body>
      </html>
    `);
  }
});

module.exports = router;
