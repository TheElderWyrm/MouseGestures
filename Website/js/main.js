/* MouseGestures site — vanilla JS, no dependencies.
   Theme toggle · mobile nav · action-catalog ribbon (auto-scroll, category
   jump, drag) · scroll reveals · GitHub release auto-check · the hero
   desktop playground with switchable profiles · the ⌥ + top-right-corner
   easter egg. */
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

  /* ---------- Action-catalog ribbon ----------
     The two chip tracks auto-scroll like a marquee, but are fully
     interactive: hovering the catalog (tabs or ribbon) freezes them, any
     track can be dragged, and the category tabs glide the owning track so
     that category is in view (dimming everything else). */

  (function catalog() {
    var marquee = document.querySelector("[data-marquee]");
    if (!marquee) return;
    var tabs = Array.prototype.slice.call(document.querySelectorAll(".cat-tab"));
    var tabsWrap = document.querySelector(".cat-tabs");

    function setFilter(fam) {
      if (fam) marquee.setAttribute("data-filter", fam);
      else marquee.removeAttribute("data-filter");
      tabs.forEach(function (t) {
        t.setAttribute("aria-pressed", String(t.dataset.fam === fam));
      });
    }

    if (reducedMotion) {
      // static wrapped grid (no clones, no motion): tabs only highlight a category
      tabs.forEach(function (tab) {
        tab.addEventListener("click", function () {
          var fam = tab.dataset.fam;
          setFilter(marquee.getAttribute("data-filter") === fam ? null : fam);
        });
      });
      return;
    }

    var SPEED = 36; // px/s auto-scroll
    var tracks = [];
    Array.prototype.forEach.call(marquee.querySelectorAll(".marquee-track"), function (track) {
      var chips = track.querySelector(".chips");
      if (!chips) return;
      var clone = chips.cloneNode(true);
      clone.setAttribute("aria-hidden", "true");
      track.appendChild(clone);
      tracks.push({
        el: track,
        chips: chips,
        offset: 0,
        unit: 0,
        dir: track.classList.contains("reverse") ? 1 : -1
      });
    });
    if (!tracks.length) return;
    marquee.classList.add("js");

    var hovering = false, dragging = false, selected = null, inView = true;
    var running = false, lastT = 0, resumeTimer = null;
    var coarse = matchMedia("(hover: none)").matches;

    function wrap(x, unit) {
      return unit ? -((((-x) % unit) + unit) % unit) : x;
    }

    function apply(s) {
      s.el.style.transform = "translate3d(" + s.offset.toFixed(2) + "px,0,0)";
    }

    function measure() {
      tracks.forEach(function (s) {
        s.unit = s.chips.getBoundingClientRect().width;
        s.offset = wrap(s.offset, s.unit);
        apply(s);
      });
    }

    function paused() {
      return hovering || dragging || selected !== null || !inView || document.hidden;
    }

    function tick(t) {
      if (paused()) { running = false; return; }
      // rAF timestamps can land a hair before the performance.now() captured
      // in ensure() — never step backwards
      var dt = Math.min(64, Math.max(0, t - lastT));
      lastT = t;
      tracks.forEach(function (s) {
        if (!s.unit) return;
        s.offset = wrap(s.offset + s.dir * SPEED * dt / 1000, s.unit);
        apply(s);
      });
      requestAnimationFrame(tick);
    }

    function ensure() {
      if (!running && !paused()) {
        running = true;
        lastT = performance.now();
        requestAnimationFrame(tick);
      }
    }

    function clearSelection() {
      selected = null;
      setFilter(null);
      ensure();
    }

    /* freeze while the pointer is over the tabs or the ribbon */
    [tabsWrap, marquee].forEach(function (area) {
      if (!area) return;
      area.addEventListener("pointerenter", function (e) {
        if (e.pointerType !== "mouse") return;
        clearTimeout(resumeTimer);
        hovering = true;
      });
      area.addEventListener("pointerleave", function (e) {
        if (e.pointerType !== "mouse") return;
        hovering = false;
        clearTimeout(resumeTimer);
        // a selected category lingers briefly after you move away, then
        // the ribbon un-dims and resumes
        if (selected !== null) resumeTimer = setTimeout(clearSelection, 2400);
        ensure();
      });
    });

    /* drag to scroll a track by hand */
    tracks.forEach(function (s) {
      s.el.addEventListener("pointerdown", function (e) {
        if (e.pointerType === "mouse" && e.button !== 0) return;
        dragging = true;
        marquee.classList.add("dragging");
        var lastX = e.clientX;
        var move = function (ev) {
          s.offset = wrap(s.offset + (ev.clientX - lastX), s.unit);
          lastX = ev.clientX;
          apply(s);
        };
        var up = function () {
          dragging = false;
          marquee.classList.remove("dragging");
          window.removeEventListener("pointermove", move);
          window.removeEventListener("pointerup", up);
          window.removeEventListener("pointercancel", up);
          ensure();
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
        window.addEventListener("pointercancel", up);
        e.preventDefault();
      });
    });

    /* category tabs: glide the owning track so the category lands in view */
    function trackForFam(fam) {
      for (var i = 0; i < tracks.length; i++) {
        if (tracks[i].chips.querySelector('.chip.fam[data-fam="' + fam + '"]')) return tracks[i];
      }
      return null;
    }

    function glideTo(s, target) {
      var from = s.offset;
      var delta = target - from;
      if (delta > s.unit / 2) delta -= s.unit;
      if (delta < -s.unit / 2) delta += s.unit;
      var t0 = performance.now(), DUR = 620;
      function step(t) {
        var k = Math.min(1, (t - t0) / DUR);
        k = 1 - Math.pow(1 - k, 3);
        s.offset = wrap(from + delta * k, s.unit);
        apply(s);
        if (k < 1 && selected !== null && !dragging) requestAnimationFrame(step);
      }
      requestAnimationFrame(step);
    }

    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        var fam = tab.dataset.fam;
        clearTimeout(resumeTimer);
        if (selected === fam) { clearSelection(); return; }
        selected = fam;
        setFilter(fam);
        var s = trackForFam(fam);
        var chip = s && s.chips.querySelector('.chip.fam[data-fam="' + fam + '"]');
        if (s && chip) {
          var pos = chip.getBoundingClientRect().left - s.chips.getBoundingClientRect().left;
          var inset = Math.min(48, marquee.clientWidth * 0.05);
          glideTo(s, wrap(inset - pos, s.unit));
        }
        // no hover to release the freeze on touch devices — time out instead
        if (coarse) resumeTimer = setTimeout(clearSelection, 8000);
      });
    });

    /* don't burn frames while off-screen */
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        inView = entries[0].isIntersecting;
        ensure();
      }, { rootMargin: "120px 0px" }).observe(marquee);
    }
    document.addEventListener("visibilitychange", ensure);

    if ("ResizeObserver" in window) {
      var ro = new ResizeObserver(measure);
      ro.observe(marquee);
      tracks.forEach(function (s) { ro.observe(s.chips); });
    } else {
      window.addEventListener("resize", measure);
    }

    measure();
    ensure();
  })();

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

    var eggArmed = true;
    var CORNER = 34; // px from the top-right corner
    window.addEventListener("mousemove", function (e) {
      var inCorner = e.clientX >= window.innerWidth - CORNER && e.clientY <= CORNER;
      if (inCorner && e.altKey && eggArmed) {
        eggArmed = false;
        var next = toggleTheme(true);
        toast("⌥ + Top-Right Corner → " + (next === "dark" ? "Dark" : "Light") +
              " Mode — that’s MouseGestures.");
        dropHint();
      } else if (!inCorner) {
        eggArmed = true;
      }
    }, { passive: true });
  }

  /* ==========================================================
     The playground: a miniature desktop wired like the real app
     (8 zones × modifier × action), with switchable profiles.
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
    var sleepVeil = document.getElementById("sleepVeil");
    var lockscreen = document.getElementById("lockscreen");
    var winFront = document.getElementById("winFront");
    var caption = document.getElementById("demoCaption");

    var shiftHeld = false;
    var volume = 50, preMute = 50, playing = false;
    var hudTimer, volTimer, mediaTimer, transientTimer, minTimer, sleepTimer;

    if (matchMedia("(hover: none)").matches && caption) {
      caption.innerHTML = "<strong>Try it:</strong> tap a corner or an edge of the little desktop, " +
        "and switch profiles above. In the real app, your whole screen is the canvas.";
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

    var setVolume = function (v) {
      volume = Math.max(0, Math.min(100, v));
      volBar.style.setProperty("--vol", volume + "%");
      volHud.classList.add("show");
      mediaHud.classList.remove("show");
      clearTimeout(volTimer);
      volTimer = setTimeout(function () { volHud.classList.remove("show"); }, 1000);
    };

    var muteToggle = function () {
      if (volume > 0) { preMute = volume; setVolume(0); }
      else setVolume(preMute || 50);
    };

    var showMedia = function (icon) {
      mediaHud.setAttribute("data-ic", icon);
      mediaHud.classList.add("show");
      volHud.classList.remove("show");
      clearTimeout(mediaTimer);
      mediaTimer = setTimeout(function () { mediaHud.classList.remove("show"); }, 1000);
    };

    var playPause = function () {
      playing = !playing;
      showMedia(playing ? "play" : "pause");
    };

    var screenshot = function () {
      shotFlash.classList.remove("go");
      shotThumb.classList.remove("go");
      void shotFlash.offsetWidth;
      shotFlash.classList.add("go");
      shotThumb.classList.add("go");
    };

    var setSnap = function (side) {
      desktop.dataset.snap = desktop.dataset.snap === side ? "none" : side;
    };
    var snapFn = function (side) {
      return function () { setSnap(side); };
    };

    var minimizeFront = function () {
      winFront.classList.remove("is-min");
      void winFront.offsetWidth;
      winFront.classList.add("is-min");
      clearTimeout(minTimer);
      minTimer = setTimeout(function () { winFront.classList.remove("is-min"); }, 1500);
    };

    var sleepDisplay = function () {
      sleepVeil.classList.add("on");
      clearTimeout(sleepTimer);
      sleepTimer = setTimeout(function () { sleepVeil.classList.remove("on"); }, 1150);
    };

    /* Three profiles, each a coherent gesture set — the same trick the real
       app's profiles (and App Profiles) pull off at desk scale.
       zone id -> { glyph, base action, shift action } */
    var PROFILES = {
      everyday: {
        label: "Everyday",
        zones: {
          tl:     { g: "↖", base: ["Mission Control", function () { transientState("is-mission", 1500); }],
                            shift: ["App Exposé", function () { transientState("is-expose", 1500); }] },
          tr:     { g: "↗", base: ["Toggle Dark Mode", function () { toggleTheme(true); }],
                            shift: ["Screenshot", screenshot] },
          bl:     { g: "↙", base: ["Show Desktop", function () { transientState("is-showdesk", 1500); }] },
          br:     { g: "↘", base: ["Lock Screen", function () { desktop.classList.add("is-locked"); }] },
          top:    { g: "↑", base: ["Volume Up", function () { setVolume(volume + 12.5); }],
                            shift: ["Volume Down", function () { setVolume(volume - 12.5); }] },
          bottom: { g: "↓", base: ["Play / Pause", playPause] },
          left:   { g: "←", base: ["Snap Window Left", snapFn("left")] },
          right:  { g: "→", base: ["Snap Window Right", snapFn("right")] }
        }
      },
      windows: {
        label: "Windows",
        zones: {
          tl:     { g: "↖", base: ["Snap Top-Left Quarter", snapFn("tl")] },
          tr:     { g: "↗", base: ["Snap Top-Right Quarter", snapFn("tr")] },
          bl:     { g: "↙", base: ["Snap Bottom-Left Quarter", snapFn("bl")] },
          br:     { g: "↘", base: ["Snap Bottom-Right Quarter", snapFn("br")] },
          left:   { g: "←", base: ["Snap Left Half", snapFn("left")] },
          right:  { g: "→", base: ["Snap Right Half", snapFn("right")] },
          top:    { g: "↑", base: ["Maximize Window", snapFn("max")],
                            shift: ["Center Window", snapFn("center")] },
          bottom: { g: "↓", base: ["Tile Both Windows", snapFn("tile")],
                            shift: ["Minimize Window", minimizeFront] }
        }
      },
      media: {
        label: "Media",
        zones: {
          tl:     { g: "↖", base: ["Previous Track", function () { showMedia("prev"); }] },
          tr:     { g: "↗", base: ["Next Track", function () { showMedia("next"); }] },
          top:    { g: "↑", base: ["Volume Up", function () { setVolume(volume + 12.5); }],
                            shift: ["Mute", muteToggle] },
          bottom: { g: "↓", base: ["Play / Pause", playPause] },
          left:   { g: "←", base: ["Seek Back 10 s", function () { showMedia("rw"); }] },
          right:  { g: "→", base: ["Seek Forward 10 s", function () { showMedia("ff"); }] },
          bl:     { g: "↙", base: ["Volume Down", function () { setVolume(volume - 12.5); }] },
          br:     { g: "↘", base: ["Sleep Display", sleepDisplay] }
        }
      }
    };

    var ZONE_NAMES = {
      tl: "Top-left corner", tr: "Top-right corner",
      bl: "Bottom-left corner", br: "Bottom-right corner",
      top: "Top edge", bottom: "Bottom edge",
      left: "Left edge", right: "Right edge"
    };

    var currentProfile = "everyday";
    var zoneEls = {};
    var lastGlobalFire = 0;

    var fire = function (id) {
      var zone = PROFILES[currentProfile].zones[id];
      if (!zone) return;

      // one action at a time: clipping two zones in one motion fires once
      var now = performance.now();
      if (now - lastGlobalFire < 240) return;
      lastGlobalFire = now;

      desktop.classList.add("touched");
      if (desktop.classList.contains("is-locked")) desktop.classList.remove("is-locked");

      var entry = (shiftHeld && zone.shift) ? zone.shift : zone.base;
      showHud(zone.g, entry[0], shiftHeld && !!zone.shift);
      entry[1]();

      var zoneEl = zoneEls[id];
      zoneEl.classList.remove("zap");
      void zoneEl.offsetWidth;
      zoneEl.classList.add("zap");
    };

    /* Gesture detection: a zone fires when the cursor lands in it and stays
       for a beat (a flick that merely clips an edge on its way to a corner
       doesn't count), and it won't re-fire until the cursor leaves the zone.
       Click/tap always works and can deliberately repeat an action. */
    var DWELL = 100; // ms the cursor must stay before the gesture lands

    Array.prototype.forEach.call(demo.querySelectorAll(".zone"), function (zoneEl) {
      var id = zoneEl.dataset.zone;
      zoneEls[id] = zoneEl;
      var armed = true, dwellTimer = null;

      zoneEl.addEventListener("pointerenter", function (e) {
        if (e.pointerType !== "mouse" || !armed) return;
        clearTimeout(dwellTimer);
        dwellTimer = setTimeout(function () {
          armed = false;
          fire(id);
        }, DWELL);
      });
      zoneEl.addEventListener("pointerleave", function (e) {
        if (e.pointerType !== "mouse") return;
        clearTimeout(dwellTimer);
        armed = true;
      });
      zoneEl.addEventListener("click", function () {
        clearTimeout(dwellTimer);
        fire(id);
      });
    });

    lockscreen.addEventListener("click", function () {
      desktop.classList.remove("is-locked");
    });

    /* ---------- Profile tabs ---------- */

    var dpTabs = Array.prototype.slice.call(document.querySelectorAll(".dp-tab"));

    var setProfile = function (id, announce) {
      currentProfile = id;
      dpTabs.forEach(function (b) {
        b.setAttribute("aria-pressed", String(b.dataset.profile === id));
      });
      Object.keys(zoneEls).forEach(function (zid) {
        var z = PROFILES[id].zones[zid];
        var label = ZONE_NAMES[zid] + ": " + z.base[0] +
          (z.shift ? " (hold Shift: " + z.shift[0] + ")" : "");
        zoneEls[zid].setAttribute("aria-label", label);
      });
      if (announce) {
        desktop.classList.add("touched");
        showHud("⟳", "Switch Profile → " + PROFILES[id].label, false);
      }
    };

    dpTabs.forEach(function (b) {
      b.addEventListener("click", function () {
        if (b.dataset.profile !== currentProfile) setProfile(b.dataset.profile, true);
      });
    });

    setProfile("everyday", false);

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
