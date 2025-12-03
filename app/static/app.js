// Simple client-side script for the quote app

document.addEventListener('DOMContentLoaded', () => {
  console.log('Quote app loaded successfully');

  // Add fade-in animation to quote card
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

  // Add click animation to buttons
  const buttons = document.querySelectorAll('button');
  buttons.forEach(button => {
    button.addEventListener('click', (e) => {
      button.style.transform = 'scale(0.95)';
      setTimeout(() => {
        button.style.transform = 'scale(1)';
      }, 100);
    });
  });
});
