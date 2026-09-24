/*
 * Mangayomi extension host shim.
 *
 * Mangayomi extensions are plain JavaScript modules that subclass a global
 * `MProvider` and talk to a handful of host-provided globals — `Client` for
 * HTTP, `Document` for HTML parsing, `SharedPreferences` for per-source
 * settings, plus a set of String helpers and crypto utilities. This file
 * supplies all of them so an unmodified upstream extension runs inside Sozo.
 *
 * WHY THIS MATTERS FOR iOS
 * ------------------------
 * CloudStream (.cs3), Aniyomi and Mihon extensions are Android APKs loaded
 * through DexClassLoader — there is no equivalent on iOS, which is why the
 * extension features have been Android-only. Mangayomi extensions ship as
 * JavaScript, so they run anywhere a JS engine does. This shim executes inside
 * the same headless WebView the app already uses for its own extractors, which
 * exists on iOS, macOS and Windows as well as Android. That makes this the path
 * to extension support on iOS, not just another repo format.
 *
 * IMPLEMENTATION NOTES
 * --------------------
 * `Document` is backed by the browser's own DOMParser and querySelector rather
 * than a hand-rolled parser: it is already there, it is a real spec-compliant
 * HTML5 parser (extensions rely on tolerant parsing of malformed markup), and
 * it brings `document.evaluate` along for the extensions that use XPath.
 *
 * `Client` routes through `window.dartFetch`, the app's existing native fetch
 * bridge, so requests keep the cookie jar, redirects and Cloudflare handling
 * the rest of the app already has — and are not subject to the WebView's CORS.
 */
(function () {
  'use strict';

  if (globalThis.__sozoMangayomiReady) return;

  // --- HTTP ---------------------------------------------------------------

  function normaliseHeaders(headers) {
    const out = {};
    if (!headers) return out;
    if (typeof headers.forEach === 'function' && !Array.isArray(headers)) {
      try {
        headers.forEach((v, k) => { out[String(k)] = String(v); });
        return out;
      } catch (_) { /* fall through to plain-object handling */ }
    }
    for (const k of Object.keys(headers)) {
      const v = headers[k];
      if (v !== undefined && v !== null) out[String(k)] = String(v);
    }
    return out;
  }

  class MResponse {
    constructor(raw) {
      const data = raw ? raw.data : null;
      // `dartFetch` helpfully JSON-decodes application/json responses, but
      // extensions expect `res.body` to be the raw text and call JSON.parse on
      // it themselves. Re-stringify so `String(obj)` doesn't hand them
      // "[object Object]".
      this.body = data == null
        ? ''
        : (typeof data === 'string' ? data : JSON.stringify(data));
      this.statusCode = (raw && raw.status) ? Number(raw.status) : 0;
      this.headers = (raw && raw.headers) ? raw.headers : {};
    }
    // Several extensions read `.text` instead of `.body`.
    get text() { return this.body; }
    get isOk() { return this.statusCode >= 200 && this.statusCode < 400; }
  }

  class Client {
    /**
     * `options` is accepted and ignored on purpose — upstream extensions pass
     * things like `{ useDartHttpClient: true }` to pick a transport inside
     * Mangayomi. We only have one transport, and it is the right one.
     */
    constructor(options) { this.options = options || {}; }

    async get(url, headers) {
      return this._send('GET', url, headers, null);
    }

    async post(url, headers, body) {
      return this._send('POST', url, headers, body);
    }

    /**
     * Some sources ask for headers alone — a redirect target, a content length.
     * Annas Archive calls this in getDetail and threw a TypeError without it.
     */
    async head(url, headers) {
      return this._send('HEAD', url, headers, null);
    }

    async put(url, headers, body) {
      return this._send('PUT', url, headers, body);
    }

    async delete(url, headers, body) {
      return this._send('DELETE', url, headers, body);
    }

    async request(req) {
      const r = req || {};
      return this._send(r.method || 'GET', r.url, r.headers, r.body ?? r.data);
    }

    async _send(method, url, headers, body) {
      if (!url) throw new Error('Client: url is required');
      const payload = {
        url: String(url),
        method: String(method).toUpperCase(),
        headers: normaliseHeaders(headers),
      };
      if (body !== undefined && body !== null) {
        const contentTypeKey = Object.keys(payload.headers).find(k => k.toLowerCase() === 'content-type');
        const contentType = contentTypeKey ? payload.headers[contentTypeKey].toLowerCase() : '';
        if (typeof body !== 'string' && contentType.includes('application/x-www-form-urlencoded')) {
          const form = new URLSearchParams();
          for (const [key, value] of Object.entries(body)) {
            for (const item of (Array.isArray(value) ? value : [value])) {
              if (item != null) form.append(key, String(item));
            }
          }
          payload.body = form.toString();
        } else {
          payload.body = typeof body === 'string' ? body : JSON.stringify(body);
        }
        if (!contentTypeKey && typeof body !== 'string') {
          payload.headers['Content-Type'] = 'application/json';
        }
      }
      const raw = await window.dartFetch(payload);
      return new MResponse(raw);
    }
  }

  // --- HTML ---------------------------------------------------------------

  /**
   * Wraps a DOM node in the element API Mangayomi extensions expect.
   * Returned by `Document.select*`; also usable as a sub-document, since
   * extensions routinely call `.select()` on a result of `.selectFirst()`.
   */
  class MElement {
    constructor(node) { this._node = node; }

    // Untrimmed, as upstream's is. Sources trim it themselves where they
    // want it trimmed, and some compare it exactly: kolnovel's next page is
    // `.text == "Next "`, so a trimmed "Next" ended every list at page one.
    get text() { return this._node ? (this._node.textContent || '') : ''; }
    get rawText() { return this.text; }
    get html() { return this._node ? (this._node.innerHTML || '') : ''; }
    /**
     * Upstream's name for the same thing, and the one extensions actually use.
     *
     * Mangayomi calls it `innerHtml`; we only had `html`, so every
     * `.innerHtml` in an extension evaluated to `undefined` — a chapter body
     * that came back as the literal string "undefined", and 103 call sites
     * across the novel sources alone.
     */
    get innerHtml() { return this.html; }
    get outerHtml() { return this._node ? (this._node.outerHTML || '') : ''; }
    get className() { return this._node ? (this._node.className || '') : ''; }
    get id() { return this._node ? (this._node.id || '') : ''; }
    get tagName() {
      return this._node && this._node.tagName
        ? this._node.tagName.toLowerCase() : '';
    }

    attr(name) {
      if (!this._node || !this._node.getAttribute) return '';
      const v = this._node.getAttribute(name);
      return v == null ? '' : v;
    }
    // Getters, not methods — upstream declares them as properties and every
    // extension reads them without parentheses.
    //
    // As methods, `el.getHref` evaluated to the Function itself. It went into
    // the result object, and `JSON.stringify` at the WebView boundary drops
    // function-valued properties silently — so the url was simply absent, the
    // `if (link.isEmpty) continue` guard skipped the row, and browse, search
    // and the chapter list all came back empty. That is the whole reason no
    // novel source worked: 38 `.getHref` and 18 `.getSrc` across them, and not
    // one of them written with parentheses.
    get getHref() { return this.attr('href'); }
    get getSrc() { return this.attr('src'); }
    get getDataSrc() { return this.attr('data-src') || this.attr('src'); }
    get getImg() { return this.attr('data-src') || this.attr('src'); }
    /** Ours, kept for anything already written against it. */
    get getDst() { return this.attr('data-src') || this.attr('src'); }

    hasAttr(name) {
      return !!(this._node && this._node.hasAttribute &&
        this._node.hasAttribute(name));
    }

    get localName() {
      return this._node && this._node.localName
        ? String(this._node.localName).toLowerCase() : this.tagName;
    }

    get nextElementSibling() {
      const n = this._node && this._node.nextElementSibling;
      return n ? new MElement(n) : null;
    }

    get previousElementSibling() {
      const n = this._node && this._node.previousElementSibling;
      return n ? new MElement(n) : null;
    }

    get attributes() {
      const out = {};
      if (!this._node || !this._node.attributes) return out;
      for (const a of this._node.attributes) out[a.name] = a.value;
      return out;
    }

    select(query) { return selectAll(this._node, query); }
    selectFirst(query) { return selectOne(this._node, query); }
    xpath(expr) { return evaluateXPath(this._node, expr); }

    get parent() {
      return this._node && this._node.parentElement
        ? new MElement(this._node.parentElement) : null;
    }
    get children() {
      if (!this._node) return [];
      return Array.from(this._node.children).map((c) => new MElement(c));
    }
  }

  // --- jsoup selectors ------------------------------------------------------
  //
  // Mangayomi parses with a jsoup-style engine, and sources use its pseudo
  // selectors: `.serl:contains('الكاتب') a`, `div.d p:contains(by) a`,
  // `li:eq(2)`. The browser's querySelectorAll rejects them, so every such
  // lookup came back empty — author, genre and status on kolnovel and
  // bookReadFree. The native engine still does all the CSS; only the jsoup
  // parts are filtered here.

  const JSOUP = /:(containsOwn|containsData|containsWholeText|contains|matchesOwn|matches|eq|lt|gt)\(/i;

  /** The index just past the `)` closing the `(` at [open], quotes respected. */
  function closeParen(sel, open) {
    let depth = 0;
    let quote = null;
    for (let i = open; i < sel.length; i++) {
      const c = sel[i];
      if (quote) {
        if (c === '\\') i++;
        else if (c === quote) quote = null;
      } else if (c === '"' || c === "'") quote = c;
      else if (c === '(') depth++;
      else if (c === ')' && --depth === 0) return i + 1;
    }
    return sel.length;
  }

  function splitTopLevel(sel, sepTest) {
    const parts = [];
    let depth = 0;
    let quote = null;
    let start = 0;
    for (let i = 0; i < sel.length; i++) {
      const c = sel[i];
      if (quote) {
        if (c === '\\') i++;
        else if (c === quote) quote = null;
      } else if (c === '"' || c === "'") quote = c;
      else if (c === '(' || c === '[') depth++;
      else if (c === ')' || c === ']') depth--;
      else if (depth === 0 && sepTest(c)) {
        parts.push(sel.slice(start, i));
        start = i + 1;
      }
    }
    parts.push(sel.slice(start));
    return parts;
  }

  function unquote(arg) {
    const a = arg.trim();
    return /^(['"]).*\1$/.test(a) ? a.slice(1, -1) : a;
  }

  function ownText(node) {
    let out = '';
    for (const c of node.childNodes || []) if (c.nodeType === 3) out += c.nodeValue;
    return out;
  }

  function siblingIndex(node) {
    let i = 0;
    for (let n = node.previousElementSibling; n; n = n.previousElementSibling) i++;
    return i;
  }

  function norm(text) { return String(text || '').replace(/\s+/g, ' ').toLowerCase(); }

  function regexOf(arg) {
    try { return new RegExp(unquote(arg)); } catch (_) { return /$^/; }
  }

  function pseudoTest(name, arg, node) {
    switch (name.toLowerCase()) {
      case 'contains': return norm(node.textContent).includes(norm(unquote(arg)));
      case 'containsown': return norm(ownText(node)).includes(norm(unquote(arg)));
      case 'containswholetext': return (node.textContent || '').includes(unquote(arg));
      case 'containsdata': return (node.textContent || '').includes(unquote(arg));
      case 'matches': return regexOf(arg).test(node.textContent || '');
      case 'matchesown': return regexOf(arg).test(ownText(node));
      case 'eq': return siblingIndex(node) === Number(arg);
      case 'lt': return siblingIndex(node) < Number(arg);
      case 'gt': return siblingIndex(node) > Number(arg);
      default: return false;
    }
  }

  /** Whether [node] matches one compound selector ("p.x:contains(y)"). */
  function matchesCompound(node, compound) {
    let native = '';
    let rest = compound;
    const tests = [];
    for (let m = JSOUP.exec(rest); m; m = JSOUP.exec(rest)) {
      const open = m.index + m[0].length - 1;
      const end = closeParen(rest, open);
      native += rest.slice(0, m.index);
      tests.push([m[1], rest.slice(open + 1, end - 1)]);
      rest = rest.slice(end);
    }
    native += rest;
    if (native.trim() && !node.matches(native.trim())) return false;
    return tests.every(([name, arg]) => pseudoTest(name, arg, node));
  }

  /** The compound at the start of [sel] and what follows its combinator. */
  function firstCompound(sel) {
    let depth = 0;
    let quote = null;
    for (let i = 0; i < sel.length; i++) {
      const c = sel[i];
      if (quote) {
        if (c === '\\') i++;
        else if (c === quote) quote = null;
      } else if (c === '"' || c === "'") quote = c;
      else if (c === '(' || c === '[') depth++;
      else if (c === ')' || c === ']') depth--;
      else if (depth === 0 && /[\s>+~]/.test(c)) return [sel.slice(0, i), sel.slice(i)];
    }
    return [sel, ''];
  }

  function inDocumentOrder(nodes) {
    const unique = Array.from(new Set(nodes));
    return unique.sort((a, b) =>
      a === b ? 0 : (a.compareDocumentPosition(b) & 4 ? -1 : 1));
  }

  /** One selector without top-level commas, jsoup pseudos allowed. */
  function selectComplex(root, sel) {
    const m = JSOUP.exec(sel);
    if (!m) return Array.from(root.querySelectorAll(sel));
    // Everything before the compound holding the first jsoup pseudo is plain
    // CSS; that compound is matched here; the rest is searched from each hit.
    const before = sel.slice(0, m.index);
    const cut = Math.max(
      before.lastIndexOf(' '), before.lastIndexOf('>'),
      before.lastIndexOf('+'), before.lastIndexOf('~'));
    const lead = before.slice(0, cut + 1);
    const [compound, tail] = firstCompound(sel.slice(cut + 1));
    const native = compound.replace(new RegExp(JSOUP.source + '[^)]*\\)', 'gi'), '').trim() || '*';
    const candidates = Array.from(root.querySelectorAll(lead + native))
      .filter((n) => matchesCompound(n, compound));
    const t = tail.trim();
    if (!t) return candidates;
    const out = [];
    for (const n of candidates) {
      if (t[0] === '+' || t[0] === '~') {
        const next = t.slice(1).trim();
        const [sib, deeper] = firstCompound(next);
        for (let s2 = n.nextElementSibling; s2; s2 = s2.nextElementSibling) {
          if (matchesCompound(s2, sib)) {
            if (deeper.trim()) out.push(...selectComplex(s2, ':scope' + deeper));
            else out.push(s2);
          }
          if (t[0] === '+') break;
        }
      } else {
        out.push(...selectComplex(n, ':scope' + (t[0] === '>' ? ' ' : ' ') + t));
      }
    }
    return inDocumentOrder(out);
  }

  function jsoupSelect(root, query) {
    if (!JSOUP.test(query)) return Array.from(root.querySelectorAll(query));
    const parts = splitTopLevel(query, (c) => c === ',').map((p) => p.trim()).filter(Boolean);
    const found = [];
    for (const part of parts) found.push(...selectComplex(root, part));
    return parts.length > 1 ? inDocumentOrder(found) : found;
  }

  function selectAll(root, query) {
    if (!root || !query) return [];
    try {
      return jsoupSelect(root, String(query)).map((n) => new MElement(n));
    } catch (_) {
      // An invalid selector must not take the whole extension down — upstream
      // sources ship typos, and Mangayomi's parser tolerates some of them.
      return [];
    }
  }

  // Never null, as upstream's is never null. Mangayomi's selectFirst hands
  // back an element whatever it finds, and a miss reads as empty — so its
  // sources are written as `el.selectFirst("img").getSrc` with no guard. Ours
  // returned null, and that one line on Anna's Archive ran against every
  // <a> on the page, so the first anchor without an image threw and the
  // whole list was lost. An empty element answers '' to everything, which is
  // what the source was written to expect.
  function selectOne(root, query) {
    if (!root || !query) return new MElement(null);
    try {
      if (JSOUP.test(String(query))) {
        return new MElement(jsoupSelect(root, String(query))[0] || null);
      }
      return new MElement(root.querySelector(query));
    } catch (_) {
      return new MElement(null);
    }
  }

  function evaluateXPath(root, expr) {
    const out = [];
    if (!root || !expr) return out;
    try {
      const doc = root.ownerDocument || root;
      const res = doc.evaluate(expr, root, null,
        XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
      for (let i = 0; i < res.snapshotLength; i++) {
        const n = res.snapshotItem(i);
        out.push(n.nodeType === 1 ? new MElement(n) : String(n.textContent || ''));
      }
    } catch (_) { /* malformed expression → no matches */ }
    return out;
  }

  const __parser = new DOMParser();

  class MDocument {
    constructor(html) {
      // 'text/html' (not XML): sources are full of unclosed tags and the HTML
      // parser is the only one that recovers from them the way a browser does.
      this._doc = __parser.parseFromString(String(html ?? ''), 'text/html');
    }
    select(query) { return selectAll(this._doc, query); }
    selectFirst(query) { return selectOne(this._doc, query); }
    xpath(expr) { return evaluateXPath(this._doc, expr); }
    xpathFirst(expr) { return evaluateXPath(this._doc, expr)[0] || null; }
    get body() { return new MElement(this._doc.body); }
    get html() { return this._doc.documentElement ? this._doc.documentElement.outerHTML : ''; }
    get text() { return this._doc.body ? (this._doc.body.textContent || '') : ''; }

    // The rest of upstream's surface. None of it is load-bearing for the
    // sources we ship today; all of it is the same class of silent break as
    // `innerHtml` was, and it is three lines each.
    get outerHtml() { return this.html; }
    get innerHtml() {
      return this._doc.documentElement ? this._doc.documentElement.innerHTML : '';
    }
    get documentElement() {
      return this._doc.documentElement ? new MElement(this._doc.documentElement) : null;
    }
    get head() { return this._doc.head ? new MElement(this._doc.head) : null; }
    get parent() { return null; }
    get children() {
      const root = this._doc.documentElement;
      if (!root) return [];
      return Array.from(root.children || []).map((n) => new MElement(n));
    }
    attr(name) {
      const root = this._doc.documentElement;
      if (!root || !root.getAttribute) return '';
      const v = root.getAttribute(name);
      return v == null ? '' : v;
    }
    hasAttr(name) {
      const root = this._doc.documentElement;
      return !!(root && root.hasAttribute && root.hasAttribute(name));
    }
    getElementById(id) {
      const n = this._doc.getElementById ? this._doc.getElementById(id) : null;
      return n ? new MElement(n) : null;
    }
    getElementsByTagName(tag) {
      return Array.from(this._doc.getElementsByTagName(tag) || [])
        .map((n) => new MElement(n));
    }
    getElementsByClassName(name) {
      return Array.from(this._doc.getElementsByClassName(name) || [])
        .map((n) => new MElement(n));
    }
  }

  // --- per-source preferences --------------------------------------------

  /**
   * Backed by a plain object the host seeds before each call and reads back
   * after. Synchronous by contract — extensions call `preference.get(key)`
   * inline inside `getBaseUrl()` — so it cannot round-trip to Dart per access.
   */
  class SharedPreferences {
    get(key) {
      const store = globalThis.__sozoPrefs || {};
      const v = store[key];
      return v === undefined || v === null ? '' : v;
    }
    getString(key, def) { const v = this.get(key); return v === '' ? (def ?? '') : String(v); }
    getInt(key, def) { const v = this.get(key); return v === '' ? (def ?? 0) : parseInt(v, 10); }
    getBool(key, def) { const v = this.get(key); return v === '' ? (def ?? false) : v === true || v === 'true'; }
    getStringList(key, def) { const v = this.get(key); return Array.isArray(v) ? v : (def ?? []); }
    set(key, value) {
      globalThis.__sozoPrefs = globalThis.__sozoPrefs || {};
      globalThis.__sozoPrefs[key] = value;
      // Marked so the host can persist only what actually changed.
      globalThis.__sozoPrefsDirty = true;
    }
    setString(key, v) { this.set(key, String(v)); }
    setInt(key, v) { this.set(key, Number(v)); }
    setBool(key, v) { this.set(key, !!v); }
  }

  // --- base class ---------------------------------------------------------

  class MProvider {
    /**
     * `source` falls back to the global the host sets before instantiating:
     * extensions that declare their own zero-arg constructor and call `super()`
     * would otherwise lose `this.source`, and `this.source.baseUrl` is used by
     * a large fraction of them.
     */
    constructor(source) {
      this.source = source || globalThis.__sozoSource || {};
    }
    getHeaders(url) { return { Referer: (this.source && this.source.baseUrl) || url || '' }; }
    getFilterList() { return []; }
    getSourcePreferences() { return []; }
  }

  // --- String helpers extensions rely on ----------------------------------

  function defineStringHelper(name, fn) {
    if (String.prototype[name]) return;
    Object.defineProperty(String.prototype, name, {
      value: fn, writable: true, configurable: true, enumerable: false,
    });
  }

  defineStringHelper('substringAfter', function (delim) {
    const i = this.indexOf(delim);
    return i < 0 ? String(this) : this.slice(i + delim.length);
  });
  defineStringHelper('substringAfterLast', function (delim) {
    const i = this.lastIndexOf(delim);
    return i < 0 ? String(this) : this.slice(i + delim.length);
  });
  defineStringHelper('substringBefore', function (delim) {
    const i = this.indexOf(delim);
    return i < 0 ? String(this) : this.slice(0, i);
  });
  defineStringHelper('substringBeforeLast', function (delim) {
    const i = this.lastIndexOf(delim);
    return i < 0 ? String(this) : this.slice(0, i);
  });
  defineStringHelper('substringBetween', function (left, right) {
    const a = this.indexOf(left);
    if (a < 0) return '';
    const from = a + left.length;
    const b = this.indexOf(right, from);
    return b < 0 ? '' : this.slice(from, b);
  });

  // --- crypto / obfuscation helpers ---------------------------------------

  /** Unpacks the classic `eval(function(p,a,c,k,e,d){…})` packer. */
  function unpackJs(source) {
    try {
      const m = String(source).match(
        /}\s*\(\s*'(.*?)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'(.*?)'\.split\('\|'\)/,
      );
      if (!m) return String(source);
      let [, p, a, c, k] = m;
      a = parseInt(a, 10); c = parseInt(c, 10);
      const keys = k.split('|');
      const base = (n) => (n < a ? '' : base(Math.floor(n / a)))
        + ((n = n % a) > 35 ? String.fromCharCode(n + 29) : n.toString(36));
      let out = p;
      while (c--) {
        if (keys[c]) {
          out = out.replace(new RegExp('\\b' + base(c) + '\\b', 'g'), keys[c]);
        }
      }
      return out;
    } catch (_) {
      return String(source);
    }
  }

  const enc = new TextEncoder();

  function bytesToHex(buf) {
    return Array.from(new Uint8Array(buf))
      .map((b) => b.toString(16).padStart(2, '0')).join('');
  }
  function base64ToBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function bytesToBase64(bytes) {
    let bin = '';
    const arr = new Uint8Array(bytes);
    for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
    return btoa(bin);
  }

  /**
   * CryptoJS-compatible AES: OpenSSL "Salted__" envelope with the EVP_BytesToKey
   * (MD5-based) KDF. WebCrypto has no MD5, so the KDF is implemented directly —
   * it is only key derivation, never a security boundary here, and matching
   * CryptoJS byte-for-byte is the whole point.
   */
  function md5(bytes) {
    // Minimal MD5 over a Uint8Array → Uint8Array(16).
    function rl(x, c) { return (x << c) | (x >>> (32 - c)); }
    const s = [7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
               5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
               4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
               6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21];
    const K = new Int32Array(64);
    for (let i = 0; i < 64; i++) K[i] = (Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296)) | 0;
    const ml = bytes.length;
    const withPad = new Uint8Array((((ml + 8) >> 6) + 1) << 6);
    withPad.set(bytes);
    withPad[ml] = 0x80;
    const bitLen = ml * 8;
    new DataView(withPad.buffer).setUint32(withPad.length - 8, bitLen >>> 0, true);
    new DataView(withPad.buffer).setUint32(withPad.length - 4, Math.floor(bitLen / 4294967296), true);
    let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
    const view = new DataView(withPad.buffer);
    for (let off = 0; off < withPad.length; off += 64) {
      let A = a0, B = b0, C = c0, D = d0;
      for (let i = 0; i < 64; i++) {
        let F, g;
        if (i < 16) { F = (B & C) | (~B & D); g = i; }
        else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
        else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
        else { F = C ^ (B | ~D); g = (7 * i) % 16; }
        F = (F + A + K[i] + view.getUint32(off + g * 4, true)) | 0;
        A = D; D = C; C = B;
        B = (B + rl(F, s[i])) | 0;
      }
      a0 = (a0 + A) | 0; b0 = (b0 + B) | 0; c0 = (c0 + C) | 0; d0 = (d0 + D) | 0;
    }
    const out = new Uint8Array(16);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, a0 >>> 0, true); dv.setUint32(4, b0 >>> 0, true);
    dv.setUint32(8, c0 >>> 0, true); dv.setUint32(12, d0 >>> 0, true);
    return out;
  }

  function evpBytesToKey(password, salt, keyLen, ivLen) {
    const pw = enc.encode(password);
    let d = new Uint8Array(0);
    let prev = new Uint8Array(0);
    while (d.length < keyLen + ivLen) {
      const input = new Uint8Array(prev.length + pw.length + salt.length);
      input.set(prev, 0);
      input.set(pw, prev.length);
      input.set(salt, prev.length + pw.length);
      prev = md5(input);
      const next = new Uint8Array(d.length + prev.length);
      next.set(d); next.set(prev, d.length);
      d = next;
    }
    return { key: d.slice(0, keyLen), iv: d.slice(keyLen, keyLen + ivLen) };
  }

  async function decryptAESCryptoJS(cipherB64, passphrase) {
    const raw = base64ToBytes(cipherB64);
    // "Salted__" + 8-byte salt + ciphertext
    const salt = raw.slice(8, 16);
    const data = raw.slice(16);
    const { key, iv } = evpBytesToKey(passphrase, salt, 32, 16);
    const k = await crypto.subtle.importKey('raw', key, 'AES-CBC', false, ['decrypt']);
    const plain = await crypto.subtle.decrypt({ name: 'AES-CBC', iv }, k, data);
    return new TextDecoder().decode(plain);
  }

  async function encryptAESCryptoJS(plainText, passphrase) {
    const salt = crypto.getRandomValues(new Uint8Array(8));
    const { key, iv } = evpBytesToKey(passphrase, salt, 32, 16);
    const k = await crypto.subtle.importKey('raw', key, 'AES-CBC', false, ['encrypt']);
    const ct = new Uint8Array(
      await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, k, enc.encode(plainText)),
    );
    const out = new Uint8Array(16 + ct.length);
    out.set(enc.encode('Salted__'), 0);
    out.set(salt, 8);
    out.set(ct, 16);
    return bytesToBase64(out);
  }

  /** Raw AES-CBC with an explicit key/iv (no OpenSSL envelope). */
  async function cryptoHandler(text, ivString, secretKeyString, encryptFlag) {
    const key = await crypto.subtle.importKey(
      'raw', enc.encode(secretKeyString), 'AES-CBC', false,
      [encryptFlag ? 'encrypt' : 'decrypt'],
    );
    const iv = enc.encode(ivString);
    if (encryptFlag) {
      const ct = await crypto.subtle.encrypt({ name: 'AES-CBC', iv }, key, enc.encode(text));
      return bytesToBase64(ct);
    }
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-CBC', iv }, key, base64ToBytes(text),
    );
    return new TextDecoder().decode(plain);
  }

  // --- built-in video extractors -----------------------------------------
  //
  // Mangayomi gives anime sources a set of host extractors as globals —
  // `streamWishExtractor(url, prefix)` and the rest — so a source hands a
  // mirror page over instead of scraping it itself. None of them existed
  // here: a source calling one threw a ReferenceError and lost the mirror,
  // or the whole episode. Each returns Mangayomi's video shape, and an empty
  // list when the host has changed or refuses; never a throw.

  const ORIGIN = (u) => { try { return new URL(u).origin; } catch (_) { return ''; } };

  async function pageText(url, headers) {
    try {
      const res = await new Client().get(url, headers || {});
      return res.isOk ? res.body : '';
    } catch (_) {
      return '';
    }
  }

  const PACKED = /eval\(function\(p,a,c,k,e,[dr]\)[\s\S]*?\.split\(['"]\|['"]\)[^)]*\)\)/;

  /** The page's packed player script unpacked, appended to the page itself. */
  function withUnpacked(html) {
    const m = html.match(PACKED);
    if (!m) return html;
    try { return html + '\n' + unpackJs(m[0]); } catch (_) { return html; }
  }

  function video(url, quality, headers) {
    return { url, originalUrl: url, quality, headers: headers || {} };
  }

  /** One row per variant of an HLS master, after the master itself. */
  async function hlsRows(master, headers, label) {
    const rows = [video(master, `${label} - Auto`, headers)];
    const text = await pageText(master, headers);
    if (!text.includes('#EXT-X-STREAM-INF')) return rows;
    const lines = text.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      const res = /RESOLUTION=\d+x(\d+)/.exec(lines[i]);
      const next = (lines[i + 1] || '').trim();
      if (!next || next.startsWith('#')) continue;
      let abs = next;
      try { abs = new URL(next, master).href; } catch (_) {}
      rows.push(video(abs, `${label} - ${res ? res[1] + 'p' : 'Video'}`, headers));
    }
    return rows;
  }

  function firstMatch(text, patterns) {
    for (const re of patterns) {
      const m = re.exec(text);
      if (m && m[1]) return m[1].replace(/\\\//g, '/');
    }
    return '';
  }

  const HLS_IN_PLAYER = [
    /file\s*:\s*["']([^"']+\.m3u8[^"']*)["']/,
    /["']hls\d?["']\s*:\s*["']([^"']+)["']/,
    /sources\s*:\s*\[\s*\{\s*file\s*:\s*["']([^"']+)["']/,
    /src\s*:\s*["']([^"']+\.m3u8[^"']*)["']/,
  ];

  /** StreamWish, Filemoon and their many mirror domains: a packed jwplayer. */
  async function packedHls(url, label, depth) {
    const headers = { Referer: ORIGIN(url) + '/' };
    let html = await pageText(url, headers);
    if (!html) return [];
    let found = firstMatch(withUnpacked(html), HLS_IN_PLAYER);
    // Filemoon puts the player in an iframe on its own page.
    if (!found && !depth) {
      const frame = /<iframe[^>]+src=["']([^"']+)["']/i.exec(html);
      if (frame) {
        let next = frame[1];
        try { next = new URL(next, url).href; } catch (_) {}
        return packedHls(next, label, 1);
      }
    }
    if (!found) return [];
    try { found = new URL(found, url).href; } catch (_) {}
    return hlsRows(found, headers, label);
  }

  const extractors = {
    streamWishExtractor: (url, prefix) =>
      packedHls(url, `${prefix || ''}StreamWish`.trim()),

    filemoonExtractor: async (url, prefix, suffix) =>
      (await packedHls(url, `${prefix || ''}Filemoon`.trim()))
        .map((v) => Object.assign(v, { quality: v.quality + (suffix || '') })),

    mp4UploadExtractor: async (url, headers, prefix, suffix) => {
      const h = Object.assign({ Referer: 'https://www.mp4upload.com/' }, normaliseHeaders(headers));
      const html = withUnpacked(await pageText(url, h));
      const src = firstMatch(html, [/src\s*:\s*["']([^"']+\.mp4[^"']*)["']/, /player\.src\(\s*["']([^"']+)["']/]);
      return src ? [video(src, `${prefix || ''}Mp4Upload${suffix || ''}`, h)] : [];
    },

    doodExtractor: async (url, quality) => {
      const html = await pageText(url, {});
      const pass = /\/pass_md5\/[^'"\s]+/.exec(html);
      if (!pass) return [];
      const origin = ORIGIN(url);
      const base = await pageText(origin + pass[0], { Referer: url });
      if (!base) return [];
      const token = pass[0].split('/').pop();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      let tail = '';
      for (let i = 0; i < 10; i++) tail += chars[Math.floor(Math.random() * chars.length)];
      return [video(`${base}${tail}?token=${token}&expiry=${Date.now()}`,
        quality || 'Doodstream', { Referer: origin + '/' })];
    },

    streamTapeExtractor: async (url, quality) => {
      const html = await pageText(url, {});
      const m = /robotlink'\)\.innerHTML\s*=\s*'([^']+)'\s*\+\s*\('([^']+)'\)(?:\.substring\((\d+)\))?/.exec(html);
      if (!m) return [];
      const tail = m[2].substring(m[3] ? Number(m[3]) : 3);
      const link = 'https:' + m[1] + tail;
      return [video(link, quality || 'StreamTape', { Referer: ORIGIN(url) + '/' })];
    },

    yourUploadExtractor: async (url, headers, name, prefix) => {
      const h = Object.assign({ Referer: 'https://www.yourupload.com/' }, normaliseHeaders(headers));
      const html = await pageText(url, h);
      const src = firstMatch(html, [/file\s*:\s*'([^']+)'/, /file\s*:\s*"([^"]+)"/]);
      return src ? [video(src, `${prefix || ''}${name || 'YourUpload'}`, h)] : [];
    },

    sibnetExtractor: async (url, prefix) => {
      const html = await pageText(url, {});
      const path = firstMatch(html, [/player\.src\(\[\{\s*src\s*:\s*"([^"]+)"/]);
      if (!path) return [];
      const link = path.startsWith('http') ? path : 'https://video.sibnet.ru' + path;
      return [video(link, `${prefix || ''}Sibnet`, { Referer: url })];
    },

    voeExtractor: async (url, prefix) => {
      const html = await pageText(url, {});
      let hls = firstMatch(html, [/["']hls["']\s*:\s*["']([^"']+)["']/, /sources\[['"]hls['"]\]\s*=\s*['"]([^'"]+)['"]/]);
      if (hls && !hls.startsWith('http')) { try { hls = atob(hls); } catch (_) {} }
      return hls ? hlsRows(hls, { Referer: ORIGIN(url) + '/' }, `${prefix || ''}Voe`) : [];
    },

    okruExtractor: async (url) => {
      const html = await pageText(url, {});
      const m = /data-options="([^"]+)"/.exec(html);
      if (!m) return [];
      try {
        const options = JSON.parse(m[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&'));
        const meta = JSON.parse(options.flashvars.metadata);
        const names = { mobile: '144p', lowest: '240p', low: '360p', sd: '480p', hd: '720p', full: '1080p', quad: '1440p', ultra: '2160p' };
        const rows = (meta.videos || []).map((v) => video(v.url, `Okru - ${names[v.name] || v.name}`, {}));
        if (meta.hlsManifestUrl) rows.unshift(video(meta.hlsManifestUrl, 'Okru - Auto', {}));
        return rows.reverse();
      } catch (_) {
        return [];
      }
    },
  };

  // The rest of upstream's set: cloud drives that need an account (Quark,
  // UC) and hosts without a working scrape. Present, so a source that calls
  // one keeps its other mirrors instead of throwing.
  for (const name of [
    'quarkVideosExtractor', 'quarkFilesExtractor', 'ucVideosExtractor',
    'ucFilesExtractor', 'gogoCdnExtractor', 'streamlareExtractor',
    'myTvExtractor', 'sendVidExtractor', 'vidBomExtractor',
  ]) {
    extractors[name] = async () => [];
  }

  for (const [name, fn] of Object.entries(extractors)) {
    globalThis[name] = async (...args) => {
      try {
        return (await fn(...args)) || [];
      } catch (_) {
        return [];
      }
    };
  }

  // --- expose --------------------------------------------------------------

  globalThis.MProvider = MProvider;
  globalThis.Client = Client;
  globalThis.Document = MDocument;
  globalThis.Element = globalThis.Element || MElement;
  globalThis.SharedPreferences = SharedPreferences;
  globalThis.Response = MResponse;

  globalThis.unpackJs = unpackJs;
  globalThis.decryptAESCryptoJS = decryptAESCryptoJS;
  globalThis.encryptAESCryptoJS = encryptAESCryptoJS;
  globalThis.cryptoHandler = cryptoHandler;
  globalThis.deobfuscateJsPassword = (s) => unpackJs(s);

  globalThis.MBridge = {
    parsHtml: (html) => new MDocument(html),
    xpath: (html, expr) => evaluateXPath(new MDocument(html)._doc, expr),
    unpackJs,
    decryptAESCryptoJS,
    encryptAESCryptoJS,
    cryptoHandler,
    md5: (s) => bytesToHex(md5(enc.encode(String(s)))),
  };

  /**
   * Loads an extension's source and returns a live instance.
   *
   * The source is wrapped in an IIFE rather than eval'd at top level so two
   * extensions can define the same `DefaultExtension` symbol without colliding
   * — every Mangayomi extension uses that exact class name.
   */
  globalThis.__sozoLoadMangayomi = function (code, source) {
    globalThis.__sozoSource = source || {};
    const factory = new Function(
      'source',
      `${code}\n;return (typeof DefaultExtension !== 'undefined') ? new DefaultExtension(source) : null;`,
    );
    const instance = factory(globalThis.__sozoSource);
    if (!instance) throw new Error('Extension does not define DefaultExtension');
    if (!instance.source) instance.source = globalThis.__sozoSource;

    // Method-name drift across repos. Mangayomi itself has renamed some of
    // these, and third-party repos are written against whichever spelling was
    // current when the author wrote them. Aliasing here is far cheaper than
    // teaching every call site about both names — and a missing alias presents
    // as "Extension does not implement getLatestUpdates", i.e. a source that
    // silently has no Latest row.
    const aliases = [
      ['getLatestUpdates', 'getLatest'],
      ['getDetail', 'getMangaDetails'],
      ['getPageList', 'getPageUrls'],
      ['getVideoList', 'getVideos'],
    ];
    for (const [a, b] of aliases) {
      if (typeof instance[a] !== 'function' && typeof instance[b] === 'function') {
        instance[a] = instance[b].bind(instance);
      } else if (typeof instance[b] !== 'function' && typeof instance[a] === 'function') {
        instance[b] = instance[a].bind(instance);
      }
    }

    // Kept so switching back to a source already seen is a pointer assignment
    // instead of another new Function(code) compile. A cross-search touching
    // six sources used to recompile all six on every query.
    const registry = globalThis.__sozoProviders || (globalThis.__sozoProviders = {});
    if (source && source.id != null) registry[String(source.id)] = instance;

    globalThis.__sozoProvider = instance;
    return true;
  };

  /** Makes an already-loaded extension current. False when it is not loaded. */
  globalThis.__sozoActivateMangayomi = function (id) {
    const registry = globalThis.__sozoProviders || {};
    const instance = registry[String(id)];
    if (!instance) return false;
    globalThis.__sozoProvider = instance;
    globalThis.__sozoSource = instance.source || globalThis.__sozoSource;
    return true;
  };

  // One WebView round trip per chapter, even when headers depend on each URL.
  globalThis.__sozoImageHeaders = async function (urls) {
    const provider = globalThis.__sozoProvider;
    const result = [];
    for (const url of urls) {
      try {
        result.push(normaliseHeaders(await provider.getHeaders(url)));
      } catch (error) {
        if (!/not implemented|does not implement|is not a function/i.test(String(error))) throw error;
        result.push({});
      }
    }
    return result;
  };

  async function epubCall(method, name, url, headers, chapter) {
    const result = await window.flutter_inappwebview.callHandler('mangayomiEpub', {
      method, name, url, headers: normaliseHeaders(headers), chapter,
    });
    if (result && result.error) throw new Error(result.error);
    return result ? result.value : null;
  }
  globalThis.parseEpub = async (name, url, headers) => {
    const provider = globalThis.__sozoProvider;
    const book = await epubCall('book', name, url, headers);
    if (provider && book) provider.__sozoEpubTitles = book.chapters;
    return book;
  };
  globalThis.parseEpubChapter = (name, url, headers, chapter) => epubCall('chapter', name, url, headers, chapter);

  globalThis.__sozoMangayomiReady = true;
})();
