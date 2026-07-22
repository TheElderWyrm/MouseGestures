/* MouseGestures site script — no dependencies.
   Theme toggle · mobile nav · hero demo engine · action marquee ·
   GitHub release auto-check · the ⌥ + top-right-corner easter egg. */
(function () {
    'use strict';

    var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    /* ---------------- theme ---------------- */
    function setTheme(theme, persist) {
        document.documentElement.setAttribute('data-theme', theme);
        if (persist) {
            try { localStorage.setItem('mg-theme', theme); } catch (e) { /* ignore */ }
        }
    }
    function toggleTheme() {
        var next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        setTheme(next, true);
        return next;
    }
    document.querySelectorAll('.theme-toggle').forEach(function (btn) {
        btn.addEventListener('click', function () { toggleTheme(); });
    });
    // follow the OS while the visitor hasn't chosen manually
    window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', function (e) {
        var stored = null;
        try { stored = localStorage.getItem('mg-theme'); } catch (err) { /* ignore */ }
        if (!stored) setTheme(e.matches ? 'light' : 'dark', false);
    });

    /* ---------------- mobile nav ---------------- */
    var menuBtn = document.querySelector('.menu-btn');
    var navMenu = document.getElementById('nav-menu');
    if (menuBtn && navMenu) {
        function closeMenu() {
            navMenu.classList.remove('open');
            menuBtn.setAttribute('aria-expanded', 'false');
        }
        menuBtn.addEventListener('click', function () {
            var open = navMenu.classList.toggle('open');
            menuBtn.setAttribute('aria-expanded', String(open));
        });
        navMenu.addEventListener('click', function (e) {
            if (e.target.closest('a')) closeMenu();
        });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') closeMenu();
        });
        document.addEventListener('click', function (e) {
            if (!e.target.closest('nav') && navMenu.classList.contains('open')) closeMenu();
        });
    }

    /* ---------------- action-catalog marquee ---------------- */
    if (!reducedMotion) {
        document.querySelectorAll('[data-marquee]').forEach(function (marquee) {
            marquee.querySelectorAll('.marquee-track').forEach(function (track) {
                var chips = track.querySelector('.chips');
                if (!chips) return;
                var clone = chips.cloneNode(true);
                clone.setAttribute('aria-hidden', 'true');
                track.appendChild(clone);
            });
            marquee.classList.add('js');
        });
    }

    /* ---------------- hero demo engine ---------------- */
    var demo = document.getElementById('demo');
    if (demo) {
        var stage = demo.querySelector('.stage');
        var capTrigger = demo.querySelector('.cap-trigger');
        var capArrow = demo.querySelector('.cap-arrow');
        var capAction = demo.querySelector('.cap-action');

        var scenes = [
            { id: 'snap',   zone: 'right',       trigger: '⌘ + Right Edge',          action: 'Snap Window Right' },
            { id: 'tile',   zone: 'top',         trigger: '⌃ + Top Edge',            action: 'Tile All Windows' },
            { id: 'volume', zone: 'bottom-left', trigger: '⇧ + Bottom-Left Corner',  action: 'Raise Volume' },
            { id: 'dark',   zone: 'top-right',   trigger: '⌥ + Top-Right Corner',    action: 'Toggle Dark Mode' }
        ];
        var current = 0;
        var SCENE_MS = 4200;
        var visible = true;

        function setScene(index) {
            current = index;
            var s = scenes[index];
            stage.setAttribute('data-scene', s.id);
            capTrigger.textContent = s.trigger;
            capArrow.textContent = '→';
            capAction.textContent = s.action;
        }

        if (reducedMotion) {
            demo.setAttribute('data-static', '');
            setScene(0);
        } else {
            setScene(0);
            var timer = setInterval(function () {
                if (document.hidden || !visible) return;
                setScene((current + 1) % scenes.length);
            }, SCENE_MS);

            if ('IntersectionObserver' in window) {
                new IntersectionObserver(function (entries) {
                    visible = entries[0].isIntersecting;
                }, { threshold: 0.15 }).observe(demo);
            }

            var restart = function () {
                clearInterval(timer);
                timer = setInterval(function () {
                    if (document.hidden || !visible) return;
                    setScene((current + 1) % scenes.length);
                }, SCENE_MS);
            };

            var driveTo = function (zoneName) {
                for (var i = 0; i < scenes.length; i++) {
                    if (scenes[i].zone === zoneName) {
                        if (i !== current) setScene(i);
                        restart();
                        return;
                    }
                }
                // an unmapped zone: remind that everything is configurable
                capTrigger.textContent = 'Any zone + any modifiers';
                capAction.textContent = 'Anything you like';
                restart();
            };

            demo.querySelectorAll('.zone').forEach(function (zone) {
                zone.addEventListener('click', function () { driveTo(zone.dataset.zone); });
                zone.addEventListener('pointerenter', function (e) {
                    if (e.pointerType === 'mouse') driveTo(zone.dataset.zone);
                });
            });
        }
    }

    /* ---------------- GitHub release auto-check ----------------
       The static card already links to releases/latest; this refines it with
       the exact version, a direct DMG link, size, and release date — so the
       page stays current on every future release without a redeploy. */
    (function checkRelease() {
        var btn = document.getElementById('dl-btn');
        var meta = document.getElementById('dl-meta');
        if (!btn || !meta || !window.fetch) return;

        fetch('https://api.github.com/repos/TheElderWyrm/MouseGestures/releases/latest', {
            headers: { Accept: 'application/vnd.github+json' }
        }).then(function (r) {
            if (!r.ok) throw new Error('release lookup failed');
            return r.json();
        }).then(function (rel) {
            if (!rel || rel.draft || rel.prerelease) return;
            var dmg = (rel.assets || []).filter(function (a) {
                return /\.dmg$/i.test(a.name || '');
            })[0];
            if (dmg) btn.href = dmg.browser_download_url;
            btn.textContent = 'Download MouseGestures ' + (rel.tag_name || '') + ' (.dmg)';
            var bits = [];
            if (dmg && dmg.size) bits.push((dmg.size / 1048576).toFixed(1) + ' MB');
            bits.push('signed & notarized');
            if (rel.published_at) {
                bits.push('released ' + new Date(rel.published_at).toLocaleDateString(undefined,
                    { year: 'numeric', month: 'short', day: 'numeric' }));
            }
            meta.textContent = bits.join(' · ');
        }).catch(function () { /* static card already links to releases/latest */ });
    })();

    /* ---------------- toast ---------------- */
    var toastEl = document.getElementById('toast');
    var toastTimer = null;
    function toast(message) {
        if (!toastEl) return;
        toastEl.textContent = message;
        toastEl.hidden = false;
        // force a frame so the transition plays
        void toastEl.offsetWidth;
        toastEl.classList.add('show');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () {
            toastEl.classList.remove('show');
        }, 3600);
    }

    /* ---------------- easter egg: ⌥ + top-right corner = toggle theme ------
       The page itself behaves like MouseGestures: hold option and glide into
       the top-right corner of the viewport to fire a real "gesture". */
    if (window.matchMedia('(pointer: fine)').matches) {
        var hint = document.getElementById('egg-hint');
        var hintOff = false;
        try { hintOff = localStorage.getItem('mg-hint-off') === '1'; } catch (e) { /* ignore */ }
        if (hint && !hintOff) hint.hidden = false;

        function dropHint() {
            if (hint) hint.hidden = true;
            try { localStorage.setItem('mg-hint-off', '1'); } catch (e) { /* ignore */ }
        }
        var dismiss = document.getElementById('egg-dismiss');
        if (dismiss) dismiss.addEventListener('click', dropHint);

        var armed = true;
        var CORNER = 34; // px from the top-right corner
        window.addEventListener('mousemove', function (e) {
            var inCorner = e.clientX >= window.innerWidth - CORNER && e.clientY <= CORNER;
            if (inCorner && e.altKey && armed) {
                armed = false;
                var next = toggleTheme();
                toast('⌥ + Top-Right Corner → ' + (next === 'dark' ? 'Dark' : 'Light') +
                      ' Mode — that’s MouseGestures.');
                dropHint();
            } else if (!inCorner) {
                armed = true;
            }
        }, { passive: true });
    }
})();
