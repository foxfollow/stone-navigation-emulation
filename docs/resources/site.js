// Shared behavior for the Stone Nav site: theme, copy buttons, screenshot modal, scroll effects.
// motion.js (landing pages only) wraps toggleTheme, openModal and closeModal with animated versions.
(function () {
    function readTheme() {
        try { return localStorage.getItem('theme') || 'dark'; } catch (e) { return 'dark'; }
    }
    let currentTheme = readTheme();

    function setTheme(theme) {
        currentTheme = theme;
        try { localStorage.setItem('theme', theme); } catch (e) { }
        const html = document.documentElement;
        const icon = document.getElementById('theme-icon-fa');
        const dark = theme === 'dark';
        html.classList.toggle('dark', dark);
        document.body.classList.toggle('bg-dark-900', dark);
        document.body.classList.toggle('text-white', dark);
        if (icon) icon.className = dark ? 'fa-solid fa-sun text-sm text-yellow-400' : 'fa-solid fa-moon text-sm text-gray-600';
    }
    window.toggleTheme = function () { setTheme(currentTheme === 'dark' ? 'light' : 'dark'); };

    window.showCopied = function (icon) {
        icon.className = 'fa-solid fa-check text-green-500';
        setTimeout(() => { icon.className = 'fa-regular fa-copy'; }, 2000);
    };

    // Any button with data-copy="#id" copies that element's text.
    function initCopy() {
        document.querySelectorAll('[data-copy]').forEach(btn => {
            btn.addEventListener('click', () => {
                const source = document.querySelector(btn.getAttribute('data-copy'));
                if (!source) return;
                const text = source.innerText.trim();
                const icon = btn.querySelector('i');
                if (navigator.clipboard && window.isSecureContext) {
                    navigator.clipboard.writeText(text).then(() => window.showCopied(icon), () => { });
                }
            });
        });
    }

    window.openModal = function (img, caption) {
        const modal = document.getElementById('imageModal');
        if (!modal) return;
        document.getElementById('modalImage').src = img.src;
        document.getElementById('modalImage').alt = img.alt;
        document.getElementById('modalCaption').textContent = caption;
        modal.style.display = 'flex';
        document.body.style.overflow = 'hidden';
    };
    window.closeModal = function () {
        const modal = document.getElementById('imageModal');
        if (!modal) return;
        modal.style.display = 'none';
        document.body.style.overflow = 'auto';
    };

    function initScrollFx() {
        const els = document.querySelectorAll('.reveal');
        if ('IntersectionObserver' in window) {
            const io = new IntersectionObserver(entries => {
                entries.forEach(e => {
                    if (e.isIntersecting) { e.target.classList.add('visible'); io.unobserve(e.target); }
                });
            }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
            els.forEach(el => io.observe(el));
        } else {
            els.forEach(el => el.classList.add('visible'));
        }
        const header = document.querySelector('.glass-nav');
        const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 8);
        window.addEventListener('scroll', onScroll, { passive: true });
        onScroll();
    }

    document.addEventListener('keydown', e => { if (e.key === 'Escape') window.closeModal(); });
    document.addEventListener('DOMContentLoaded', () => { setTheme(currentTheme); initCopy(); initScrollFx(); });
})();
