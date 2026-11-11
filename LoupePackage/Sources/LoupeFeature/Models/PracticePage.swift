import Foundation

// The practice app is a small real page (HTML and CSS) shown inside the setup window.
//
// It used to be drawn by hand, which meant an agent could only pull the few levers that
// drawing offered. A page has source, so a connected agent changes it the way it changes
// code in a real project: it reads the page and writes it back however the note asks.
//
// What keeps that safe: the page never runs scripts of its own and never loads anything
// from outside (see `PracticePageWebView`), and what an agent sends is cleaned here first.

public enum PracticePage {

    /// The page a practice starts with: a heading, a checkbox, a button, and grey bars
    /// standing in for the rest of an app
    public static let startingHTML = """
    <h1 id="heading">Weekend Planner</h1>
    <div class="row">
      <label id="reminder"><input type="checkbox"> Remind me on Friday</label>
      <button id="saveButton">Save Plan</button>
    </div>
    <ul class="plans" aria-hidden="true">
      <li><i style="width: 78%"></i><i style="width: 56%"></i></li>
      <li><i style="width: 62%"></i><i style="width: 44%"></i></li>
      <li><i style="width: 70%"></i><i style="width: 50%"></i></li>
      <li><i style="width: 50%"></i><i style="width: 36%"></i></li>
      <li><i style="width: 74%"></i><i style="width: 54%"></i></li>
      <li><i style="width: 58%"></i><i style="width: 42%"></i></li>
    </ul>
    """

    /// Longest page an agent may send
    public static let maxLength = 30_000

    /// What agents are told about the page, wherever it is handed to them
    public static let howToEdit = "The practice app is a small HTML page, and html is its current source. Change it however the note asks: anything HTML and CSS can express is allowed, including restyling, adding, moving and removing elements. A base stylesheet already styles h1, label, button, .row and .plans for light and dark mode; inline styles or a <style> block override it. Scripts and anything loaded from the internet are ignored. Keep the id and data-loupe-key attributes of elements you keep, so the user's notes stay attached to them."

    // MARK: Cleaning what an agent sends

    /// An agent's page, made safe to keep: trimmed, within the size limit, and without the
    /// tags that could run code or pull something in. Nil if nothing usable is left.
    /// (The page could not run or load any of it anyway. This keeps the stored source honest.)
    public static func cleaned(_ html: String) -> String? {
        var page = html
        let patterns = [
            #"(?is)<script\b.*?</script\s*>"#,
            #"(?is)<(script|iframe|frame|frameset|object|embed|applet|link|meta|base)\b[^>]*>"#,
            #"(?is)</(script|iframe|frame|frameset|object|embed|applet)\s*>"#,
        ]
        for pattern in patterns {
            page = page.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        page = page.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !page.isEmpty, page.count <= maxLength else { return nil }
        return page
    }

    // MARK: The pretend agent's changes, for the page to lay over itself

    /// The colours the pretend agent can use, as the page's own colour names
    static func cssColor(_ color: PracticeColor) -> String {
        color == .standard ? "" : "var(--loupe-\(color.rawValue))"
    }

    /// The pretend agent's changes as plain values the page's script understands, by element key.
    /// Elements it has not touched are left out.
    public static func overlay(for looks: [PracticeElement: PracticeLook]) -> [String: [String: Any]] {
        var overlay: [String: [String: Any]] = [:]
        for (element, look) in looks where look != PracticeLook(text: element.title) {
            var entry: [String: Any] = [
                "scale": Double(look.size.scale),
                "color": cssColor(look.color),
                "fill": element.role == "AXButton",
                "darkOnFill": look.color == .yellow,
                "bold": look.bold,
                "removed": look.removed,
            ]
            if element.isCheckbox { entry["checked"] = look.checked }
            if look.text != element.title { entry["text"] = look.text }
            overlay[element.id] = entry
        }
        return overlay
    }

    // MARK: The whole document

    /// The document the practice app's web view loads once. The page's content is put into
    /// its body afterwards, and again whenever it changes.
    public static let document = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
    <style>\(baseStyles)</style>
    </head>
    <body></body>
    </html>
    """

    static let baseStyles = """
    :root {
      color-scheme: light dark;
      --text: #1d1d1f; --line: rgba(0,0,0,.2); --fill: rgba(0,0,0,.07); --bar: rgba(0,0,0,.09); --thumb: rgba(0,0,0,.07);
      --loupe-red: #c62828; --loupe-orange: #b45309; --loupe-yellow: #8a6d00; --loupe-green: #1b7a34;
      --loupe-blue: #1d5fd0; --loupe-purple: #6d3fc4; --loupe-pink: #c2185b; --loupe-gray: #5f6672;
      --loupe-fill-yellow: #f2c200;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --text: #f5f5f7; --line: rgba(255,255,255,.22); --fill: rgba(255,255,255,.1); --bar: rgba(255,255,255,.1); --thumb: rgba(255,255,255,.07);
        --loupe-red: #ff6b6b; --loupe-orange: #ff9f45; --loupe-yellow: #ffd60a; --loupe-green: #4cd964;
        --loupe-blue: #5aa9ff; --loupe-purple: #b69cff; --loupe-pink: #ff7ab2; --loupe-gray: #a8afba;
      }
    }
    html, body { margin: 0; background: transparent; }
    body {
      font: 13px -apple-system, system-ui, sans-serif; color: var(--text);
      padding: 14px 16px; overflow: hidden; cursor: default;
      -webkit-user-select: none; user-select: none;
    }
    h1 { font-size: 17px; font-weight: 700; margin: 0 0 12px; padding: 2px 4px; width: fit-content; max-width: 100%; }
    .row { display: flex; align-items: center; justify-content: space-between; gap: 8px; margin: 0 0 18px; }
    label { display: inline-flex; align-items: center; gap: .45em; padding: 2px 4px; }
    input[type=checkbox] {
      -webkit-appearance: none; appearance: none; margin: 0; flex: none; position: relative;
      width: 1.08em; height: 1.08em; font-size: inherit; box-sizing: border-box;
      border: 1.5px solid color-mix(in srgb, currentColor 62%, transparent); border-radius: .26em;
    }
    input[type=checkbox]:checked { border-color: currentColor; background-color: currentColor; }
    input[type=checkbox]:checked::after {
      content: ""; position: absolute; left: 30%; top: 6%; width: 26%; height: 56%;
      border: solid Canvas; border-width: 0 .15em .15em 0; transform: rotate(45deg);
    }
    button {
      font: inherit; font-weight: 500; color: var(--text); background: var(--fill);
      border: 1px solid var(--line); border-radius: .46em; padding: .38em 1.08em; margin: 0;
    }
    .plans { list-style: none; margin: 0; padding: 0; }
    .plans li { position: relative; height: 34px; margin: 0 0 14px; padding-left: 44px; display: flex; flex-direction: column; justify-content: center; gap: 7px; }
    .plans li::before { content: ""; position: absolute; left: 0; top: 0; width: 34px; height: 34px; border-radius: 6px; background: var(--thumb); }
    .plans i { display: block; height: 8px; border-radius: 4px; background: var(--bar); }
    .plans i + i { opacity: .65; }
    :focus { outline: none; }
    body * { transition: font-size .35s ease, color .3s ease, background-color .3s ease, opacity .25s ease; }
    @media (prefers-reduced-motion: reduce) { body * { transition: none !important; animation: none !important; } }
    """

    /// Loupe's own script for the page. It reports what is under the pointer, where the
    /// noted elements are, and what the page's source is now, and it lays the pretend
    /// agent's changes over the page. It is the only script that ever runs there.
    public static let bridgeScript = #"""
    (function () {
      if (window.loupe) { return; }
      var post = function (message) { window.webkit.messageHandlers.loupe.postMessage(message); };
      var SKIP = '[aria-hidden="true"], [data-loupe-skip]';
      var TAGS = { BUTTON: 1, A: 1, INPUT: 1, SELECT: 1, TEXTAREA: 1, LABEL: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, P: 1, LI: 1, IMG: 1, SUMMARY: 1, TD: 1, TH: 1, BLOCKQUOTE: 1, FIGCAPTION: 1 };
      var TAG_SELECTOR = 'button, a, input, select, textarea, label, h1, h2, h3, h4, h5, h6, p, li, img, summary, td, th, blockquote, figcaption, [id], [data-loupe-key]';
      var pickable = false, tracked = [], hoverEl = null, lastHTML = null, appliedKeys = [], originalText = new Map(), settleUntil = 0, settling = false;

      function hasOwnText(el) {
        for (var i = 0; i < el.childNodes.length; i++) {
          var node = el.childNodes[i];
          if (node.nodeType === 3 && node.nodeValue.trim() !== '') { return true; }
        }
        return false;
      }

      // The thing a person means when the pointer is over `node`
      function pointable(node) {
        var el = node && node.nodeType === 1 ? node : (node ? node.parentElement : null);
        if (!el || !document.body.contains(el) || el === document.body) { return null; }
        if (el.closest(SKIP)) { return null; }
        while (el && el !== document.body) {
          if (TAGS[el.tagName] || el.id || el.dataset.loupeKey || hasOwnText(el)) {
            var label = el.closest('label');
            return label || el;
          }
          el = el.parentElement;
        }
        return null;
      }

      function find(key) {
        return document.getElementById(key) || document.querySelector('[data-loupe-key="' + String(key).replace(/["\\]/g, '\\$&') + '"]');
      }

      function keyFor(el) {
        if (el.id) { return el.id; }
        if (el.dataset.loupeKey) { return el.dataset.loupeKey; }
        var n = 1;
        while (find('item' + n)) { n++; }
        el.dataset.loupeKey = 'item' + n;
        return el.dataset.loupeKey;
      }

      function roleOf(el) {
        var tag = el.tagName;
        if (tag === 'LABEL') {
          var input = el.querySelector('input');
          if (input) { return roleOf(input); }
          return 'AXStaticText';
        }
        if (tag === 'BUTTON' || tag === 'SUMMARY') { return 'AXButton'; }
        if (tag === 'A') { return 'AXLink'; }
        if (/^H[1-6]$/.test(tag)) { return 'AXHeading'; }
        if (tag === 'IMG') { return 'AXImage'; }
        if (tag === 'SELECT') { return 'AXPopUpButton'; }
        if (tag === 'TEXTAREA') { return 'AXTextArea'; }
        if (tag === 'INPUT') {
          var type = (el.getAttribute('type') || 'text').toLowerCase();
          if (type === 'checkbox') { return 'AXCheckBox'; }
          if (type === 'radio') { return 'AXRadioButton'; }
          if (type === 'button' || type === 'submit' || type === 'reset') { return 'AXButton'; }
          if (type === 'range') { return 'AXSlider'; }
          return 'AXTextField';
        }
        return 'AXStaticText';
      }

      function titleOf(el) {
        var text = el.getAttribute('aria-label') || el.innerText || el.value || el.getAttribute('alt') || el.getAttribute('placeholder') || '';
        return text.replace(/\s+/g, ' ').trim().slice(0, 60);
      }

      function rectOf(el) {
        var r = el.getBoundingClientRect();
        return [r.left, r.top, r.width, r.height];
      }

      function describe(el, key) {
        return { key: key || el.id || el.dataset.loupeKey || '', role: roleOf(el), title: titleOf(el), rect: rectOf(el) };
      }

      function setHover(el) {
        if (el === hoverEl) { return; }
        hoverEl = el;
        post({ type: 'hover', element: el ? describe(el) : null });
      }

      function choose(el) {
        if (!pickable || !el) { return; }
        post({ type: 'select', element: describe(el, keyFor(el)) });
      }

      // The practice app is something to point at, not something to operate: nothing in
      // it reacts to clicks or typing, just as nothing does under Loupe's real overlay.
      document.addEventListener('mousemove', function (event) {
        setHover(pickable ? pointable(event.target) : null);
      }, true);
      document.documentElement.addEventListener('mouseleave', function () { setHover(null); }, true);
      document.addEventListener('mousedown', function (event) { event.preventDefault(); }, true);
      document.addEventListener('click', function (event) {
        event.preventDefault();
        event.stopPropagation();
        choose(pointable(event.target));
      }, true);
      document.addEventListener('focusin', function (event) {
        setHover(pickable ? pointable(event.target) : null);
      }, true);
      document.addEventListener('focusout', function () { setHover(null); }, true);
      document.addEventListener('keydown', function (event) {
        if (event.key === 'Tab') { return; }
        event.preventDefault();
        if (event.key === 'Enter' || event.key === ' ') { choose(pointable(event.target)); }
      }, true);
      window.addEventListener('resize', function () { report(); });

      // Tab reaches everything that can be pointed at, while pointing is possible
      function refreshTabbing() {
        var marked = document.querySelectorAll('[data-loupe-tab]');
        for (var i = 0; i < marked.length; i++) {
          marked[i].removeAttribute('tabindex');
          marked[i].removeAttribute('data-loupe-tab');
        }
        if (!pickable) { return; }
        var candidates = document.body.querySelectorAll(TAG_SELECTOR);
        for (var j = 0; j < candidates.length; j++) {
          var el = candidates[j];
          if (el.closest(SKIP) || pointable(el) !== el) { continue; }
          if (el.style.visibility === 'hidden') { continue; }
          el.setAttribute('tabindex', '0');
          el.setAttribute('data-loupe-tab', '');
        }
      }

      function setText(el, text) {
        if (!originalText.has(el)) { originalText.set(el, null); }
        var nodes = [];
        for (var i = 0; i < el.childNodes.length; i++) {
          if (el.childNodes[i].nodeType === 3 && el.childNodes[i].nodeValue.trim() !== '') { nodes.push(el.childNodes[i]); }
        }
        if (nodes.length === 0) { el.appendChild(document.createTextNode(text)); return; }
        var lead = el.querySelector('input') ? ' ' : '';
        nodes[nodes.length - 1].nodeValue = lead + text;
        for (var j = 0; j < nodes.length - 1; j++) { nodes[j].nodeValue = ''; }
      }

      // Lay the pretend agent's changes over the page
      function applyLooks(looks) {
        Object.keys(looks).forEach(function (key) {
          var el = find(key), look = looks[key];
          if (!el) { return; }
          if (!el.dataset.loupeBase) { el.dataset.loupeBase = parseFloat(getComputedStyle(el).fontSize) || 13; }
          var base = parseFloat(el.dataset.loupeBase);
          el.style.fontSize = look.scale === 1 ? '' : (Math.round(base * look.scale * 10) / 10) + 'px';
          if (look.fill) {
            el.style.backgroundColor = look.color ? (look.darkOnFill ? 'var(--loupe-fill-yellow)' : look.color) : '';
            el.style.borderColor = look.color ? 'transparent' : '';
            el.style.color = look.color ? (look.darkOnFill ? '#1d1d1f' : 'Canvas') : '';
          } else {
            el.style.color = look.color || '';
          }
          el.style.fontWeight = look.bold ? '800' : '';
          el.style.visibility = look.removed ? 'hidden' : '';
          if (typeof look.checked === 'boolean') {
            var box = el.matches('input') ? el : el.querySelector('input[type=checkbox]');
            if (box) {
              box.checked = look.checked;
              if (look.checked) { box.setAttribute('checked', ''); } else { box.removeAttribute('checked'); }
            }
          }
          if (typeof look.text === 'string') { setText(el, look.text); }
        });
        appliedKeys = Object.keys(looks);
      }

      // The page's source as it stands, without the marks Loupe's script left on it
      function snapshot() {
        var copy = document.body.cloneNode(true);
        var all = copy.querySelectorAll('*');
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          if (el.hasAttribute('data-loupe-tab')) { el.removeAttribute('tabindex'); el.removeAttribute('data-loupe-tab'); }
          el.removeAttribute('data-loupe-base');
          if (el.getAttribute('style') === '') { el.removeAttribute('style'); }
        }
        return copy.innerHTML.trim();
      }

      function report() {
        var frames = {};
        for (var i = 0; i < tracked.length; i++) {
          var el = find(tracked[i]);
          if (el) { frames[tracked[i]] = rectOf(el); }
        }
        if (hoverEl && !document.body.contains(hoverEl)) { hoverEl = null; }
        post({ type: 'frames', frames: frames, hover: hoverEl ? rectOf(hoverEl) : null });
      }

      // Things move for a moment after a change. Keep reporting until they stop,
      // then say what the page's source is now.
      function settle() {
        settleUntil = Date.now() + 700;
        if (settling) { return; }
        settling = true;
        var tick = function () {
          report();
          if (Date.now() < settleUntil) { requestAnimationFrame(tick); return; }
          settling = false;
          post({ type: 'snapshot', html: snapshot() });
        };
        requestAnimationFrame(tick);
      }

      window.loupe = {
        update: function (state) {
          var looks = state.looks || {};
          var keys = Object.keys(looks);
          var dropped = appliedKeys.some(function (key) { return keys.indexOf(key) < 0; });
          if (typeof state.html === 'string' && (state.html !== lastHTML || dropped)) {
            document.body.innerHTML = state.html;
            lastHTML = state.html;
            hoverEl = null;
            originalText = new Map();
            appliedKeys = [];
          }
          applyLooks(looks);
          pickable = !!state.pickable;
          tracked = state.tracked || [];
          refreshTabbing();
          if (!pickable) { setHover(null); }
          report();
          settle();
        }
      };
      post({ type: 'ready' });
    })();
    """#
}
