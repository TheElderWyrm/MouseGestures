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
    var lockscreen = document.getElementById("lockscreen");
    var winFront = document.getElementById("winFront");
    var caption = document.getElementById("demoCaption");
    var mbarApp = document.querySelector(".mbar-app");
    var mpFill = document.getElementById("mpFill");

    var shiftHeld = false;
    var volume = 50, preMute = 50, playing = false;
    var hudTimer, volTimer, mediaTimer, transientTimer, minTimer;

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

    /* the mini player's progress fill — nudged by seek/track actions so it
       feels connected to what you just fired, nothing more */
    var mpPos = 28;
    var setMpPos = function (p) {
      mpPos = Math.max(4, Math.min(96, p));
      if (mpFill) mpFill.style.setProperty("--mp", mpPos + "%");
    };

    var showMedia = function (icon) {
      mediaHud.setAttribute("data-ic", icon);
      mediaHud.classList.add("show");
      volHud.classList.remove("show");
      clearTimeout(mediaTimer);
      mediaTimer = setTimeout(function () { mediaHud.classList.remove("show"); }, 1000);
      if (icon === "ff") setMpPos(mpPos + 9);
      else if (icon === "rw") setMpPos(mpPos - 9);
      else if (icon === "next" || icon === "prev") setMpPos(6);
    };

    var playPause = function () {
      playing = !playing;
      desktop.classList.toggle("mp-playing", playing);
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

    /* Three profiles, each a coherent gesture set — the same trick the real
       app's profiles (and App Profiles) pull off at desk scale.
       zone id -> { glyph, short on-zone label, base action, shift action } */
    var PROFILES = {
      everyday: {
        label: "Everyday",
        zones: {
          tl:     { g: "↖", s: "Mission Control",
                            base: ["Mission Control", function () { transientState("is-mission", 1500); }],
                            shift: ["App Exposé", function () { transientState("is-expose", 1500); }] },
          tr:     { g: "↗", s: "Dark Mode",
                            base: ["Toggle Dark Mode", function () { toggleTheme(true); }],
                            shift: ["Screenshot", screenshot] },
          bl:     { g: "↙", s: "Show Desktop", base: ["Show Desktop", function () { transientState("is-showdesk", 1500); }] },
          br:     { g: "↘", s: "Lock Screen", base: ["Lock Screen", function () { desktop.classList.add("is-locked"); }] },
          top:    { g: "↑", s: "Volume Up",
                            base: ["Volume Up", function () { setVolume(volume + 12.5); }],
                            shift: ["Volume Down", function () { setVolume(volume - 12.5); }] },
          bottom: { g: "↓", s: "Play / Pause", base: ["Play / Pause", playPause] },
          left:   { g: "←", s: "Snap Left", base: ["Snap Window Left", snapFn("left")] },
          right:  { g: "→", s: "Snap Right", base: ["Snap Window Right", snapFn("right")] }
        }
      },
      windows: {
        label: "Windows",
        zones: {
          tl:     { g: "↖", s: "Top-Left ¼", base: ["Snap Top-Left Quarter", snapFn("tl")] },
          tr:     { g: "↗", s: "Top-Right ¼", base: ["Snap Top-Right Quarter", snapFn("tr")] },
          bl:     { g: "↙", s: "Bottom-Left ¼", base: ["Snap Bottom-Left Quarter", snapFn("bl")] },
          br:     { g: "↘", s: "Bottom-Right ¼", base: ["Snap Bottom-Right Quarter", snapFn("br")] },
          left:   { g: "←", s: "Left Half", base: ["Snap Left Half", snapFn("left")] },
          right:  { g: "→", s: "Right Half", base: ["Snap Right Half", snapFn("right")] },
          top:    { g: "↑", s: "Maximize",
                            base: ["Maximize Window", snapFn("max")],
                            shift: ["Center Window", snapFn("center")] },
          bottom: { g: "↓", s: "Tile Both",
                            base: ["Tile Both Windows", snapFn("tile")],
                            shift: ["Minimize Window", minimizeFront] }
        }
      },
      /* laid out like the app's drafted Media Control profile:
         prev | play/pause | next on top, seek on the sides, volume across the bottom */
      media: {
        label: "Media",
        zones: {
          tl:     { g: "↖", s: "Prev Track", base: ["Previous Track", function () { showMedia("prev"); }] },
          top:    { g: "↑", s: "Play / Pause", base: ["Play / Pause", playPause] },
          tr:     { g: "↗", s: "Next Track", base: ["Next Track", function () { showMedia("next"); }] },
          left:   { g: "←", s: "Back 10 s",
                            base: ["Seek Back 10 s", function () { showMedia("rw"); }],
                            shift: ["Seek Back 30 s", function () { showMedia("rw"); }] },
          right:  { g: "→", s: "Fwd 10 s",
                            base: ["Seek Forward 10 s", function () { showMedia("ff"); }],
                            shift: ["Seek Forward 30 s", function () { showMedia("ff"); }] },
          bl:     { g: "↙", s: "Vol Down", base: ["Volume Down", function () { setVolume(volume - 12.5); }] },
          bottom: { g: "↓", s: "Mute", base: ["Mute", muteToggle] },
          br:     { g: "↘", s: "Vol Up", base: ["Volume Up", function () { setVolume(volume + 12.5); }] }
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

    var fire = function (id, opts) {
      var zone = PROFILES[currentProfile].zones[id];
      if (!zone) return;

      // one action at a time: clipping two zones in one motion fires once
      var now = performance.now();
      if (now - lastGlobalFire < 240) return;
      lastGlobalFire = now;

      desktop.classList.add("touched");
      if (desktop.classList.contains("is-locked")) desktop.classList.remove("is-locked");

      // the phantom cursor passes its own shift state; real gestures use the keyboard's
      var wantShift = (opts && "shift" in opts) ? opts.shift : shiftHeld;
      var entry = (wantShift && zone.shift) ? zone.shift : zone.base;
      showHud(zone.g, entry[0], wantShift && !!zone.shift);
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
      desktop.dataset.profile = id;
      if (mbarApp) mbarApp.textContent = id === "media" ? "Music" : "Finder";
      if (id !== "media") desktop.classList.remove("mp-playing");
      dpTabs.forEach(function (b) {
        b.setAttribute("aria-pressed", String(b.dataset.profile === id));
      });
      Object.keys(zoneEls).forEach(function (zid) {
        var z = PROFILES[id].zones[zid];
        var label = ZONE_NAMES[zid] + ": " + z.base[0] +
          (z.shift ? " (hold Shift: " + z.shift[0] + ")" : "");
        zoneEls[zid].setAttribute("aria-label", label);
        var zl = zoneEls[zid].querySelector(".zl");
        if (zl) zl.textContent = z.s || z.base[0];
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

    var trailPush = null; // set by the trail; the phantom cursor feeds it too

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

      trailPush = function (x, y) {
        points.push({ x: x, y: y, t: performance.now() });
        if (points.length > 90) points.shift();
        if (!running) { running = true; requestAnimationFrame(draw); }
      };

      desktop.addEventListener("pointermove", function (e) {
        if (e.pointerType !== "mouse") return;
        var rect = desktop.getBoundingClientRect();
        trailPush(e.clientX - rect.left, e.clientY - rect.top);
      });

      function trailColors() {
        return docEl.getAttribute("data-theme") === "dark"
          ? ["76, 141, 255", "155, 107, 255"]
          : ["47, 111, 228", "124, 77, 219"];
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

    /* ---------- Phantom cursor: plays the current profile while you're away ----------
       A ghost pointer tours the zones and fires their real actions (HUD, trail
       and all), so the demo explains itself. The moment your own pointer comes
       near the demo it bows out; it returns a beat after you leave. */

    (function () {
      if (reducedMotion) return;

      var heroDemo = document.querySelector(".hero-demo") || demo;
      var ghostEl = document.createElement("div");
      ghostEl.className = "ghost";
      ghostEl.setAttribute("aria-hidden", "true");
      ghostEl.innerHTML = '<svg viewBox="0 0 24 24"><path d="M5.4 2.8 5.4 20.6 9.7 16.6 12.3 22.4 15.2 21.1 12.6 15.3 18.6 14.8 Z" ' +
        'fill="#16161d" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
      desktop.appendChild(ghostEl);

      /* Scripted tours. The everyday tour skips Dark Mode (it would flip the
         whole page under the reader) and Lock Screen (it waits for a click). */
      var TOURS = {
        everyday: [
          { z: "top" }, { z: "right" }, { z: "bottom" }, { z: "tl" },
          { z: "top", shift: true }, { z: "left" }, { z: "bl" }
        ],
        windows: [
          { z: "left" }, { z: "tl" }, { z: "br" }, { z: "top" },
          { z: "bottom" }, { z: "right" }, { z: "top", shift: true }, { z: "bottom", shift: true }
        ],
        media: [
          { z: "top" }, { z: "right" }, { z: "tr" }, { z: "br" },
          { z: "bottom" }, { z: "left" }, { z: "tl" }, { z: "bl" }
        ]
      };

      var gx = 0, gy = 0;
      var raf = null, timer = null, resumeTimer = null;
      var idx = -1, running = false, inView = false, userNear = false;

      function place() {
        // the path's arrow tip sits at (5.4, 2.8) of the 24-box; land the tip on target
        ghostEl.style.transform = "translate(" + (gx - 4.3) + "px," + (gy - 2.2) + "px)";
      }

      function zoneTarget(id) {
        var zr = zoneEls[id].getBoundingClientRect();
        var dr = desktop.getBoundingClientRect();
        return { x: zr.left - dr.left + zr.width / 2, y: zr.top - dr.top + zr.height / 2 };
      }

      // a plain lerp between two points, used for the small settle wiggle below
      function tweenLinear(x0, y0, x1, y1, dur, onDone) {
        var t0 = performance.now();
        function frame(t) {
          if (!running) return;
          var p = Math.min(1, (t - t0) / dur);
          var e = 1 - Math.pow(1 - p, 2);
          gx = x0 + (x1 - x0) * e;
          gy = y0 + (y1 - y0) * e;
          place();
          if (p < 1) { raf = requestAnimationFrame(frame); return; }
          onDone();
        }
        raf = requestAnimationFrame(frame);
      }

      // a hand slightly overshoots the target and corrects — reads as a
      // landing, not a stop-on-a-dime
      function settle(tx, ty, done) {
        var ang = Math.random() * Math.PI * 2;
        var ox = tx + Math.cos(ang) * 4.5, oy = ty + Math.sin(ang) * 4.5;
        tweenLinear(tx, ty, ox, oy, 75, function () {
          tweenLinear(ox, oy, tx, ty, 130, done);
        });
      }

      // curved (quadratic-bezier) travel, at an unhurried and slightly
      // randomized pace — a straight-line lerp reads as robotic
      function legTo(tx, ty, done) {
        var sx = gx, sy = gy;
        var dist = Math.hypot(tx - sx, ty - sy);
        var dur = Math.max(650, Math.min(1500, dist * 2.6)) * (0.85 + Math.random() * 0.3);
        var mx = (sx + tx) / 2, my = (sy + ty) / 2;
        var nx = -(ty - sy), ny = (tx - sx);
        var nlen = Math.hypot(nx, ny) || 1;
        var bow = Math.min(46, dist * 0.18) * (Math.random() < 0.5 ? -1 : 1);
        var cx = mx + (nx / nlen) * bow, cy = my + (ny / nlen) * bow;
        var t0 = performance.now();
        function frame(t) {
          if (!running) return;
          var p = Math.min(1, (t - t0) / dur);
          var e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
          var mt = 1 - e;
          gx = mt * mt * sx + 2 * mt * e * cx + e * e * tx;
          gy = mt * mt * sy + 2 * mt * e * cy + e * e * ty;
          place();
          if (trailPush) trailPush(gx, gy);
          if (p < 1) { raf = requestAnimationFrame(frame); return; }
          settle(tx, ty, done);
        }
        raf = requestAnimationFrame(frame);
      }

      function nextStop() {
        if (!running) return;
        var tour = TOURS[currentProfile] || TOURS.everyday;
        idx = (idx + 1) % tour.length;
        var stop = tour[idx];
        var t = zoneTarget(stop.z);
        legTo(t.x, t.y, function () {
          timer = setTimeout(function () {          // a real gesture dwells briefly
            if (!running) return;
            fire(stop.z, { shift: !!stop.shift });
            timer = setTimeout(nextStop, 1750 + Math.random() * 500); // linger so the HUD can be read
          }, 380);
        });
      }

      function start() {
        if (running || !inView || userNear || document.hidden) return;
        running = true;
        idx = -1;
        desktop.classList.remove("is-locked");
        var dr = desktop.getBoundingClientRect();
        gx = dr.width / 2;
        gy = dr.height / 2;
        place();
        ghostEl.classList.add("on");
        timer = setTimeout(nextStop, 1000);
      }

      function halt() {
        running = false;
        ghostEl.classList.remove("on");
        clearTimeout(timer);
        cancelAnimationFrame(raf);
      }

      /* your pointer owns the desk; the ghost only works when you're away */
      heroDemo.addEventListener("pointerenter", function (e) {
        if (e.pointerType !== "mouse") return;
        userNear = true;
        clearTimeout(resumeTimer);
        halt();
      });
      heroDemo.addEventListener("pointerleave", function (e) {
        if (e.pointerType !== "mouse") return;
        userNear = false;
        clearTimeout(resumeTimer);
        resumeTimer = setTimeout(start, 2600);
      });
      heroDemo.addEventListener("pointerdown", function (e) {
        if (e.pointerType === "mouse") return;      // touch: no enter/leave to rely on
        halt();
        clearTimeout(resumeTimer);
        resumeTimer = setTimeout(start, 8000);
      });

      if ("IntersectionObserver" in window) {
        new IntersectionObserver(function (entries) {
          inView = entries[0].isIntersecting;
          if (inView) start(); else halt();
        }, { threshold: 0.45 }).observe(desktop);
      } else {
        inView = true;
        start();
      }

      document.addEventListener("visibilitychange", function () {
        if (document.hidden) halt(); else start();
      });
    })();
  }
})();
