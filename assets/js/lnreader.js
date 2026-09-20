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
 *   @libs/fetch          fetchApi / fetchFile
 *   @libs/novelStatus    the status enum
 *   @libs/filterInputs   filter shapes, which Sozo does not surface yet
 *   @libs/defaultCover   the placeholder cover
 *   @libs/storage        per-plugin key/value
 *   cheerio              a jQuery-ish reader over the real DOM
 *   htmlparser2          what cheerio is built on; plugins only ever pass it on
 *   dayjs                release dates
 *
 * cheerio is the only hard one, and it is only hard if you try to port it. This
 * runs in a WebView with a real `DOMParser` and real `querySelectorAll`, so the
 * subset the plugins actually use is a wrapper over a NodeList.
 */
(function () {
  'use strict';

  /* ---- cheerio over the DOM ------------------------------------------- */

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
   * A plugin's own key/value store.
   *
   * In memory for now, and deliberately: the only things plugins keep here are
   * a login cookie or a chosen domain, and persisting a credential is a
   * decision with its own conversation attached. A plugin that needs one asks
   * again next session rather than Sozo storing it quietly.
   */
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
   * The plugin's HTTP.
   *
   * Routed through the same `fetch` the Mangayomi bridge installs, which is
   * what carries Sozo's user agent, its cookie jar and any Cloudflare clearance
   * the app has earned. A plugin reaching for the raw one would bypass all
   * three and be blocked where the rest of the app is not.
   */
  async function fetchApi(url, init) {
    return fetch(url, init || {});
  }
  async function fetchFile(url, init) {
    const res = await fetch(url, init || {});
    const buf = await res.arrayBuffer();
    let binary = '';
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }

  function makeRequire(pluginId) {
    const storage = makeStorage();
    const modules = {
      '@libs/fetch': { fetchApi, fetchFile },
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
      cheerio: { load, CheerioAPI: load },
      htmlparser2: { parseDocument: (html) => load(html) },
      dayjs: dayjs,
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

  function novelCard(plugin, n) {
    return {
      name: n.name || n.title || '',
      link: absolute(plugin.site, n.path || n.url || ''),
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
    plugin.site = site;

    const list = async (page, options) => {
      const novels = await plugin.popularNovels(page, {
        showLatestNovels: !!(options && options.latest),
        filters: plugin.filters || {},
      });
      return { list: (novels || []).map((n) => novelCard(plugin, n)), hasNextPage: true };
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
        return {
          list: (novels || []).map((n) => novelCard(plugin, n)),
          hasNextPage: true,
        };
      },

      getDetail: async (url) => {
        const novel = await plugin.parseNovel(pathOf(site, url));
        const chapters = (novel.chapters || []).map((c, i) => ({
          name: c.name || `Chapter ${i + 1}`,
          url: absolute(site, c.path || c.url || ''),
          dateUpload: c.releaseTime ? String(Date.parse(c.releaseTime) || '') : '',
          scanlator: '',
        }));
        return {
          name: novel.name || '',
          imageUrl: absolute(site, novel.cover || defaultCover),
          description: novel.summary || '',
          author: novel.author || '',
          artist: novel.artist || '',
          status: statusOf(novel.status),
          genre: splitGenres(novel.genres),
          link: absolute(site, novel.path || url),
          // Newest first, which is the order every Mangayomi source returns and
          // therefore the order the app's chapter list expects to reverse.
          chapters: chapters.reverse(),
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
      getHtmlContent: async (url) => {
        const html = await plugin.parseChapter(pathOf(site, url));
        return String(html == null ? '' : html);
      },

      getPageList: async () => [],
      getVideoList: async () => [],
      getFilterList: () => [],
    };
  }

  /** LNReader passes paths, not urls; the app stores urls. */
  function pathOf(site, url) {
    const u = String(url == null ? '' : url);
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
    makeRequire,
    pathOf,
    absolute,
    statusOf,
    splitGenres,
    dayjs,
  };
})();
