/* MouseGestures site — vanilla JS, no dependencies.
   Theme toggle · mobile nav · action marquee · scroll reveals ·
   GitHub release auto-check · the hero desktop playground ·
   the ⌥ + top-right-corner easter egg. */
(function () {
  "use strict";

  var reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  var docEl = document.documentElement;

  /* ---------- Theme ---------- */

  function setTheme(theme, persist) {
    docEl.setAttribute("data-theme", theme);
    if (persist) {
      try { localStorage.setItem("mg-theme", theme); } catch (e) { /* private mode */ }
    }
  }

  function toggleTheme(persist) {
    var next = docEl.getAttribute("data-theme") === "dark" ? "light" : "dark";
    setTheme(next, persist);
    return next;
  }

  document.getElementById("themeToggle").addEventListener("click", function () {
    toggleTheme(true);
  });

  // follow the OS while the visitor hasn't chosen manually
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
    var stored = null;
    try { stored = localStorage.getItem("mg-theme"); } catch (err) { /* ignore */ }
    if (!stored) setTheme(e.matches ? "dark" : "light", false);
  });

  /* ---------- Mobile nav ---------- */

  var menuBtn = document.querySelector(".menu-btn");
  var navMenu = document.getElementById("navMenu");
  if (menuBtn && navMenu) {
    var closeMenu = function () {
      navMenu.classList.remove("open");
      menuBtn.setAttribute("aria-expanded", "false");
    };
    menuBtn.addEventListener("click", function () {
      var open = navMenu.classList.toggle("open");
      menuBtn.setAttribute("aria-expanded", String(open));
    });
    navMenu.addEventListener("click", function (e) {
      if (e.target.closest("a")) closeMenu();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") closeMenu();
    });
    document.addEventListener("click", function (e) {
      if (!e.target.closest(".nav") && navMenu.classList.contains("open")) closeMenu();
    });
  }

  /* ---------- Clocks & year ---------- */

  (function () {
    var now = new Date();
    var h = now.getHours() % 12 || 12;
    var m = String(now.getMinutes()).padStart(2, "0");
    var t = h + ":" + m;
    var mbar = document.getElementById("mbarClock");
    var lock = document.getElementById("lockClock");
    if (mbar) mbar.textContent = t;
    if (lock) lock.textContent = t;
    var year = document.getElementById("year");
    if (year) year.textContent = String(now.getFullYear());
  })();

  /* ---------- Action-catalog marquee ---------- */

  if (!reducedMotion) {
    Array.prototype.forEach.call(document.querySelectorAll("[data-marquee]"), function (marquee) {
      Array.prototype.forEach.call(marquee.querySelectorAll(".marquee-track"), function (track) {
        var chips = track.querySelector(".chips");
        if (!chips) return;
        var clone = chips.cloneNode(true);
        clone.setAttribute("aria-hidden", "true");
        track.appendChild(clone);
      });
      marquee.classList.add("js");
    });
  }

  /* ---------- Scroll reveals ---------- */

  (function () {
    var items = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
    if (reducedMotion || !("IntersectionObserver" in window)) {
      items.forEach(function (el) { el.classList.add("in"); });
      return;
    }
    // Anything already in (or near) the first viewport shows immediately;
    // only genuinely below-the-fold content waits for the observer.
    var vh = window.innerHeight || docEl.clientHeight;
    var pending = items.filter(function (el) {
      if (el.getBoundingClientRect().top < vh * 0.96) {
        el.classList.add("in", "no-anim"); // visible immediately, no load-fade
        return false;
      }
      return true;
    });
    if (!pending.length) return;
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.18, rootMargin: "0px 0px -8% 0px" });
    pending.forEach(function (el) { io.observe(el); });
  })();

  /* ---------- GitHub release auto-check ----------
     The static button already links to releases/latest/download; this refines
     the page with the exact version, size, and release date — so it stays
     current on every future release without a redeploy. */
  (function checkRelease() {
    var btn = document.getElementById("dl-btn");
    var meta = document.getElementById("dl-meta");
    if (!btn || !meta || !window.fetch) return;

    fetch("https://api.github.com/repos/TheElderWyrm/MouseGestures/releases/latest", {
      headers: { Accept: "application/vnd.github+json" }
    }).then(function (r) {
      if (!r.ok) throw new Error("release lookup failed");
      return r.json();
    }).then(function (rel) {
      if (!rel || rel.draft || rel.prerelease) return;
      var dmg = (rel.assets || []).filter(function (a) {
        return /\.dmg$/i.test(a.name || "");
      })[0];
      if (dmg) btn.lastChild.textContent = " Download MouseGestures " + (rel.tag_name || "");
      var bits = [];
      if (rel.tag_name) bits.push("Version " + rel.tag_name.replace(/^v/, ""));
      if (dmg && dmg.size) bits.push((dmg.size / 1048576).toFixed(1) + " MB");
      bits.push("macOS 13+ · Apple silicon");
      bits.push("signed & notarized");
      if (rel.published_at) {
        bits.push("released " + new Date(rel.published_at).toLocaleDateString(undefined,
          { year: "numeric", month: "short", day: "numeric" }));
      }
      meta.textContent = bits.join(" · ");
    }).catch(function () { /* static button already links to releases/latest */ });
  })();

  /* ---------- Toast ---------- */

  var toastEl = document.getElementById("toast");
  var toastTimer = null;
  function toast(message) {
    if (!toastEl) return;
    toastEl.textContent = message;
    toastEl.hidden = false;
    // force a frame so the transition plays
    void toastEl.offsetWidth;
    toastEl.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      toastEl.classList.remove("show");
    }, 3600);
  }

  /* ---------- Easter egg: ⌥ + top-right corner = toggle theme ----------
     The page itself behaves like MouseGestures: hold option and glide into
     the top-right corner of the viewport to fire a real "gesture". */
  if (matchMedia("(pointer: fine)").matches) {
    var hint = document.getElementById("egg-hint");
    var hintOff = false;
    try { hintOff = localStorage.getItem("mg-hint-off") === "1"; } catch (e) { /* ignore */ }
    if (hint && !hintOff) hint.hidden = false;

    var dropHint = function () {
      if (hint) hint.hidden = true;
      try { localStorage.setItem("mg-hint-off", "1"); } catch (e) { /* ignore */ }
    };
    var dismiss = document.getElementById("egg-dismiss");
    if (dismiss) dismiss.addEventListener("click", dropHint);

    var armed = true;
    var CORNER = 34; // px from the top-right corner
    window.addEventListener("mousemove", function (e) {
      var inCorner = e.clientX >= window.innerWidth - CORNER && e.clientY <= CORNER;
      if (inCorner && e.altKey && armed) {
        armed = false;
        var next = toggleTheme(true);
        toast("⌥ + Top-Right Corner → " + (next === "dark" ? "Dark" : "Light") +
              " Mode — that’s MouseGestures.");
        dropHint();
      } else if (!inCorner) {
        armed = true;
      }
    }, { passive: true });
  }

  /* ==========================================================
     The playground: a miniature desktop wired like the real app
     (8 zones × modifier × action).
     ========================================================== */

  var demo = document.getElementById("demo");
  if (demo) {
    var desktop = document.getElementById("desktop");
    var hud = document.getElementById("hud");
    var volHud = document.getElementById("volHud");
    var volBar = document.getElementById("volBar");
    var mediaHud = document.getElementById("mediaHud");
    var shotFlash = document.getElementById("shotFlash");
    var shotThumb = document.getElementById("shotThumb");
    var lockscreen = document.getElementById("lockscreen");
    var caption = document.getElementById("demoCaption");

    var shiftHeld = false;
    var volume = 50;
    var hudTimer, volTimer, mediaTimer, transientTimer;
    var lastFire = {}; // per-zone cooldown

    if (matchMedia("(hover: none)").matches && caption) {
      caption.innerHTML = "<strong>Try it:</strong> tap a corner or an edge of the little desktop. " +
        "In the real app, your whole screen is the canvas.";
    }

    document.addEventListener("keydown", function (e) { if (e.key === "Shift") shiftHeld = true; });
    document.addEventListener("keyup", function (e) { if (e.key === "Shift") shiftHeld = false; });
    window.addEventListener("blur", function () { shiftHeld = false; });

    var showHud = function (zoneGlyph, actionName, withShift) {
      hud.innerHTML = "<b>" + (withShift ? "⇧ " : "") + zoneGlyph + "</b> " + actionName;
      hud.classList.add("show");
      clearTimeout(hudTimer);
      hudTimer = setTimeout(function () { hud.classList.remove("show"); }, 1400);
    };

    /* Transient desktop states (mission control / exposé / show desktop)
       are mutually exclusive and self-clearing. */
    var transientState = function (cls, holdMs) {
      desktop.classList.remove("is-mission", "is-expose", "is-showdesk");
      // force reflow so re-triggering the same state animates again
      void desktop.offsetWidth;
      desktop.classList.add(cls);
      clearTimeout(transientTimer);
      transientTimer = setTimeout(function () { desktop.classList.remove(cls); }, holdMs);
    };

    var showVolume = function (delta) {
      volume = Math.max(0, Math.min(100, volume + delta));
      volBar.style.setProperty("--vol", volume + "%");
      volHud.classList.add("show");
      mediaHud.classList.remove("show");
      clearTimeout(volTimer);
      volTimer = setTimeout(function () { volHud.classList.remove("show"); }, 1000);
    };

    var showMedia = function () {
      mediaHud.classList.toggle("playing");
      mediaHud.classList.add("show");
      volHud.classList.remove("show");
      clearTimeout(mediaTimer);
      mediaTimer = setTimeout(function () { mediaHud.classList.remove("show"); }, 1000);
    };

    var screenshot = function () {
      shotFlash.classList.remove("go");
      shotThumb.classList.remove("go");
      void shotFlash.offsetWidth;
      shotFlash.classList.add("go");
      shotThumb.classList.add("go");
    };

    var snap = function (side) {
      desktop.dataset.snap = desktop.dataset.snap === side ? "none" : side;
    };

    /* zone id -> { glyph, base action, shift action } */
    var zones = {
      tl:     { g: "↖", base: ["Mission Control", function () { transientState("is-mission", 1500); }],
                              shift: ["App Exposé", function () { transientState("is-expose", 1500); }] },
      tr:     { g: "↗", base: ["Toggle Dark Mode", function () { toggleTheme(true); }],
                              shift: ["Screenshot", screenshot] },
      bl:     { g: "↙", base: ["Show Desktop", function () { transientState("is-showdesk", 1500); }] },
      br:     { g: "↘", base: ["Lock Screen", function () { desktop.classList.add("is-locked"); }] },
      top:    { g: "↑", base: ["Volume Up", function () { showVolume(12.5); }],
                              shift: ["Volume Down", function () { showVolume(-12.5); }] },
      bottom: { g: "↓", base: ["Play / Pause", showMedia] },
      left:   { g: "←", base: ["Snap Window Left", function () { snap("left"); }] },
      right:  { g: "→", base: ["Snap Window Right", function () { snap("right"); }] }
    };

    var fire = function (zoneEl) {
      var id = zoneEl.dataset.zone;
      var zone = zones[id];
      if (!zone) return;

      var now = performance.now();
      if (lastFire[id] && now - lastFire[id] < 650) return;
      lastFire[id] = now;

      desktop.classList.add("touched");
      if (desktop.classList.contains("is-locked")) desktop.classList.remove("is-locked");

      var entry = (shiftHeld && zone.shift) ? zone.shift : zone.base;
      showHud(zone.g, entry[0], shiftHeld && !!zone.shift);
      entry[1]();

      zoneEl.classList.remove("zap");
      void zoneEl.offsetWidth;
      zoneEl.classList.add("zap");
    };

    Array.prototype.forEach.call(demo.querySelectorAll(".zone"), function (zoneEl) {
      zoneEl.addEventListener("pointerenter", function (e) {
        if (e.pointerType === "mouse") fire(zoneEl);
      });
      zoneEl.addEventListener("click", function () { fire(zoneEl); });
    });

    lockscreen.addEventListener("click", function () {
      desktop.classList.remove("is-locked");
    });

    /* ---------- Cursor comet trail ---------- */

    (function () {
      if (reducedMotion) return;

      var canvas = document.getElementById("trail");
      var ctx = canvas.getContext("2d");
      var dpr = Math.min(window.devicePixelRatio || 1, 2);
      var points = [];
      var running = false;
      var LIFE = 420; // ms a point stays visible

      function resize() {
        var rect = desktop.getBoundingClientRect();
        canvas.width = Math.round(rect.width * dpr);
        canvas.height = Math.round(rect.height * dpr);
      }

      if ("ResizeObserver" in window) {
        new ResizeObserver(resize).observe(desktop);
      } else {
        window.addEventListener("resize", resize);
      }
      resize();

      desktop.addEventListener("pointermove", function (e) {
        if (e.pointerType !== "mouse") return;
        var rect = desktop.getBoundingClientRect();
        points.push({ x: e.clientX - rect.left, y: e.clientY - rect.top, t: performance.now() });
        if (points.length > 90) points.shift();
        if (!running) { running = true; requestAnimationFrame(draw); }
      });

      function trailColors() {
        return docEl.getAttribute("data-theme") === "dark"
          ? ["133, 131, 255", "56, 200, 255"]
          : ["94, 92, 230", "0, 168, 232"];
      }

      function draw() {
        var now = performance.now();
        while (points.length && now - points[0].t > LIFE) points.shift();

        ctx.clearRect(0, 0, canvas.width, canvas.height);

        if (points.length > 1) {
          var colors = trailColors();
          ctx.lineCap = "round";
          ctx.lineJoin = "round";
          for (var i = 1; i < points.length; i++) {
            var a = points[i - 1], b = points[i];
            var age = 1 - (now - b.t) / LIFE;           // 1 = fresh, 0 = dying
            if (age <= 0) continue;
            var mix = i / points.length;                 // head fades toward accent-2
            var rgb = mix > 0.5 ? colors[1] : colors[0];
            // soft glow pass
            ctx.strokeStyle = "rgba(" + rgb + "," + (0.16 * age) + ")";
            ctx.lineWidth = 10 * dpr * age;
            ctx.beginPath();
            ctx.moveTo(a.x * dpr, a.y * dpr);
            ctx.lineTo(b.x * dpr, b.y * dpr);
            ctx.stroke();
            // bright core pass
            ctx.strokeStyle = "rgba(" + rgb + "," + (0.85 * age) + ")";
            ctx.lineWidth = 2.6 * dpr * age + 0.4;
            ctx.beginPath();
            ctx.moveTo(a.x * dpr, a.y * dpr);
            ctx.lineTo(b.x * dpr, b.y * dpr);
            ctx.stroke();
          }
        }

        if (points.length) {
          requestAnimationFrame(draw);
        } else {
          running = false;
          ctx.clearRect(0, 0, canvas.width, canvas.height);
        }
      }
    })();
  }
})();
