// Escape database values before putting them into HTML
const escapeHtml = (value) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

// Wraps page content in the shared layout. `body` must already be escaped.
const renderPage = (title, body) => `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <link rel="stylesheet" href="/static/style.css">
</head>
<body>
  <div class="container">${body}
  </div>
  <script src="/static/app.js"></script>
</body>
</html>`;

module.exports = { escapeHtml, renderPage };
