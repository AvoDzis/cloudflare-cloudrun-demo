// Client-side script for the quote app (no inline handlers, so the CSP can stay strict)

document.addEventListener('DOMContentLoaded', () => {
  // Fade-in animation for the quote card
  const quoteCard = document.querySelector('.quote-card');
  if (quoteCard) {
    quoteCard.style.opacity = '0';
    quoteCard.style.transform = 'translateY(20px)';
    quoteCard.style.transition = 'opacity 0.5s ease, transform 0.5s ease';

    setTimeout(() => {
      quoteCard.style.opacity = '1';
      quoteCard.style.transform = 'translateY(0)';
    }, 100);
  }

  const anotherQuote = document.getElementById('another-quote');
  if (anotherQuote) {
    anotherQuote.addEventListener('click', () => location.reload());
  }

  // Click animation for buttons
  document.querySelectorAll('button').forEach((button) => {
    button.addEventListener('click', () => {
      button.style.transform = 'scale(0.95)';
      setTimeout(() => {
        button.style.transform = 'scale(1)';
      }, 100);
    });
  });
});
