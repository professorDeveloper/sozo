// Sozo could read light novels and had almost nowhere to read them from.
//
// A novel source here is a Mangayomi source whose repo index declares
// `itemType: novel`, and those are a handful next to the manga ones — most
// installs have none, which is the whole reason CatalogueResolver widens the
// light-novel shelf to the comic readers and has to caveat every answer it gets
// back. LNReader's index is 279 novel sources.
//
// They are CommonJS bundles rather than Mangayomi classes, so the adaptation is
// one file: the modules they `require`, a cheerio built on the WebView's own
// DOM, and a translation from their method names to the ones the rest of the
// app already speaks.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { test } = require('node:test');
const assert = require('node:assert/strict');

const shim = fs.readFileSync(
  path.join(__dirname, '../../assets/js/lnreader.js'),
  'utf8',
);

/// A context with the pieces a WebView has and node does not.
function host({ html = '', fetchImpl } = {}) {
  const sandbox = {
    console: { warn: () => {}, error: () => {}, log: () => {} },
    URL,
    URLSearchParams,
    TextEncoder,
    TextDecoder,
    Symbol,
    btoa: (s) => Buffer.from(s, 'binary').toString('base64'),
    fetch: fetchImpl || (async () => { throw new Error('no network'); }),
    // Only the methods the shim's cheerio touches, over a tree the test builds
    // by hand — node has no DOM and the point here is the wrapper's contract,
    // not the parser's.
    DOMParser: class {
      parseFromString() {
        return html;
      }
    },
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(shim, sandbox);
  return sandbox;
}

/// The smallest thing that behaves like an element tree.
function el(tag, { text = '', attrs = {}, children = [] } = {}) {
  const node = {
    nodeType: 1,
    tagName: tag.toUpperCase(),
    textContent: text || children.map((c) => c.textContent).join(''),
    children,
    parentElement: null,
    getAttribute: (n) => (n in attrs ? attrs[n] : null),
    setAttribute: (n, v) => { attrs[n] = v; },
    matches: (sel) => sel === tag || sel === '*',
    querySelectorAll: (sel) => {
      const out = [];
      const walk = (n) => {
        for (const c of n.children) {
          if (c.matches(sel)) out.push(c);
          walk(c);
        }
      };
      walk(node);
      return out;
    },
    querySelector: (sel) => node.querySelectorAll(sel)[0] || null,
    classList: { contains: () => false, add: () => {}, remove: () => {} },
    innerHTML: '',
  };
  for (const c of children) c.parentElement = node;
  return node;
}

/* ---- the require shim ------------------------------------------------- */

test('every module the plugin corpus asks for is provided', () => {
  // This list is not guessed. It is every distinct `require()` across all 279
  // plugins in the published index, so a plugin that loads today cannot stop
  // loading because a module quietly went missing from the shim.
  const needed = [
    '@libs/fetch',
    '@libs/novelStatus',
    '@libs/filterInputs',
    '@libs/defaultCover',
    '@libs/storage',
    '@libs/isAbsoluteUrl',
    '@libs/aes',
    '@/types/constants',
    'cheerio',
    'htmlparser2',
    'dayjs',
    'urlencode',
    'qs',
  ];
  const require_ = host().__sozoLnReaderInternals.makeRequire('test');
  for (const name of needed) {
    const mod = require_(name);
    assert.ok(mod, `${name} is missing`);
    assert.ok(
      typeof mod === 'function' || Object.keys(mod).length > 0,
      `${name} resolves to an empty object, i.e. it is NOT provided`,
    );
  }
});

test('an unknown module is an empty object, not a crash', () => {
  // A bundle with no line numbers failing on "require is not defined" says
  // nothing. A plugin that only touches the module on a path we never take
  // keeps working, and one that really needed it fails with its own message.
  const sandbox = host();
  const plugin = sandbox.__sozoLoadLnReader(
    `const x = require('@libs/somethingNew');
     module.exports.default = { site: 'https://s.test/', parseChapter: async () => '<p>hi</p>' };`,
    { id: 'p' },
  );
  assert.equal(typeof plugin.getHtmlContent, 'function');
});

test('a bundle that is not a plugin is rejected by name', () => {
  const sandbox = host();
  assert.throws(
    () => sandbox.__sozoLoadLnReader('module.exports.default = {};', { id: 'p' }),
    /not an LNReader plugin/,
  );
});

/* ---- the translation -------------------------------------------------- */

const plugin = `
  const { fetchApi } = require('@libs/fetch');
  const { NovelStatus } = require('@libs/novelStatus');
  module.exports.default = {
    id: 'demo', name: 'Demo', site: 'https://novels.test/',
    popularNovels: async (page, opts) => [
      { name: opts.showLatestNovels ? 'Newest' : 'Popular', path: 'novel/one', cover: '/c.png' },
    ],
    searchNovels: async (q) => [{ name: 'Found ' + q, path: 'novel/two' }],
    parseNovel: async (p) => ({
      name: 'A Novel', path: p, cover: 'https://cdn.test/c.png',
      summary: 'words', author: 'Someone', status: NovelStatus.Completed,
      genres: 'Action, Drama',
      chapters: [
        { name: 'Chapter 1', path: 'novel/one/1' },
        { name: 'Chapter 2', path: 'novel/one/2' },
      ],
    }),
    parseChapter: async (p) => '<p>' + p + '</p>',
  };
`;

test('popular and latest are one call, told apart', async () => {
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  assert.equal((await p.getPopular(1)).list[0].name, 'Popular');
  assert.equal((await p.getLatestUpdates(1)).list[0].name, 'Newest');
});

test('a relative path comes back as a url the app can store', async () => {
  // LNReader passes paths and the rest of Sozo stores urls; every link and
  // cover crosses that boundary here.
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  const card = (await p.getPopular(1)).list[0];
  assert.equal(card.link, 'https://novels.test/novel/one');
  assert.equal(card.imageUrl, 'https://novels.test/c.png');
});

test('an absolute cover is left alone', async () => {
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  const detail = await p.getDetail('https://novels.test/novel/one');
  assert.equal(detail.imageUrl, 'https://cdn.test/c.png');
});

test('and the url is turned back into a path on the way in', async () => {
  // The plugin only understands its own paths, so a stored url has to be
  // unwound before it is handed back.
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  assert.equal(
    await p.getHtmlContent('https://novels.test/novel/one/1'),
    '<p>novel/one/1</p>',
  );
});

test('chapters arrive newest first, like every Mangayomi source', async () => {
  // The app's chapter list reverses what it is given; handing it the plugin's
  // own order would number every novel backwards.
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  const detail = await p.getDetail('https://novels.test/novel/one');
  assert.deepEqual([...detail.chapters].map((c) => c.name), ['Chapter 2', 'Chapter 1']);
});

test('genres split, status maps, description survives', async () => {
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  const detail = await p.getDetail('https://novels.test/novel/one');
  assert.deepEqual([...detail.genre], ['Action', 'Drama']);
  assert.equal(detail.status, 1);
  assert.equal(detail.description, 'words');
  assert.equal(detail.author, 'Someone');
});

test('prose comes back as prose, which is the whole point', async () => {
  // Sozo's reader already renders getHtmlContent as text — that is how a
  // Mangayomi novel source reads — so an LNReader plugin lands in the same
  // reader, with the same offline download and the same EPUB export.
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  assert.equal(typeof (await p.getHtmlContent('novel/one/1')), 'string');
  assert.deepEqual([...(await p.getPageList())], []);
});

test('the plugin fetches through the app, not around it', async () => {
  // fetchApi has to be the fetch the bridge installs: that is what carries
  // Sozo's user agent, its cookie jar and any Cloudflare clearance it has
  // earned. The raw one would be blocked where the rest of the app is not.
  let seen = null;
  const sandbox = host({
    fetchImpl: async (url) => {
      seen = url;
      return { text: async () => 'ok' };
    },
  });
  const p = sandbox.__sozoLoadLnReader(
    `const { fetchApi } = require('@libs/fetch');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async (path) => (await fetchApi('https://s.test/' + path)).text() };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('a/b'), 'ok');
  assert.equal(seen, 'https://s.test/a/b');
});

/* ---- cheerio over the DOM --------------------------------------------- */

test('a miss returns an empty set rather than throwing', () => {
  // The single most important thing to preserve: a plugin whose site changed
  // should come back with nothing, not take the page down.
  const sandbox = host({ html: el('html') });
  const $ = sandbox.__sozoLnReaderInternals.load('<html></html>');
  assert.equal($('a').length, 0);
  assert.equal($('a').attr('href'), undefined);
  assert.equal($('a').first().text(), '');
  assert.deepEqual([...$('a').map((i, n) => n).get()], []);
});

test('map returns a set whose get() is the array', () => {
  // Plugins overwhelmingly write `.map(...).get()`; a plain array would break
  // every one of them.
  const tree = el('html', {
    children: [el('a', { text: 'one' }), el('a', { text: 'two' })],
  });
  const sandbox = host({ html: tree });
  const $ = sandbox.__sozoLnReaderInternals.load('x');
  assert.deepEqual([...$('a').map((i, n) => n.textContent).get()], ['one', 'two']);
  assert.equal($('a').length, 2);
  assert.equal($('a')[0].textContent, 'one');
});

test('text joins, attr reads the first, missing attrs are undefined', () => {
  const tree = el('html', {
    children: [
      el('a', { text: 'one', attrs: { href: '/1' } }),
      el('a', { text: 'two', attrs: { href: '/2' } }),
    ],
  });
  const sandbox = host({ html: tree });
  const $ = sandbox.__sozoLnReaderInternals.load('x');
  assert.equal($('a').text(), 'onetwo');
  assert.equal($('a').attr('href'), '/1');
  assert.equal($('a').attr('title'), undefined);
});

/* ---- the pure helpers -------------------------------------------------- */

test('a path is unwound only when it really is under the site', () => {
  const { pathOf } = host().__sozoLnReaderInternals;
  assert.equal(pathOf('https://s.test/', 'https://s.test/a/b'), 'a/b');
  assert.equal(pathOf('https://s.test/', 'https://other.test/a'), 'https://other.test/a');
  assert.equal(pathOf('', 'a/b'), 'a/b');
  assert.equal(pathOf('https://s.test/', ''), '');
});

test('status maps to the numbers the app already uses', () => {
  const { statusOf } = host().__sozoLnReaderInternals;
  assert.equal(statusOf('Ongoing'), 0);
  assert.equal(statusOf('Completed'), 1);
  assert.equal(statusOf('On Hiatus'), 2);
  assert.equal(statusOf('Cancelled'), 3);
  assert.equal(statusOf('nonsense'), 5);
  assert.equal(statusOf(undefined), 5);
});

test('genres come as a list whichever way the plugin sends them', () => {
  const { splitGenres } = host().__sozoLnReaderInternals;
  assert.deepEqual([...splitGenres(['A', 'B'])], ['A', 'B']);
  assert.deepEqual([...splitGenres('A, B ,C')], ['A', 'B', 'C']);
  assert.deepEqual([...splitGenres('')], []);
  assert.deepEqual([...splitGenres(undefined)], []);
});
