import './style.css'

document.querySelector('#app').innerHTML = `
  <div class="bg-noise"></div>
  <div class="bg-blob bg-blob-1"></div>
  <div class="bg-blob bg-blob-2"></div>
  <div class="bg-blob bg-blob-3"></div>

  <nav>
    <div class="nav-inner">
      <a href="/" class="logo-link">Mend.ly</a>
      <a href="#" class="nav-cta">Download</a>
    </div>
  </nav>

  <main>
    <section class="hero">
      <div class="hero-text">
        <h1>Therapy that fits<br/><span class="gradient-text">your life</span></h1>
        <p class="subtitle">
          Mend.ly is a private AI companion that helps you process
          your thoughts, build healthier habits, and feel heard — anytime,
          anywhere.
        </p>
        <div class="cta-row">
          <a href="#" class="app-store-badge" aria-label="Download on the App Store">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40" width="180" height="60">
              <rect width="120" height="40" rx="6" fill="#000"/>
              <g fill="#fff">
                <path d="M24.77 20.3a4.95 4.95 0 0 1 2.36-4.15 5.07 5.07 0 0 0-3.99-2.16c-1.68-.18-3.31 1.01-4.17 1.01-.87 0-2.2-.99-3.63-.96a5.33 5.33 0 0 0-4.49 2.74c-1.93 3.34-.49 8.27 1.36 10.97.93 1.33 2.02 2.81 3.45 2.76 1.39-.06 1.92-.89 3.6-.89 1.68 0 2.16.89 3.62.86 1.5-.03 2.44-1.34 3.33-2.68a11.05 11.05 0 0 0 1.52-3.11 4.78 4.78 0 0 1-2.96-4.39z"/>
                <path d="M22.04 12.21a4.87 4.87 0 0 0 1.12-3.49 4.96 4.96 0 0 0-3.21 1.66 4.64 4.64 0 0 0-1.14 3.37 4.11 4.11 0 0 0 3.23-1.54z"/>
              </g>
              <g fill="#fff" font-family="Inter, -apple-system, sans-serif">
                <text x="42.5" y="15.5" font-size="5.8" letter-spacing="0.04em">Download on the</text>
                <text x="42.5" y="27.5" font-size="12" font-weight="600" letter-spacing="-0.02em">App Store</text>
              </g>
            </svg>
          </a>
        </div>
        <p class="privacy-note">No account required. No data stored. Encrypted end-to-end.</p>
      </div>

      <div class="hero-device">
        <div class="iphone-frame">
          <div class="iphone-notch"></div>
          <div class="iphone-screen">
            <img src="/screenshot.png" alt="Mend.ly app screenshot" class="screenshot" />
          </div>
          <div class="iphone-home-bar"></div>
        </div>
      </div>
    </section>

    <div class="section-divider"></div>

    <section id="features" class="features">
      <h2 class="section-heading">Why Mend.ly?</h2>
      <div class="features-grid">
        <div class="feature-card fade-up" style="--delay: 0s">
          <div class="feature-icon feature-icon--sage">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          </div>
          <h3>Private by Design</h3>
          <p>No account needed, no personal data stored, and all communication is securely encrypted.</p>
        </div>
        <div class="feature-card fade-up" style="--delay: 0.1s">
          <div class="feature-icon feature-icon--clay">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
          </div>
          <h3>Natural Conversations</h3>
          <p>Talk through what's on your mind with a compassionate AI that actually listens.</p>
        </div>
        <div class="feature-card fade-up" style="--delay: 0.2s">
          <div class="feature-icon feature-icon--sand">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
          </div>
          <h3>Always Available</h3>
          <p>No appointments, no waitlists. Open the app whenever you need support.</p>
        </div>
      </div>
    </section>
  </main>

  <footer>
    <div class="footer-inner">
      <div class="footer-links">
        <a href="/privacy.html">Privacy Policy</a>
        <a href="/support.html">Support</a>
      </div>
      <p>&copy; 2025 Mend.ly. All rights reserved.</p>
    </div>
  </footer>
`

// Intersection Observer for fade-up animations
const observer = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible')
      observer.unobserve(entry.target)
    }
  })
}, { threshold: 0.15 })

document.querySelectorAll('.fade-up').forEach(el => observer.observe(el))
