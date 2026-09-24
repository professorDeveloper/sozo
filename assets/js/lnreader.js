/* eslint-disable */
/**
 * Runs an LNReader plugin as if it were a Mangayomi extension.
 *
 * Sozo could read light novels and had almost nowhere to read them from. A
 * novel source here is a Mangayomi source whose repo index declares
 * `itemType: novel`, and those are a handful next to the manga ones — which is
 * why CatalogueResolver has to widen the light-novel shelf to the comic readers
 * and caveat every answer it gets back. LNReader has 279 novel sources.
 *
 * The whole adaptation is this file, for one reason: everything downstream of
 * `runtime.call(id, 'getPopular')` — search, home, detail, chapters, the
 * reader, downloads, EPUB export, read state — is already written against the
 * Mangayomi method names and the novel shape. So an LNReader plugin does not
 * need a new pipeline; it needs a translation at the one point where the code
 * is loaded.
 *
 * The plugins are CommonJS bundles that `require()` a small set of modules, so
 * that is what is provided here:
 *
 *   @libs/fetch          fetchApi / fetchFile / fetchText / fetchProto
 *   @libs/novelStatus    the status enum
 *   @libs/filterInputs   filter shapes, which Sozo does not surface yet
 *   @libs/defaultCover   the placeholder cover
 *   @libs/storage        per-plugin key/value
 *   cheerio              a jQuery-ish reader over the real DOM
 *   htmlparser2          what cheerio is built on; plugins only ever pass it on
 *   dayjs                release dates
 *
 * cheerio, htmlparser2 and dayjs (and protobufjs, for fetchProto) are the real packages, bundled into
 * `lnreader_deps.js` (see tool/lnreader_deps/) and loaded before this file —
 * LNReader itself runs them unmodified. A hand-written stand-in over the
 * WebView's DOM came first and covered too little: `new htmlparser2.Parser`,
 * `.contents()`, `.attribs`, `:contains(...)` and the rest are used by about
 * 170 of the 280 plugins, and each missing one threw. The stand-in below is
 * now only the fallback for a page where the bundle did not load.
 */
(function () {
  'use strict';

  /** The real libraries, when `lnreader_deps.js` has run. */
  const deps = globalThis.__lnDeps || null;

  /* ---- fallback cheerio over the DOM ----------------------------------- */

  /**
   * Cheerio's contract is that every call returns a new wrapped set, never a
   * bare node, so chains like `$('a').first().attr('href')` keep working on an
   * empty match instead of throwing. That is the single most important thing to
   * preserve: a plugin whose site changed should return nothing, not crash.
   */
  function wrap(nodes, root) {
    const list = nodes ? Array.prototype.slice.call(nodes) : [];
    const self = {
      length: list.length,
      nodes: list,
      toArray: () => list.slice(),
      get: (i) => (i == null ? list.slice() : list[i < 0 ? list.length + i : i]),
      eq: (i) => wrap([list[i < 0 ? list.length + i : i]].filter(Boolean), root),
      first: () => wrap(list.slice(0, 1), root),
      last: () => wrap(list.slice(-1), root),

      find: (sel) => {
        const out = [];
        for (const n of list) {
          if (!n || !n.querySelectorAll) continue;
          for (const m of n.querySelectorAll(sel)) out.push(m);
        }
        return wrap(out, root);
      },
      children: (sel) => {
        const out = [];
        for (const n of list) {
          for (const c of n.children || []) {
            if (!sel || c.matches(sel)) out.push(c);
          }
        }
        return wrap(out, root);
      },
      parent: () => wrap(list.map((n) => n.parentElement).filter(Boolean), root),
      closest: (sel) =>
        wrap(list.map((n) => n.closest && n.closest(sel)).filter(Boolean), root),
      next: () => wrap(list.map((n) => n.nextElementSibling).filter(Boolean), root),
      prev: () =>
        wrap(list.map((n) => n.previousElementSibling).filter(Boolean), root),
      siblings: (sel) => {
        const out = [];
        for (const n of list) {
          for (const s of (n.parentElement || {}).children || []) {
            if (s !== n && (!sel || s.matches(sel))) out.push(s);
          }
        }
        return wrap(out, root);
      },

      filter: (test) =>
        wrap(
          list.filter((n, i) =>
            typeof test === 'function' ? test.call(n, i, n) : n.matches(test),
          ),
          root,
        ),
      not: (sel) => wrap(list.filter((n) => !n.matches(sel)), root),
      is: (sel) => list.some((n) => n.matches && n.matches(sel)),
      has: (sel) => wrap(list.filter((n) => n.querySelector(sel)), root),

      each: (fn) => {
        list.forEach((n, i) => fn.call(n, i, n));
        return self;
      },
      // Cheerio's map returns a wrapped set whose `.get()` is the array, and
      // plugins overwhelmingly write `.map(...).get()`. Returning a plain array
      // would break every one of them.
      map: (fn) => {
        const out = list.map((n, i) => fn.call(n, i, n));
        const mapped = wrap([], root);
        mapped.length = out.length;
        mapped.toArray = () => out.slice();
        mapped.get = (i) => (i == null ? out.slice() : out[i]);
        return mapped;
      },

      attr: (name, value) => {
        if (value === undefined) {
          if (typeof name === 'object') return self;
          const n = list[0];
          if (!n || !n.getAttribute) return undefined;
          const v = n.getAttribute(name);
          return v === null ? undefined : v;
        }
        for (const n of list) n.setAttribute(name, value);
        return self;
      },
      prop: (name) => (list[0] ? list[0][name] : undefined),
      data: (name) => {
        const n = list[0];
        if (!n || !n.dataset) return undefined;
        return name ? n.dataset[name] : n.dataset;
      },
      hasClass: (name) => list.some((n) => n.classList.contains(name)),
      addClass: (name) => {
        for (const n of list) n.classList.add(name);
        return self;
      },
      removeClass: (name) => {
        for (const n of list) n.classList.remove(name);
        return self;
      },

      text: (value) => {
        if (value === undefined) return list.map((n) => n.textContent).join('');
        for (const n of list) n.textContent = value;
        return self;
      },
      html: (value) => {
        if (value === undefined) return list[0] ? list[0].innerHTML : null;
        for (const n of list) n.innerHTML = value;
        return self;
      },
      val: () => (list[0] ? list[0].value : undefined),

      remove: () => {
        for (const n of list) if (n.parentNode) n.parentNode.removeChild(n);
        return self;
      },
      empty: () => {
        for (const n of list) n.innerHTML = '';
        return self;
      },
    };
    self[Symbol.iterator] = function* () {
      for (const n of list) yield n;
    };
    // Plugins index the set directly (`$('a')[0]`) about as often as they call
    // .get(0).
    list.forEach((n, i) => {
      self[i] = n;
    });
    return self;
  }

  function load(html) {
    const doc = new DOMParser().parseFromString(
      String(html == null ? '' : html),
      'text/html',
    );
    const $ = function (selector, context) {
      if (!selector) return wrap([], doc);
      // A node, or an already-wrapped set, passed back in.
      if (selector.nodeType) return wrap([selector], doc);
      if (selector.nodes) return wrap(selector.nodes, doc);
      const scope = context
        ? context.nodes
          ? context.nodes[0]
          : context
        : doc;
      if (!scope || !scope.querySelectorAll) return wrap([], doc);
      return wrap(scope.querySelectorAll(selector), doc);
    };
    $.root = () => wrap([doc.documentElement], doc);
    $.html = (sel) =>
      sel ? $(sel).html() : doc.documentElement.outerHTML;
    $.text = (sel) => (sel ? $(sel).text() : doc.body.textContent);
    $.load = load;
    return $;
  }

  /* ---- the modules a plugin asks for ---------------------------------- */

  const NovelStatus = {
    Unknown: 'Unknown',
    Ongoing: 'Ongoing',
    Completed: 'Completed',
    Licensed: 'Licensed',
    PublishingFinished: 'Publishing Finished',
    Cancelled: 'Cancelled',
    OnHiatus: 'On Hiatus',
  };

  const FilterTypes = {
    TextInput: 'Text',
    Picker: 'Picker',
    CheckboxGroup: 'Checkbox',
    Switch: 'Switch',
    ExcludableCheckboxGroup: 'XCheckbox',
  };

  /**
   * A plugin's own key/value store, kept with the source's preferences.
   *
   * Plugins read their settings from it (`pluginSettings` keys) and keep a
   * chosen domain or a cursor there. It lived in memory, so every setting
   * reset each session and could not be changed from the app at all. It is
   * the same per-source store Mangayomi sources use — seeded before each call
   * and saved after one that changed it — so the source settings screen edits
   * the same values the plugin reads. An `expires` is honoured on read.
   */
  function makePersistentStorage() {
    const store = () => globalThis.__sozoPrefs || (globalThis.__sozoPrefs = {});
    const dirty = () => {
      globalThis.__sozoPrefsDirty = true;
    };
    const read = (k) => {
      const v = store()[k];
      if (v && typeof v === 'object' && v.__sozoExpires !== undefined) {
        if (Date.now() > v.__sozoExpires) return undefined;
        return v.value;
      }
      return v === '' ? undefined : v;
    };
    return {
      get: (k) => read(k),
      set: (k, v, expires) => {
        const at = expires instanceof Date ? expires.getTime() : Number(expires);
        store()[k] = expires && at ? { __sozoExpires: at, value: v } : v;
        dirty();
      },
      delete: (k) => {
        delete store()[k];
        dirty();
      },
      clearAll: () => {
        globalThis.__sozoPrefs = {};
        dirty();
      },
      getAllKeys: () => Object.keys(store()),
    };
  }

  /** Session-only: what a plugin keeps for this run and no longer. */
  function makeStorage() {
    const data = new Map();
    return {
      get: (k) => data.get(k),
      set: (k, v) => {
        data.set(k, v);
      },
      delete: (k) => data.delete(k),
      clearAll: () => data.clear(),
      getAllKeys: () => Array.from(data.keys()),
    };
  }

  /** Just enough dayjs for a release date. */
  function dayjs(input) {
    const date = input === undefined ? new Date() : new Date(input);
    const api = {
      toDate: () => date,
      valueOf: () => date.getTime(),
      isValid: () => !isNaN(date.getTime()),
      toISOString: () => (isNaN(date.getTime()) ? '' : date.toISOString()),
      format: () => (isNaN(date.getTime()) ? '' : date.toISOString()),
      subtract: (n, unit) => dayjs(shift(date, -n, unit)),
      add: (n, unit) => dayjs(shift(date, n, unit)),
    };
    return api;
  }
  function shift(date, n, unit) {
    const ms = {
      second: 1e3,
      seconds: 1e3,
      minute: 6e4,
      minutes: 6e4,
      hour: 36e5,
      hours: 36e5,
      day: 864e5,
      days: 864e5,
      week: 6048e5,
      weeks: 6048e5,
      month: 2592e6,
      months: 2592e6,
      year: 31536e6,
      years: 31536e6,
    }[unit] || 0;
    return new Date(date.getTime() + n * ms);
  }

  const defaultCover =
    'https://placehold.co/400x600/1a1a1a/eeeeee/png?text=No%20Cover';

  /**
   * The plugin's HTTP, through the app's `dartFetch`.
   *
   * Not the WebView's `fetch`: this page's origin is https://sozo.local, so
   * every plugin request was cross-origin, and 196 of the 208 LNReader sites
   * that answer send no CORS header — the browser threw the responses away.
   * `dartFetch` goes out from Dart instead, with the app's user agent, cookie
   * jar and Cloudflare clearance, and no CORS. The raw `fetch` is only used
   * where there is no bridge (the tests' plain node).
   */
  function headerObject(h) {
    const out = {};
    if (!h) return out;
    if (Array.isArray(h)) {
      for (const pair of h) if (pair && pair.length >= 2) out[String(pair[0])] = String(pair[1]);
      return out;
    }
    if (typeof h.forEach === 'function') {
      h.forEach((v, k) => {
        out[String(k)] = String(v);
      });
      return out;
    }
    for (const k of Object.keys(h)) if (h[k] != null) out[k] = String(h[k]);
    return out;
  }

  function hasHeader(headers, name) {
    return Object.keys(headers).some((k) => k.toLowerCase() === name);
  }

  const FORM = 'application/x-www-form-urlencoded;charset=UTF-8';

  function bodyOf(body, headers) {
    if (body == null) return undefined;
    if (typeof body === 'string') return body;
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      if (!hasHeader(headers, 'content-type')) headers['Content-Type'] = FORM;
      return body.toString();
    }
    // A FormData goes as the multipart form it is. Sent urlencoded — which
    // is what this did — servers expecting multipart (WordPress's
    // admin-ajax among them) answered with an empty body, and the plugin's
    // JSON.parse failed on it. Text fields only: Dart's side takes a string.
    if (typeof FormData !== 'undefined' && body instanceof FormData) {
      const boundary = '----sozo' + Math.random().toString(16).slice(2) + Date.now().toString(16);
      let out = '';
      body.forEach((v, k) => {
        out += '--' + boundary + '\r\n' +
          'Content-Disposition: form-data; name="' + String(k).replace(/"/g, '%22') + '"\r\n\r\n' +
          String(v) + '\r\n';
      });
      out += '--' + boundary + '--\r\n';
      for (const k of Object.keys(headers)) {
        if (k.toLowerCase() === 'content-type') delete headers[k];
      }
      headers['Content-Type'] = 'multipart/form-data; boundary=' + boundary;
      return out;
    }
    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
      return new TextDecoder().decode(body);
    }
    return JSON.stringify(body);
  }

  /** What `fetch` resolves to, for a body Dart has already read as text. */
  function makeResponse(text, status, headers, url) {
    let h;
    try {
      h = new Headers(headers || {});
    } catch (_) {
      const lower = {};
      for (const k of Object.keys(headers || {})) lower[k.toLowerCase()] = headers[k];
      h = { get: (k) => lower[String(k).toLowerCase()] ?? null, has: (k) => String(k).toLowerCase() in lower };
    }
    return {
      ok: status >= 200 && status < 300,
      status,
      statusText: '',
      url,
      redirected: false,
      headers: h,
      text: async () => text,
      json: async () => JSON.parse(text),
      arrayBuffer: async () => new TextEncoder().encode(text).buffer,
      clone: () => makeResponse(text, status, headers, url),
    };
  }

  function bridge() {
    return typeof window !== 'undefined' && window && typeof window.dartFetch === 'function'
      ? window
      : null;
  }

  async function fetchApi(url, init) {
    const options = init || {};
    const host = bridge();
    if (!host) return fetch(url, options);
    const headers = headerObject(options.headers);
    const body = bodyOf(options.body, headers);
    const raw = await host.dartFetch({
      url: String(url),
      method: String(options.method || 'GET').toUpperCase(),
      headers,
      body,
    });
    const data = raw ? raw.data : null;
    const text = data == null ? '' : typeof data === 'string' ? data : JSON.stringify(data);
    const status = raw && raw.status ? Number(raw.status) : 0;
    return makeResponse(text, status, (raw && raw.headers) || {}, (raw && raw.url) || String(url));
  }

  /** LNReader's fetchText: the body, or '' for a failed request. */
  async function fetchText(url, init) {
    const res = await fetchApi(url, init);
    return res.ok ? res.text() : '';
  }

  /** Base64 of the bytes — covers and images a plugin inlines. */
  async function fetchFile(url, init) {
    const host = bridge();
    if (host && host.flutter_inappwebview) {
      const res = await host.flutter_inappwebview.callHandler('dartFetchBytes', {
        url: String(url),
        headers: headerObject((init || {}).headers),
      });
      return (res && res.base64) || '';
    }
    const res = await fetch(url, init || {});
    const buf = await res.arrayBuffer();
    let binary = '';
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }

  function bytesToBase64(bytes) {
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary);
  }

  function base64ToBytes(b64) {
    const binary = atob(String(b64 || ''));
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  }

  /**
   * A POST of raw bytes that answers with raw bytes. `dartFetch` carries
   * text, which mangles both, so they cross as base64.
   */
  async function postBytes(url, bytes, init) {
    const headers = headerObject((init || {}).headers);
    const host = bridge();
    if (!host) {
      const res = await fetch(url, { method: 'POST', headers, body: bytes });
      return new Uint8Array(await res.arrayBuffer());
    }
    const raw = await host.dartFetch({
      url: String(url),
      method: 'POST',
      headers,
      bodyBase64: bytesToBase64(bytes),
      responseType: 'base64',
    });
    return base64ToBytes(raw && raw.data);
  }

  /** LNReader's fetchProto: one gRPC-web call, framed and decoded. */
  async function fetchProto(protoInit, url, init) {
    const protobuf = deps && deps.protobuf;
    if (!protobuf) {
      throw new Error('this source speaks protobuf, which Sozo does not carry');
    }
    const root = protobuf.parse(protoInit.proto).root;
    const Request = root.lookupType(protoInit.requestType);
    const message = Request.encode(Request.fromObject(protoInit.requestData)).finish();
    // A frame is a flag byte and a big-endian length, then the message.
    const frame = new Uint8Array(5 + message.length);
    new DataView(frame.buffer).setUint32(1, message.length);
    frame.set(message, 5);
    const payload = await postBytes(url, frame, init);
    if (payload.length < 5) throw new Error('empty protobuf response from ' + url);
    const length = new DataView(payload.buffer, payload.byteOffset).getUint32(1);
    return root.lookupType(protoInit.responseType).decode(payload.subarray(5, 5 + length));
  }

  function makeRequire(pluginId) {
    const storage = makePersistentStorage();
    const modules = {
      '@libs/fetch': { fetchApi, fetchFile, fetchText, fetchProto },
      '@libs/novelStatus': { NovelStatus },
      '@libs/filterInputs': { FilterTypes, FilterInputs: FilterTypes },
      '@libs/defaultCover': { defaultCover },
      '@libs/storage': {
        storage,
        localStorage: storage,
        sessionStorage: makeStorage(),
      },
      '@libs/isAbsoluteUrl': {
        isUrlAbsolute: (u) => /^https?:\/\//i.test(String(u || '')),
      },
      // An alias the bundler leaves in place for a couple of plugins; it is
      // their own source tree's path for the same constant.
      '@/types/constants': { defaultCover },
      // One plugin of the 279 decrypts its chapters with AES-GCM, through
      // @noble/ciphers, whose `decrypt` is SYNCHRONOUS. WebCrypto is not, and
      // a hand-written block cipher is exactly the kind of code that is subtly
      // wrong in a way no test here would catch. So it says so: that plugin
      // fails with a sentence naming the reason, which is a great deal better
      // than a stub quietly returning garbage, or "require is not defined"
      // out of a minified bundle with no line numbers.
      '@libs/aes': {
        gcm: () => {
          throw new Error(
            'this source needs synchronous AES-GCM, which Sozo does not carry',
          );
        },
      },
      cheerio: deps ? deps.cheerio : { load, CheerioAPI: load },
      htmlparser2: deps ? deps.htmlparser2 : { parseDocument: (html) => load(html) },
      dayjs: deps ? deps.dayjs : dayjs,
      urlencode: {
        encode: encodeURIComponent,
        decode: decodeURIComponent,
        stringify: (o) => new URLSearchParams(o).toString(),
      },
      qs: {
        stringify: (o) => new URLSearchParams(o).toString(),
        parse: (s) => Object.fromEntries(new URLSearchParams(s)),
      },
    };
    return function require(name) {
      const found = modules[name];
      if (found) return found;
      // A module nobody anticipated. An empty object lets a plugin that only
      // touches it on a path we never take keep working, and the plugin fails
      // with its own message if it really needed it — which is far more useful
      // than "require is not defined" from a bundle with no line numbers.
      console.warn('[lnreader] unknown module: ' + name + ' for ' + pluginId);
      return {};
    };
  }

  /* ---- the adapter ---------------------------------------------------- */

  /** Absolute url for a path a plugin handed back. */
  function absolute(site, path) {
    const p = String(path == null ? '' : path);
    if (!p) return '';
    if (/^https?:\/\//i.test(p)) return p;
    try {
      return new URL(p, site).href;
    } catch (_) {
      return p;
    }
  }

  /**
   * The app's link for a path a plugin returned, from which [pathOf] gives
   * back exactly that path.
   *
   * A plugin is called again with the path it handed out, character for
   * character — "/novels/x", "novels/x" and "x" are different requests to
   * it. Most paths survive the round trip through a url; the ones that do
   * not (a leading slash, a full url, a path under a sub-folder of the site)
   * carry the original in the fragment, which never reaches the server.
   */
  function linkFor(site, path) {
    const p = String(path == null ? '' : path);
    const abs = absolute(site, p);
    if (!abs || pathOf(site, abs) === p) return abs;
    return abs + PATH_MARK + encodeURIComponent(p);
  }

  const PATH_MARK = '#sozo-path=';

  const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', '#39': "'" };

  /** A name some plugins hand back still HTML-escaped ("&#x633;…"). */
  function decodeEntities(text) {
    return String(text == null ? '' : text).replace(/&(#x[0-9a-f]+|#\d+|[a-z]+|#39);/gi, (m, e) => {
      if (e[0] === '#') {
        const code = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return Number.isFinite(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : m;
      }
      return ENTITIES[e.toLowerCase()] ?? m;
    });
  }

  function novelCard(plugin, n) {
    return {
      name: decodeEntities(n.name || n.title || ''),
      link: linkFor(plugin.site, n.path || n.url || ''),
      imageUrl: absolute(plugin.site, n.cover || defaultCover),
    };
  }

  /**
   * The Mangayomi-shaped object the rest of the app talks to.
   *
   * Every method below is the Mangayomi name; every call inside it is the
   * LNReader one. That is the whole translation.
   */
  function adapt(plugin, source) {
    const site = plugin.site || source.baseUrl || '';
    // Some plugins declare `site` as a getter; assigning it threw on load.
    if (!plugin.site) {
      try {
        plugin.site = site;
      } catch (_) {}
    }

    const list = async (page, options) => {
      const novels = await plugin.popularNovels(page, {
        showLatestNovels: !!(options && options.latest),
        filters: plugin.filters || {},
      });
      const found = (novels || []).map((n) => novelCard(plugin, n));
      // An empty page is the end. Always-true made "load more" ask forever.
      return { list: found, hasNextPage: found.length > 0 };
    };

    return {
      source,
      id: source.id,
      name: plugin.name || source.name,
      baseUrl: site,
      lang: plugin.lang || source.lang,

      getPopular: (page) => list(page || 1, { latest: false }),
      getLatestUpdates: (page) => list(page || 1, { latest: true }),

      search: async (query, page) => {
        const novels = await plugin.searchNovels(query, page || 1);
        const found = (novels || []).map((n) => novelCard(plugin, n));
        return { list: found, hasNextPage: found.length > 0 };
      },

      getDetail: async (url) => {
        const path = pathOf(site, url);
        const novel = await plugin.parseNovel(path);
        const chapters = (novel.chapters || []).slice();
        // Paged chapter lists: parseNovel gives the page count (and often
        // no chapters), parsePage gives each page. LNReader asks page by page
        // as the list scrolls; the app takes the list whole, so the pages are
        // fetched here — a few at a time, within the call's time limit.
        const pages = Number(novel.totalPages) || 0;
        if (typeof plugin.parsePage === 'function' && (pages > 1 || !chapters.length)) {
          const first = chapters.length ? 2 : 1;
          const last = Math.min(Math.max(pages, 1), first + MAX_CHAPTER_PAGES - 1);
          const deadline = Date.now() + CHAPTER_PAGES_BUDGET_MS;
          for (let p = first; p <= last && Date.now() < deadline; p += 4) {
            const batch = [];
            for (let q = p; q < p + 4 && q <= last; q++) {
              batch.push(plugin.parsePage(path, String(q)).catch(() => null));
            }
            for (const result of await Promise.all(batch)) {
              if (result && result.chapters) chapters.push(...result.chapters);
            }
          }
        }
        const mapped = chapters.map((c, i) => ({
          name: decodeEntities(c.name || `Chapter ${i + 1}`),
          url: linkFor(site, c.path || c.url || ''),
          dateUpload: c.releaseTime ? String(Date.parse(c.releaseTime) || '') : '',
          scanlator: '',
        }));
        return {
          name: decodeEntities(novel.name || ''),
          imageUrl: absolute(site, novel.cover || defaultCover),
          description: novel.summary || '',
          author: novel.author || '',
          artist: novel.artist || '',
          status: statusOf(novel.status),
          genre: splitGenres(novel.genres),
          link: novel.path ? linkFor(site, novel.path) : url,
          // Newest first, which is the order every Mangayomi source returns and
          // therefore the order the app's chapter list expects to reverse.
          chapters: mapped.reverse(),
        };
      },

      /**
       * A chapter of prose.
       *
       * This is the method that makes the whole thing work: Sozo's reader
       * already renders `getHtmlContent` as prose — that is how a Mangayomi
       * novel source reads — so an LNReader plugin lands in exactly the same
       * reader, with the same offline download and the same EPUB export.
       */
      //
      // Called as (sourceName, url), the Mangayomi signature. Taking one
      // argument read the source's name as the chapter address, so every
      // chapter of every LNReader source asked for the wrong page.
      getHtmlContent: async (name, url) => {
        const target = url === undefined ? name : url;
        const html = await plugin.parseChapter(pathOf(site, target));
        return String(html == null ? '' : html);
      },

      // Covers on sites that check the Referer.
      getHeaders: () => {
        const init = plugin.imageRequestInit;
        const own = init && init.headers ? headerObject(init.headers) : {};
        return hasHeader(own, 'referer') ? own : Object.assign({ Referer: site }, own);
      },

      getPageList: async () => [],
      getVideoList: async () => [],
      getFilterList: () => [],
      getSourcePreferences: () => preferencesOf(plugin),
    };
  }

  /**
   * A plugin's `pluginSettings`, in the shape Mangayomi sources describe
   * their preferences in, so one settings screen edits both. The values
   * live in the same per-source store the plugin's `storage` reads.
   */
  function preferencesOf(plugin) {
    const settings = plugin.pluginSettings;
    if (!settings || typeof settings !== 'object') return [];
    const out = [];
    for (const key of Object.keys(settings)) {
      const s = settings[key] || {};
      const title = String(s.label || key);
      const type = String(s.type || '').toLowerCase();
      const options = Array.isArray(s.options) ? s.options : [];
      if (type === 'switch') {
        out.push({ key, switchPreferenceCompat: { title, summary: '', value: !!s.value } });
      } else if ((type === 'select' || type === 'picker') && options.length) {
        const values = options.map((o) => String(o.value));
        out.push({
          key,
          listPreference: {
            title,
            summary: '',
            valueIndex: Math.max(0, values.indexOf(String(s.value))),
            entries: options.map((o) => String(o.label)),
            entryValues: values,
          },
        });
      } else if (type.includes('checkbox') && options.length) {
        out.push({
          key,
          multiSelectListPreference: {
            title,
            summary: '',
            entries: options.map((o) => String(o.label)),
            entryValues: options.map((o) => String(o.value)),
            values: Array.isArray(s.value) ? s.value.map(String) : [],
          },
        });
      } else {
        out.push({
          key,
          editTextPreference: {
            title,
            summary: '',
            value: s.value == null ? '' : String(s.value),
            dialogTitle: title,
            dialogMessage: '',
          },
        });
      }
    }
    return out;
  }

  const MAX_CHAPTER_PAGES = 60;
  const CHAPTER_PAGES_BUDGET_MS = 35000;

  /** LNReader passes paths, not urls; the app stores urls. */
  function pathOf(site, url) {
    const u = String(url == null ? '' : url);
    const mark = u.indexOf(PATH_MARK);
    if (mark >= 0) return decodeURIComponent(u.slice(mark + PATH_MARK.length));
    if (!site || !u.startsWith(site)) return u;
    const rest = u.slice(site.replace(/\/+$/, '').length);
    return rest.startsWith('/') ? rest.slice(1) : rest;
  }

  function statusOf(status) {
    switch (String(status || '')) {
      case NovelStatus.Ongoing:
        return 0;
      case NovelStatus.Completed:
      case NovelStatus.PublishingFinished:
        return 1;
      case NovelStatus.OnHiatus:
        return 2;
      case NovelStatus.Cancelled:
        return 3;
      default:
        return 5;
    }
  }

  function splitGenres(genres) {
    if (!genres) return [];
    if (Array.isArray(genres)) return genres;
    return String(genres)
      .split(',')
      .map((g) => g.trim())
      .filter(Boolean);
  }

  /* ---- entry point ---------------------------------------------------- */

  globalThis.__sozoLoadLnReader = function (code, source) {
    const module = { exports: {} };
    const factory = new Function(
      'module',
      'exports',
      'require',
      'globalThis',
      `${code}\n;return module.exports;`,
    );
    const exported = factory(
      module,
      module.exports,
      makeRequire(source && source.id),
      globalThis,
    );
    const plugin =
      (exported && (exported.default || exported)) || module.exports.default;
    if (!plugin || typeof plugin.parseChapter !== 'function') {
      throw new Error('not an LNReader plugin');
    }
    return adapt(plugin, source || {});
  };

  // Exposed so the shim's own pieces can be exercised without a plugin.
  globalThis.__sozoLnReaderInternals = {
    load,
    fetchApi,
    deps,
    makeRequire,
    pathOf,
    preferencesOf,
    linkFor,
    decodeEntities,
    absolute,
    statusOf,
    splitGenres,
    dayjs,
  };
})();
