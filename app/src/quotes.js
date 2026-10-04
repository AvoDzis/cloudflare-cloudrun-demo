// Returns one random row from the quotes table, or undefined if it is empty.
const randomQuote = async (pool) => {
  const result = await pool.query(
    'SELECT id, quote, author, created_at FROM quotes ORDER BY RANDOM() LIMIT 1'
  );
  return result.rows[0];
};

module.exports = { randomQuote };
