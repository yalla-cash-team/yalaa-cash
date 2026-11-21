// Progressive enhancement only: the page is fully usable without this script.
// All download / contact links live in index.html (single source of truth).
(function () {
  'use strict';

  var hasIO = 'IntersectionObserver' in window;
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Scroll reveals for sections below the hero.
  var items = document.querySelectorAll('.reveal');
  if (!hasIO) {
    items.forEach(function (el) { el.classList.add('in'); });
  } else {
    var reveal = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); reveal.unobserve(e.target); }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
    items.forEach(function (el) { reveal.observe(el); });
  }

  // Header gains a hairline once the page scrolls.
  var header = document.getElementById('site-header');
  if (header) {
    var onScroll = function () { header.classList.toggle('scrolled', window.scrollY > 8); };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
  }

  var stage = document.getElementById('stage');

  // Pause the endless phone loops while the hero is off screen.
  if (stage && hasIO) {
    new IntersectionObserver(function (en) {
      stage.classList.toggle('is-paused', !en[0].isIntersecting);
    }).observe(stage);
  }

  // Desktop only: very subtle mouse-responsive parallax on the phones.
  var finePointer = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine) and (min-width: 900px)');
  if (stage && !reduceMotion && finePointer && finePointer.matches) {
    var tx = 0, ty = 0, raf = 0;
    var apply = function () {
      raf = 0;
      stage.style.setProperty('--mx', tx.toFixed(3));
      stage.style.setProperty('--my', ty.toFixed(3));
    };
    var queue = function () { if (!raf) raf = requestAnimationFrame(apply); };
    window.addEventListener('pointermove', function (e) {
      var r = stage.getBoundingClientRect();
      if (r.bottom < 0 || r.top > window.innerHeight) return;
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      tx = Math.max(-1, Math.min(1, (e.clientX - cx) / (window.innerWidth / 2)));
      ty = Math.max(-1, Math.min(1, (e.clientY - cy) / (window.innerHeight / 2)));
      queue();
    }, { passive: true });
    document.documentElement.addEventListener('pointerleave', function () { tx = 0; ty = 0; queue(); });
  }

  // Floating download button (mobile CSS only shows it below 768px):
  // visible once the hero buttons have scrolled away, hidden again while the
  // closing section's own buttons are on screen.
  var floatBtn = document.getElementById('float-cta');
  var heroCta = document.getElementById('hero-cta');
  var finalCta = document.getElementById('final-cta');
  if (!floatBtn || !heroCta || !finalCta || !hasIO) return;

  var heroVisible = true, finalVisible = false;
  function update() {
    var show = !heroVisible && !finalVisible;
    floatBtn.classList.toggle('show', show);
    floatBtn.setAttribute('aria-hidden', show ? 'false' : 'true');
    floatBtn.tabIndex = show ? 0 : -1;
  }
  new IntersectionObserver(function (en) { heroVisible = en[0].isIntersecting; update(); }).observe(heroCta);
  new IntersectionObserver(function (en) { finalVisible = en[0].isIntersecting; update(); },
    { threshold: 0.2 }).observe(finalCta);
})();
