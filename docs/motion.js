(() => {
  'use strict';
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  const tour = document.getElementById('feature-tour');
  const slides = [...tour.querySelectorAll('.tour-slide')];
  const tabs = [...tour.querySelectorAll('[role="tab"]')];
  const track = tour.querySelector('.tour-track');
  const viewport = tour.querySelector('.tour-viewport');
  const pauseButton = document.getElementById('tour-motion');
  let selected = 0;
  let visible = false;
  let paused = false;
  let playLabel = document.documentElement.lang === 'zh-CN' ? '播放动效' : 'Play animation';
  let pauseLabel = pauseButton.textContent;
  function updateSceneMotion() {
    tour.classList.toggle('is-running', visible && !document.hidden && !reduce.matches && !paused);
    pauseButton.textContent = paused ? playLabel : pauseLabel;
    pauseButton.hidden = reduce.matches;
  }
  function selectSlide(index, focus = false) {
    selected = (index + slides.length) % slides.length;
    track.style.setProperty('--slide-offset', `${-100 * selected}%`);
    slides.forEach((slide, i) => {
      slide.classList.toggle('is-active', i === selected);
      slide.setAttribute('aria-hidden', String(i !== selected));
      slide.inert = i !== selected;
      tabs[i].setAttribute('aria-selected', String(i === selected));
      tabs[i].tabIndex = i === selected ? 0 : -1;
    });
    document.getElementById('tour-position').textContent = `0${selected + 1} / 0${slides.length}`;
    if (focus) tabs[selected].focus({ preventScroll: true });
  }
  tabs.forEach((tab, i) => tab.addEventListener('click', () => selectSlide(i)));
  document.getElementById('tour-prev').addEventListener('click', () => selectSlide(selected - 1));
  document.getElementById('tour-next').addEventListener('click', () => selectSlide(selected + 1));
  pauseButton.addEventListener('click', () => { paused = !paused; updateSceneMotion(); });
  tour.addEventListener('keydown', event => {
    const actions = { ArrowLeft: selected - 1, ArrowRight: selected + 1, Home: 0, End: slides.length - 1 };
    if (Object.prototype.hasOwnProperty.call(actions, event.key)) {
      event.preventDefault(); selectSlide(actions[event.key], true);
    }
  });
  let pointerStart;
  viewport.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    pointerStart = { x: event.clientX, y: event.clientY, id: event.pointerId };
    viewport.setPointerCapture(event.pointerId);
  });
  viewport.addEventListener('pointerup', event => {
    if (!pointerStart || pointerStart.id !== event.pointerId) return;
    const dx = event.clientX - pointerStart.x;
    const dy = event.clientY - pointerStart.y;
    if (Math.abs(dx) > 45 && Math.abs(dx) > Math.abs(dy) * 1.25) selectSlide(selected + (dx < 0 ? 1 : -1));
    pointerStart = undefined;
  });
  viewport.addEventListener('pointercancel', () => { pointerStart = undefined; });
  document.addEventListener('clipori-language', event => {
    playLabel = event.detail.play; pauseLabel = event.detail.pause; updateSceneMotion();
  });
  document.addEventListener('visibilitychange', updateSceneMotion);

  const revealTargets = document.querySelectorAll('.features .section-heading, .feature-tour, .privacy-note, .install-intro, .install-steps > li, .faq .section-heading, .faq-list, .closing');
  if ('IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) { entry.target.classList.add('is-visible'); revealObserver.unobserve(entry.target); }
      });
    }, { threshold: 0.12 });
    revealTargets.forEach((target, i) => {
      target.classList.add('reveal');
      target.style.setProperty('--reveal-delay', `${i % 3 * 65}ms`);
      revealObserver.observe(target);
    });
    const sceneObserver = new IntersectionObserver(entries => { visible = entries[0].isIntersecting; updateSceneMotion(); }, { threshold: 0.2 });
    sceneObserver.observe(tour);
  } else { visible = true; }
  const demo = document.getElementById('demo');
  const surround = demo.querySelector('.demo-surround');
  const hero = document.querySelector('.hero');
  let frame;
  function updateScrollMotion() {
    frame = undefined;
    if (reduce.matches) return;
    const progress = Math.min(1, Math.max(0, (innerHeight - demo.getBoundingClientRect().top) / (innerHeight * 0.8)));
    surround.style.setProperty('--demo-scale', String(0.955 + progress * 0.045));
    surround.style.setProperty('--demo-lift', `${32 * (1 - progress)}px`);
    hero.style.setProperty('--hero-drift', `${Math.min(scrollY * 0.16, 90)}px`);
  }
  function queueScrollMotion() { if (!frame && !reduce.matches) frame = requestAnimationFrame(updateScrollMotion); }
  addEventListener('scroll', queueScrollMotion, { passive: true });
  addEventListener('resize', queueScrollMotion);
  function updateMotionPreference() {
    document.documentElement.classList.toggle('has-motion', !reduce.matches && 'IntersectionObserver' in window);
    updateSceneMotion(); queueScrollMotion();
  }
  if (reduce.addEventListener) reduce.addEventListener('change', updateMotionPreference);
  updateMotionPreference();
})();
