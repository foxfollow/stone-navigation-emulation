/*
 * Landing page motion, shared by index.html and index-ua.html.
 * Loaded with `defer` after site.js, so it can wrap toggleTheme, openModal,
 * closeModal and showCopied, and runs before site.js starts the scroll reveal.
 * With "reduce motion" on, only a still frame of the navigation demo is built.
 */
(() => {
    const root = document.documentElement;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const finePointer = matchMedia('(hover: hover) and (pointer: fine)').matches;
    const $ = (sel, el = document) => el.querySelector(sel);
    const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];
    const EASE_OUT = 'cubic-bezier(0.16, 1, 0.3, 1)';
    const SVG = 'http://www.w3.org/2000/svg';
    const lang = root.lang === 'uk' ? 'uk' : 'en';

    const hero = $('main > section');

    // ---------- Navigation demo (hero) ----------
    // Mirrors the app's screen: maneuver banner, mode card, the route under a
    // fixed puck and the bottom panel. One loop: GPS → GPS lost (dead reckoning
    // keeps driving, +5 km/h) → a spoofed fix is rejected → GPS comes back.
    const TEXT = {
        uk: {
            gps: 'GPS', dr: 'Розрахункова позиція', snapped: "прив'язано до дороги", lost: 'помилка геолокації',
            spoof: 'підміна: стрибок позиції', noGps: 'без GPS', acc: '±5 м', pause: 'Пауза', back: '← 50 м', fwd: '50 м →',
            kmh: 'км/год', arrival: 'прибуття', min: 'хв', km: 'км', m: 'м', dec: ',', in: 'через', here: 'поруч',
            right: 'Тримайтеся правіше', left: 'Тримайтеся лівіше', straight: 'Прямо до пункту призначення',
            streets: ['на набережну', 'на міст', 'на проспект', 'на вулицю Садову'],
            kicker: 'Можлива підміна GPS', title: 'GPS показує інше місце. Перейти на GPS?',
            body: 'Нова точка за 1,5 км від розрахункової позиції. Авто не могло так швидко переміститися.',
            keep: 'Лишити розрахункову', take: 'Перейти на GPS', last: 'GPS',
            caption: ['GPS веде', 'GPS зник', 'Підміну відхилено', 'GPS повернувся'],
            pins: ['АЗС', 'Аптека', "Кав'ярня", 'Супермаркет', 'Паркінг'],
        },
        en: {
            gps: 'GPS', dr: 'Dead reckoning', snapped: 'snapped to road', lost: 'location error',
            spoof: 'spoofing: position jump', noGps: 'no GPS', acc: '±5 m', pause: 'Pause', back: '← 50 m', fwd: '50 m →',
            kmh: 'km/h', arrival: 'arrival', min: 'min', km: 'km', m: 'm', dec: '.', in: 'in', here: 'here',
            right: 'Keep right', left: 'Keep left', straight: 'Straight to destination',
            streets: ['onto the embankment', 'onto the bridge', 'onto the avenue', 'onto Garden Street'],
            kicker: 'Possible GPS spoofing', title: 'GPS shows another place. Switch to GPS?',
            body: 'The new fix is 1.5 km from the estimated position. A car could not have moved that fast.',
            keep: 'Keep estimate', take: 'Switch to GPS', last: 'GPS',
            caption: ['GPS leads', 'GPS lost', 'Spoof rejected', 'GPS is back'],
            pins: ['Gas station', 'Pharmacy', 'Café', 'Supermarket', 'Parking'],
        },
    }[lang];

    const ROUTE = 'M 0 140 L 0 -260 Q 0 -300 36 -318 L 204 -402 Q 240 -420 240 -460 L 240 -700 ' +
        'Q 240 -740 204 -758 L 36 -842 Q 0 -860 0 -900 L 0 -1400';
    const PINS = [
        { x: 26, y: -150, color: '#3dcf91', icon: 'fa-gas-pump', side: 1 },
        { x: 88, y: -376, color: '#f25c7a', icon: 'fa-prescription-bottle-medical', side: -1 },
        { x: 214, y: -600, color: '#d1945c', icon: 'fa-mug-hot', side: -1 },
        { x: 131, y: -822, color: '#ff8fab', icon: 'fa-cart-shopping', side: 1 },
        { x: -26, y: -1010, color: '#4080f2', icon: 'fa-square-parking', side: -1 },
    ];
    const LOOP = 26, LOST_AT = 6, BOOST_AT = 11, SPOOF_AT = 13.6, SHEET = [14, 17.2], KEEP_AT = 16.5, BACK_AT = 19.5;
    const METERS = 6; // metres per map unit
    const PUCK = { x: 165, y: 640 * 0.53 };
    const WORLD = { x: -420, y: -1620, w: 1080, h: 2060 }; // map bounds in map units

    function initNavDemo() {
        const host = $('.nav-demo');
        if (!host) return;
        const el = (tag, attrs = {}, parent) => {
            const node = document.createElementNS(SVG, tag);
            Object.entries(attrs).forEach(([k, v]) => node.setAttribute(k, v));
            if (parent) parent.append(node);
            return node;
        };
        const u = n => `calc(${n} * var(--u))`;
        const place = (node, x, y) => { node.style.left = u(x - WORLD.x); node.style.top = u(y - WORLD.y); };

        host.innerHTML =
            '<div class="nd" aria-hidden="true">' +
            `<div class="nd-pan"><svg viewBox="${WORLD.x} ${WORLD.y} ${WORLD.w} ${WORLD.h}"></svg></div>` +
            '<div class="nd-puck"><div class="nd-halo"></div><div class="nd-dot"><i class="fa-solid fa-location-arrow"></i></div></div>' +
            '<div class="nd-status"><span class="nd-clock"></span><span><i class="fa-solid fa-signal"></i><i class="fa-solid fa-wifi"></i><i class="fa-solid fa-battery-three-quarters"></i></span></div>' +
            '<div class="nd-top">' +
            '<div class="nd-card nd-man"><div class="nd-man-icon"><i class="fa-solid fa-arrow-up"></i></div><div><div class="nd-man-dist"></div><div class="nd-man-text"></div></div></div>' +
            '<div class="nd-card nd-mode"><div class="nd-mode-icon"><i class="fa-solid fa-location-arrow"></i></div>' +
            '<div><div class="nd-mode-title"><span class="nd-swap"></span></div><div class="nd-mode-sub"><span class="nd-swap"></span></div></div>' +
            '<div class="nd-mode-right"></div></div>' +
            '</div>' +
            '<div class="nd-panel"><div class="nd-eta"><b class="nd-arr"></b><span>' + TEXT.arrival + '</span><span class="nd-rem"></span></div>' +
            '<div class="nd-row r1"><div class="nd-btn pause"><i class="fa-solid fa-pause"></i>' + TEXT.pause + '</div><div class="nd-btn minus">−5</div>' +
            '<div class="nd-speed"><b>45</b><span>' + TEXT.kmh + '</span></div><div class="nd-btn plus">+5</div></div>' +
            '<div class="nd-row r2"><div class="nd-btn gps"><i class="fa-solid fa-location-arrow"></i>GPS</div><div class="nd-btn">' + TEXT.back + '</div><div class="nd-btn">' + TEXT.fwd + '</div></div></div>' +
            '<div class="nd-sheet"><div class="nd-sheet-kicker">' + TEXT.kicker + '</div><div class="nd-sheet-title">' + TEXT.title + '</div>' +
            '<div class="nd-sheet-text">' + TEXT.body + '</div><div class="nd-btn keep">◆&nbsp;' + TEXT.keep + '</div><div class="nd-btn">' + TEXT.take + '</div></div>' +
            '<div class="nd-replay"></div>' +
            '</div>' +
            '<div class="nav-demo-caption">' + TEXT.caption.map((c, i) =>
                `<span data-step="${i}"><i class="fa-solid fa-circle" style="color:${['#4d8cff', '#f2a63b', '#ff6b5e', '#4d8cff'][i]}"></i>${c}</span>`).join('') + '</div>';

        const nd = $('.nd', host);
        const pan = $('.nd-pan', host);
        // Pixels per map unit for the per-frame transform; CSS sizes use var(--u) and scale on their own.
        let k = nd.clientWidth / 330;
        const world = $('.nd-pan svg', host);

        // Map, drawn once: city blocks, a few parks, a river under the bridge, then the route on top.
        const XS = [-400, -280, -160, -60, 110, 280, 380, 500, 640];
        el('path', { class: 'nd-water', d: 'M -420 -520 L 660 -610 L 660 -540 L -420 -450 Z' }, world);
        for (let y = 400, row = 0; y > -1560; y -= 120, row++) {
            for (let c = 0; c < XS.length - 1; c++) {
                const top = y - 120 + 9, h = 120 - 18, left = XS[c] + 9, w = XS[c + 1] - XS[c] - 18;
                if (top < -520 + 40 && top + h > -610) continue; // keep the river clear
                el('rect', { class: (row * 7 + c * 3) % 11 === 0 ? 'nd-park' : 'nd-block', x: left, y: top, width: w, height: h, rx: 8 }, world);
            }
        }
        const streets = el('g', { class: 'nd-street', 'stroke-width': 7 }, world);
        XS.forEach(x => el('line', { x1: x, y1: 420, x2: x, y2: -1600 }, streets));
        for (let y = 400; y > -1600; y -= 120) el('line', { x1: -420, y1: y, x2: 660, y2: y }, streets);
        el('path', { class: 'nd-road', d: ROUTE, 'stroke-width': 18 }, world);
        el('path', { class: 'nd-route-glow', d: ROUTE, 'stroke-width': 18 }, world);
        const route = el('path', { class: 'nd-route', d: ROUTE, 'stroke-width': 7 }, world);
        const total = route.getTotalLength();

        // Route geometry, sampled once: points, headings, turns and landmark positions along it.
        const STEP = 4, samples = [];
        for (let s = 0; s <= total; s += STEP) samples.push(route.getPointAtLength(s));
        const at = s => samples[Math.max(0, Math.min(samples.length - 1, Math.round(s / STEP)))];
        const heading = s => { const a = at(s - 6), b = at(s + 6); return Math.atan2(b.x - a.x, a.y - b.y); };
        const turns = [];
        for (let s = STEP, inCurve = false, start = 0; s < total - STEP; s += STEP) {
            const d = heading(s + STEP) - heading(s);
            if (Math.abs(d) > 0.01 && !inCurve) { inCurve = true; start = s; }
            if (Math.abs(d) <= 0.01 && inCurve) { inCurve = false; turns.push({ s: start, dir: Math.sign(heading(s) - heading(start - STEP)) }); }
        }
        const sOf = (x, y) => samples.reduce((best, p, i) => {
            const d = (p.x - x) ** 2 + (p.y - y) ** 2;
            return d < best.d ? { d, s: i * STEP } : best;
        }, { d: Infinity, s: 0 }).s;

        // Markers are small HTML layers inside the moving pan, so updating a label repaints only that label.
        const mark = (x, y, html) => {
            const node = document.createElement('div');
            node.className = 'nd-mark hide';
            node.innerHTML = html;
            place(node, x, y);
            pan.append(node);
            return node;
        };
        const pins = PINS.map((p, i) => {
            const node = mark(p.x, p.y,
                `<div class="nd-pin-dot" style="background:${p.color};--c:${p.color}"><i class="fa-solid ${p.icon}"></i></div>` +
                `<div class="nd-pin-label ${p.side > 0 ? 'r' : 'l'}">${TEXT.pins[i]}<b></b></div>`);
            return { node, dist: $('b', node), y: p.y, s: sOf(p.x, p.y), shown: false };
        });
        const lastGps = mark(0, 0, `<div class="nd-gps-dot"></div><div class="nd-gps-label">${TEXT.last}</div>`);
        const ghost = mark(0, 0, '<div class="nd-ghost-ring"></div><div class="nd-ghost-dot"></div>');

        const ui = {
            clock: $('.nd-clock', host), dist: $('.nd-man-dist', host), manText: $('.nd-man-text', host),
            manIcon: $('.nd-man-icon i', host), title: $('.nd-mode-title .nd-swap', host), sub: $('.nd-mode-sub .nd-swap', host),
            right: $('.nd-mode-right', host), modeIcon: $('.nd-mode-icon i', host), arrow: $('.nd-dot i', host),
            arr: $('.nd-arr', host), rem: $('.nd-rem', host), speed: $('.nd-speed', host), speedNum: $('.nd-speed b', host),
            plus: $('.nd-btn.plus', host), sheet: $('.nd-sheet', host), keep: $('.nd-btn.keep', host),
            replay: $('.nd-replay', host), caption: $$('.nav-demo-caption span', host),
        };

        const S0 = 140, END = total - 260;
        const v = (END - S0) / (BOOST_AT + (LOOP - BOOST_AT) * 50 / 45);
        const sAt = t => S0 + v * Math.min(t, BOOST_AT) + v * 50 / 45 * Math.max(0, t - BOOST_AT);
        const num = (x, digits) => x.toFixed(digits).replace('.', TEXT.dec);
        const meters = m => { const r = Math.max(10, Math.round(m / 10) * 10); return r >= 1000 ? `${num(m / 1000, 1)} ${TEXT.km}` : `${r} ${TEXT.m}`; };
        const hhmm = d => `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
        // Every DOM write goes through these, so a frame only touches what actually changed.
        const set = (node, text, swap) => {
            if (node.textContent === text) return;
            node.textContent = text;
            if (swap) { node.classList.remove('in'); void node.offsetWidth; node.classList.add('in'); }
        };
        const prop = (node, key, value) => { if (node.style[key] !== value) node.style[key] = value; };
        const cls = (node, name, on) => { if (node.classList.contains(name) !== on) node.classList.toggle(name, on); };
        const tap = node => { node.classList.add('tap'); setTimeout(() => node.classList.remove('tap'), 280); };
        let fired = {};

        // Every frame: only the map layer and the arrow move (both composited, no repaint).
        function move(t) {
            const s = sAt(t);
            const p = at(s);
            pan.style.transform = `translate3d(${((PUCK.x - p.x + WORLD.x) * k).toFixed(1)}px, ${((PUCK.y - p.y + WORLD.y) * k).toFixed(1)}px, 0)`;
            prop(ui.arrow, 'rotate', `${Math.round(heading(s) * 180 / Math.PI - 45)}deg`);
        }

        // A few times a second, like the app itself: texts, modes and markers.
        function render(t) {
            move(t);
            const s = sAt(t);
            const p = at(s);
            const dr = t >= LOST_AT && t < BACK_AT;
            cls(nd, 'dr', dr);
            set(ui.title, dr ? TEXT.dr : TEXT.gps, true);
            set(ui.sub, !dr ? TEXT.snapped : t < SPOOF_AT ? TEXT.lost : TEXT.spoof, true);
            const off = Math.max(0, Math.floor(t - LOST_AT));
            set(ui.right, dr ? `${TEXT.noGps} 00:${String(off).padStart(2, '0')}` : TEXT.acc);
            const modeIcon = dr ? 'fa-solid fa-diamond' : 'fa-solid fa-location-arrow';
            if (ui.modeIcon.className !== modeIcon) ui.modeIcon.className = modeIcon;

            const next = turns.find(x => x.s > s);
            if (next) {
                const i = turns.indexOf(next);
                set(ui.dist, meters((next.s - s) * METERS));
                set(ui.manText, `${next.dir > 0 ? TEXT.right : TEXT.left} ${TEXT.streets[i % TEXT.streets.length]}`);
                prop(ui.manIcon, 'rotate', `${next.dir * 45}deg`);
            } else {
                set(ui.dist, meters((total - s) * METERS));
                set(ui.manText, TEXT.straight);
                prop(ui.manIcon, 'rotate', '0deg');
            }

            const speed = t >= BOOST_AT ? 50 : 45;
            const remaining = (total - s) * METERS;
            const minutes = Math.max(1, Math.round(remaining / 1000 / speed * 60));
            set(ui.arr, hhmm(new Date(Date.now() + minutes * 60000)));
            set(ui.rem, `${minutes} ${TEXT.min} · ${num(remaining / 1000, 1)} ${TEXT.km}`);
            set(ui.speedNum, String(speed));

            pins.forEach(pin => {
                // Only between the mode card and the panel, so labels never slide under them.
                const ahead = pin.s - s;
                const screenY = PUCK.y + pin.y - p.y;
                const show = ahead > -30 && screenY > 215 && screenY < 470;
                if (show !== pin.shown) { pin.node.classList.toggle('hide', !show); pin.shown = show; }
                if (show) set(pin.dist, ahead > 8 ? `${TEXT.in} ${meters(ahead * METERS)}` : TEXT.here);
            });

            if (dr && lastGps.classList.contains('hide')) { const g = at(sAt(LOST_AT)); place(lastGps, g.x, g.y); }
            cls(lastGps, 'hide', !dr);
            const ghostOn = t >= SPOOF_AT && t < SHEET[1];
            if (ghostOn && ghost.classList.contains('hide')) { const g = at(sAt(SPOOF_AT)); place(ghost, g.x + 130, g.y - 70); }
            cls(ghost, 'hide', !ghostOn);
            cls(ui.sheet, 'show', t >= SHEET[0] && t < SHEET[1]);

            const step = t < LOST_AT ? 0 : t < SPOOF_AT ? 1 : t < BACK_AT ? 2 : 3;
            ui.caption.forEach((c, i) => cls(c, 'on', i === step));
            cls(ui.replay, 'on', t > LOOP - 0.5);
            set(ui.clock, hhmm(new Date()));
        }

        // One-shot moments: the +5 tap and the "keep estimate" tap.
        function moments(t) {
            if (t >= BOOST_AT && !fired.boost) {
                fired.boost = true;
                tap(ui.plus);
                ui.speed.classList.remove('bump'); void ui.speed.offsetWidth; ui.speed.classList.add('bump');
            }
            if (t >= KEEP_AT && !fired.keep) { fired.keep = true; tap(ui.keep); }
        }

        if (reduce) { render(9); new ResizeObserver(() => { k = nd.clientWidth / 330; move(9); }).observe(nd); return; }

        // Runs only on screen, in a visible tab, after the phone's entrance animation,
        // and (with a mouse) not while the pointer rests on it.
        let t = 0, last = 0, raf = 0, onScreen = false, hovered = false, ready = false, shown = -1;
        const frame = now => {
            const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
            last = now;
            t += dt;
            if (t >= LOOP) { t = 0; fired = {}; shown = -1; }
            if (t - shown >= 0.25) { shown = t; render(t); } else move(t);
            moments(t);
            raf = requestAnimationFrame(frame);
        };
        const sync = () => {
            const run = ready && onScreen && !hovered && !document.hidden;
            if (run && !raf) { last = 0; raf = requestAnimationFrame(frame); }
            if (!run && raf) { cancelAnimationFrame(raf); raf = 0; }
        };
        render(0);
        new ResizeObserver(() => { k = nd.clientWidth / 330; move(t); }).observe(nd);
        const start = () => { if (!ready) { ready = true; sync(); } };
        nd.addEventListener('animationend', e => { if (e.target === nd) start(); });
        setTimeout(start, 1800);
        new IntersectionObserver(([e]) => { onScreen = e.isIntersecting; sync(); }).observe(nd);
        document.addEventListener('visibilitychange', sync);
        if (finePointer) {
            nd.addEventListener('pointerenter', () => { hovered = true; sync(); });
            nd.addEventListener('pointerleave', () => { hovered = false; sync(); });
        }
    }

    // ---------- Hero headline ----------
    // Words inside <span class="accent"> keep the route gradient.
    function splitHeadline() {
        const h1 = $('.hero-title');
        if (!h1) return;
        const words = [];
        h1.childNodes.forEach(node => {
            const accent = node.nodeType === 1 && node.classList.contains('accent');
            node.textContent.trim().split(/\s+/).filter(Boolean).forEach(w => words.push({ w, accent }));
        });
        h1.setAttribute('aria-label', words.map(x => x.w).join(' '));
        h1.textContent = '';
        words.forEach(({ w, accent }, i) => {
            const span = document.createElement('span');
            span.className = accent ? 'hw accent' : 'hw';
            span.setAttribute('aria-hidden', 'true');
            span.style.setProperty('--w', i);
            span.textContent = w;
            if (i) h1.append(' ');
            h1.append(span);
        });
        h1.classList.remove('anim-fade');
        h1.classList.add('split');
    }

    // ---------- Hero ambience: glow drift and dot-grid flashlight ----------
    function initHeroAmbience() {
        if (!hero) return;
        const glow = $('.hero-glow', hero);
        const grid = document.createElement('div');
        grid.className = 'hero-grid';
        grid.setAttribute('aria-hidden', 'true');
        hero.prepend(grid);
        if (!finePointer) return;
        let raf = 0;
        hero.addEventListener('pointermove', e => {
            cancelAnimationFrame(raf);
            raf = requestAnimationFrame(() => {
                const hr = hero.getBoundingClientRect();
                const gr = grid.getBoundingClientRect();
                const px = (e.clientX - hr.left) / hr.width - 0.5;
                const py = (e.clientY - hr.top) / hr.height - 0.5;
                if (glow) glow.style.translate = `${px * 80}px ${py * 50}px`;
                grid.style.setProperty('--gx', `${e.clientX - gr.left}px`);
                grid.style.setProperty('--gy', `${e.clientY - gr.top}px`);
                grid.classList.add('lit');
            });
        });
        hero.addEventListener('pointerleave', () => {
            cancelAnimationFrame(raf);
            if (glow) glow.style.translate = '';
            grid.classList.remove('lit');
        });
    }

    // ---------- Hero buttons ----------
    function initButtons() {
        if (!hero) return;
        const primary = $('a.bg-primary', hero);
        if (primary) primary.classList.add('btn-shine');
        if (!finePointer) return;
        [primary, $('.btn-secondary', hero)].filter(Boolean).forEach(btn => {
            btn.classList.add('magnetic');
            btn.addEventListener('pointermove', e => {
                const r = btn.getBoundingClientRect();
                const dx = e.clientX - (r.left + r.width / 2);
                const dy = e.clientY - (r.top + r.height / 2);
                btn.style.translate = `${dx * 0.18}px ${dy * 0.3}px`;
            });
            btn.addEventListener('pointerleave', () => { btn.style.translate = ''; });
        });
    }

    // ---------- Page scroll progress ----------
    function initProgress() {
        const bar = document.createElement('div');
        bar.className = 'page-progress';
        bar.setAttribute('aria-hidden', 'true');
        document.body.append(bar);
        let raf = 0;
        const update = () => {
            raf = 0;
            const max = root.scrollHeight - innerHeight;
            bar.style.transform = `scaleX(${max > 0 ? Math.min(1, scrollY / max) : 0})`;
        };
        addEventListener('scroll', () => { if (!raf) raf = requestAnimationFrame(update); }, { passive: true });
        addEventListener('resize', update);
        update();
    }

    // ---------- How it works ----------
    function initFlow() {
        $$('.flow .flow-step').forEach((step, i) => step.style.setProperty('--i', i));
    }

    // ---------- Screenshots: stagger, drag with momentum, wheel scrolls sideways ----------
    function initShots() {
        const strip = $('.shots');
        if (!strip) return;
        $$('.shot', strip).forEach((shot, i) => shot.style.setProperty('--i', Math.min(i, 6)));

        let target = strip.scrollLeft, wheelRaf = 0;
        const animate = () => {
            const diff = target - strip.scrollLeft;
            if (Math.abs(diff) < 0.5) { strip.scrollLeft = target; wheelRaf = 0; return; }
            strip.scrollLeft += diff * 0.2;
            wheelRaf = requestAnimationFrame(animate);
        };
        // Only while the strip can still move that way, so the section never traps the page scroll.
        strip.addEventListener('wheel', e => {
            if (e.ctrlKey || Math.abs(e.deltaX) >= Math.abs(e.deltaY)) return;
            const max = strip.scrollWidth - strip.clientWidth;
            if (!wheelRaf) target = strip.scrollLeft;
            const delta = e.deltaY * (e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? strip.clientWidth : 1);
            if ((delta < 0 && target <= 0) || (delta > 0 && target >= max - 1)) return;
            e.preventDefault();
            target = Math.max(0, Math.min(max, target + delta));
            if (!wheelRaf) wheelRaf = requestAnimationFrame(animate);
        }, { passive: false });

        if (!finePointer) return;
        let down = false, moved = false, startX = 0, startLeft = 0, lastX = 0, lastT = 0, velocity = 0, glide = 0;
        strip.addEventListener('pointerdown', e => {
            if (e.pointerType !== 'mouse' || e.button !== 0) return;
            e.preventDefault();
            down = true; moved = false; velocity = 0;
            startX = lastX = e.clientX; startLeft = strip.scrollLeft; lastT = performance.now();
            cancelAnimationFrame(glide); cancelAnimationFrame(wheelRaf); wheelRaf = 0;
        });
        addEventListener('pointermove', e => {
            if (!down) return;
            const dx = e.clientX - startX;
            if (!moved && Math.abs(dx) > 4) { moved = true; strip.classList.add('dragging'); }
            if (!moved) return;
            strip.scrollLeft = startLeft - dx;
            const now = performance.now();
            velocity = 0.75 * velocity + 0.25 * ((lastX - e.clientX) / Math.max(1, now - lastT));
            lastX = e.clientX; lastT = now;
        });
        addEventListener('pointerup', () => {
            if (!down) return;
            down = false;
            strip.classList.remove('dragging');
            if (!moved || performance.now() - lastT > 80) return;
            let v = velocity * 16;
            const tick = () => {
                v *= 0.94;
                if (Math.abs(v) < 0.4) return;
                strip.scrollLeft += v;
                glide = requestAnimationFrame(tick);
            };
            glide = requestAnimationFrame(tick);
        });
        strip.addEventListener('click', e => { if (moved) { e.preventDefault(); e.stopPropagation(); } }, true);
    }

    // ---------- Screenshot tilt ----------
    function initTilt() {
        if (!finePointer) return;
        $$('.screenshot-card').forEach(card => {
            // Measure the untransformed wrapper so the tilt doesn't feed back into itself.
            const box = card.parentElement;
            let raf = 0;
            card.addEventListener('pointerenter', () => card.classList.add('tilting'));
            card.addEventListener('pointermove', e => {
                cancelAnimationFrame(raf);
                raf = requestAnimationFrame(() => {
                    const r = box.getBoundingClientRect();
                    const px = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
                    const py = Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
                    card.style.transform =
                        `perspective(900px) translateY(-6px) rotateX(${(0.5 - py) * 9}deg) rotateY(${(px - 0.5) * 11}deg)`;
                    card.style.setProperty('--sx', `${px * 100}%`);
                    card.style.setProperty('--sy', `${py * 100}%`);
                });
            });
            card.addEventListener('pointerleave', () => {
                cancelAnimationFrame(raf);
                card.classList.remove('tilting');
                card.style.transform = '';
            });
        });
    }

    // ---------- Feature cards: one spotlight across the whole grid ----------
    function initSpotlight() {
        $$('.feat-grid').forEach(grid => {
            const cards = $$('.feat-card', grid);
            cards.forEach((card, i) => card.style.setProperty('--i', i % 3));
            if (!finePointer) return;
            let raf = 0;
            grid.addEventListener('pointermove', e => {
                cancelAnimationFrame(raf);
                raf = requestAnimationFrame(() => {
                    cards.forEach(card => {
                        const r = card.getBoundingClientRect();
                        card.style.setProperty('--mx', `${e.clientX - r.left}px`);
                        card.style.setProperty('--my', `${e.clientY - r.top}px`);
                    });
                    grid.classList.add('spot-on');
                });
            });
            grid.addEventListener('pointerleave', () => { cancelAnimationFrame(raf); grid.classList.remove('spot-on'); });
        });
    }

    // ---------- Install command types itself ----------
    function initTyping() {
        const box = $('.code-box');
        if (!box) return;
        // Untyped text stays in the layout (hidden), so the box never changes size.
        const lines = $$('code', box).map(code => {
            const text = code.textContent;
            const typed = document.createElement('span');
            const ghost = document.createElement('span');
            ghost.className = 'ty-ghost';
            ghost.textContent = text;
            code.textContent = '';
            code.append(typed, ghost);
            return { text, typed, ghost };
        });
        if (!lines.length) return;
        const caret = document.createElement('span');
        caret.className = 'ty-caret';
        caret.setAttribute('aria-hidden', 'true');
        lines[0].typed.after(caret);

        const io = new IntersectionObserver(([e]) => {
            if (!e.isIntersecting) return;
            io.disconnect();
            let line = 0, ch = 0;
            const tick = () => {
                const l = lines[line];
                ch++;
                l.typed.textContent = l.text.slice(0, ch);
                l.ghost.textContent = l.text.slice(ch);
                l.typed.after(caret);
                if (ch < l.text.length) return setTimeout(tick, 16 + Math.random() * 34);
                if (++line < lines.length) { ch = 0; setTimeout(tick, 320); }
            };
            setTimeout(tick, 450);
        }, { threshold: 0.6 });
        io.observe(box);
    }

    function initCopyPop() {
        const original = window.showCopied;
        if (typeof original !== 'function') return;
        window.showCopied = icon => {
            original(icon);
            icon.closest('button')?.animate(
                [{ transform: 'scale(1)' }, { transform: 'scale(0.8)' }, { transform: 'scale(1.2)' }, { transform: 'scale(1)' }],
                { duration: 520, easing: 'ease-out' });
        };
    }

    // ---------- Screenshot modal: fly from the card and back ----------
    function initModalFlip() {
        const modal = $('#imageModal');
        const big = $('#modalImage');
        if (!modal || !big || !big.animate) return;
        let source = null, closing = false;
        const flyFrom = (from, to) => {
            const s = from.width / to.width;
            const dx = from.left + from.width / 2 - (to.left + to.width / 2);
            const dy = from.top + from.height / 2 - (to.top + to.height / 2);
            return `translate(${dx}px, ${dy}px) scale(${s})`;
        };

        window.openModal = (img, caption) => {
            if (closing) return;
            source = img;
            big.src = img.src;
            big.alt = img.alt;
            $('#modalCaption').textContent = caption;
            big.style.opacity = '0';
            modal.classList.add('flip');
            modal.style.display = 'flex';
            document.body.style.overflow = 'hidden';
            big.decode().catch(() => {}).then(() => {
                const to = big.getBoundingClientRect();
                const from = img.getBoundingClientRect();
                big.style.opacity = '';
                modal.classList.add('show');
                if (!to.width) return;
                img.style.visibility = 'hidden';
                big.animate([{ transform: flyFrom(from, to) }, { transform: 'none' }], { duration: 560, easing: EASE_OUT })
                    .finished.finally(() => { img.style.visibility = ''; });
            });
        };

        window.closeModal = () => {
            if (!modal.classList.contains('show') || closing) return;
            closing = true;
            const to = big.getBoundingClientRect();
            const from = source ? source.getBoundingClientRect() : null;
            modal.classList.remove('show');
            const done = () => {
                modal.style.display = 'none';
                modal.classList.remove('flip');
                document.body.style.overflow = 'auto';
                if (source) source.style.visibility = '';
                closing = false;
            };
            if (!from || !from.width || !to.width) { setTimeout(done, 300); return; }
            if (source) source.style.visibility = 'hidden';
            const anim = big.animate([{ transform: 'none' }, { transform: flyFrom(from, to) }],
                { duration: 440, easing: 'cubic-bezier(0.4, 0, 0.2, 1)', fill: 'forwards' });
            anim.finished.finally(() => { done(); anim.cancel(); });
        };
    }

    // ---------- Theme switch: circular reveal from the toggle ----------
    function initThemeReveal() {
        const original = window.toggleTheme;
        if (typeof original !== 'function' || !document.startViewTransition) return;
        window.toggleTheme = () => {
            const btn = $('#theme-toggle');
            const r = btn.getBoundingClientRect();
            const x = r.left + r.width / 2, y = r.top + r.height / 2;
            const radius = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
            const transition = document.startViewTransition(original);
            transition.ready.then(() => {
                root.animate(
                    { clipPath: [`circle(0px at ${x}px ${y}px)`, `circle(${radius}px at ${x}px ${y}px)`] },
                    { duration: 650, easing: 'cubic-bezier(0.65, 0, 0.35, 1)', pseudoElement: '::view-transition-new(root)' });
            }).catch(() => {});
        };
    }

    initNavDemo();
    if (reduce) return;
    root.classList.add('motion');
    splitHeadline();
    initHeroAmbience();
    initButtons();
    initProgress();
    initFlow();
    initShots();
    initTilt();
    initSpotlight();
    initTyping();
    initCopyPop();
    initModalFlip();
    initThemeReveal();
})();
