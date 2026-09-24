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

test('the plugin fetches through dartFetch, not the page', async () => {
  // The page's origin is https://sozo.local, so the WebView's own fetch made
  // every plugin request cross-origin — and almost no novel site sends a CORS
  // header, so the browser threw the answers away. dartFetch goes out from
  // Dart, with the app's cookie jar and Cloudflare clearance.
  const sandbox = host({
    fetchImpl: async () => {
      throw new Error('the raw fetch must not be used');
    },
  });
  let seen = null;
  sandbox.window = {
    dartFetch: async (req) => {
      seen = req;
      return { status: 200, data: 'ok', headers: { 'content-type': 'text/html' } };
    },
  };
  const p = sandbox.__sozoLoadLnReader(
    `const { fetchApi } = require('@libs/fetch');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async (path) => {
         const body = new URLSearchParams({ action: 'load', id: '7' });
         const res = await fetchApi('https://s.test/' + path, {
           method: 'post', headers: { Referer: 'https://s.test/' }, body });
         return res.ok && res.status === 200 ? res.text() : 'failed';
       } };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('Source', 'https://s.test/a/b'), 'ok');
  assert.equal(seen.url, 'https://s.test/a/b');
  assert.equal(seen.method, 'POST');
  assert.equal(seen.body, 'action=load&id=7');
  assert.equal(seen.headers.Referer, 'https://s.test/');
  assert.match(seen.headers['Content-Type'], /x-www-form-urlencoded/);
});

test('a JSON answer reaches the plugin as text it can parse', async () => {
  // dartFetch decodes application/json; plugins call res.json() themselves.
  const sandbox = host();
  sandbox.window = {
    dartFetch: async () => ({ status: 200, data: { n: 1 }, headers: {} }),
  };
  const p = sandbox.__sozoLoadLnReader(
    `const { fetchApi } = require('@libs/fetch');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async () => String((await (await fetchApi('https://s.test/x')).json()).n) };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('Source', 'x'), '1');
});

test('the chapter address is the second argument, as the app calls it', async () => {
  // The bridge calls getHtmlContent(sourceName, url). Taking one argument read
  // the source's name as the address, so every chapter asked for the wrong page.
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(plugin, { id: 'demo' });
  assert.equal(
    await p.getHtmlContent('Demo Novels', 'https://novels.test/novel/one/1'),
    '<p>novel/one/1</p>',
  );
});

test('a path the plugin handed out comes back to it unchanged', () => {
  const { linkFor, pathOf } = host().__sozoLnReaderInternals;
  const site = 'https://s.test/';
  for (const path of ['novel/x', '/novels/x', 'https://s.test/n/x', 'x?id=3']) {
    assert.equal(pathOf(site, linkFor(site, path)), path);
  }
  // A plain one stays a plain url.
  assert.equal(linkFor(site, 'novel/x'), 'https://s.test/novel/x');
});

test('escaped names are decoded', () => {
  const { decodeEntities } = host().__sozoLnReaderInternals;
  assert.equal(decodeEntities('48 &#x633;&#x627; &amp; &#8217;s'), '48 سا & ’s');
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

/* ---- the real libraries ------------------------------------------------ */

const deps = fs.readFileSync(
  path.join(__dirname, '../../assets/js/lnreader_deps.js'),
  'utf8',
);

/// A context with the bundled cheerio, htmlparser2 and dayjs loaded first,
/// the way the runtime loads them.
function realHost() {
  const sandbox = {
    console: { warn: () => {}, error: () => {}, log: () => {} },
    URL,
    URLSearchParams,
    TextEncoder,
    TextDecoder,
    Headers,
    atob,
    btoa,
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(deps, sandbox);
  vm.runInContext(shim, sandbox);
  return sandbox;
}

test('plugins get the real cheerio: :contains, contents, attribs', async () => {
  // About 170 of the 280 plugins use something the hand-written stand-in
  // lacked, and each one threw.
  const sandbox = realHost();
  const p = sandbox.__sozoLoadLnReader(
    `const { load } = require('cheerio');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async () => {
         const $ = load('<div class="i"><h5>Genre</h5><a class="premium-block" href="/x">A</a> text</div>');
         const genre = $('h5:contains("Genre")').text();
         const cls = $('a').get(0).attribs.class;
         const nodes = $('.i').contents().length;
         return [genre, cls, nodes].join('|');
       } };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('S', 'x'), 'Genre|premium-block|3');
});

test('plugins get the real htmlparser2 Parser', async () => {
  const sandbox = realHost();
  const p = sandbox.__sozoLoadLnReader(
    `const { Parser } = require('htmlparser2');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async () => {
         const seen = [];
         const parser = new Parser({ onopentag: (name) => seen.push(name) });
         parser.write('<p><b>x</b></p>'); parser.end();
         return seen.join(',');
       } };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('S', 'x'), 'p,b');
});

test('a paged chapter list is fetched whole', async () => {
  const sandbox = realHost();
  const p = sandbox.__sozoLoadLnReader(
    `module.exports.default = { site: 'https://s.test/',
       parseNovel: async (path) => ({ path, name: 'N', totalPages: 3, chapters: [] }),
       parsePage: async (path, page) => ({ chapters: [
         { name: 'c' + page + 'a', path: path + '/' + page + 'a' },
         { name: 'c' + page + 'b', path: path + '/' + page + 'b' }] }),
       parseChapter: async () => '' };`,
    { id: 'p' },
  );
  const detail = await p.getDetail('https://s.test/n');
  assert.deepEqual(
    [...detail.chapters].map((c) => c.name),
    ['c3b', 'c3a', 'c2b', 'c2a', 'c1b', 'c1a'],
  );
});

test('plugin settings become source preferences, and storage keeps them', async () => {
  // They lived in memory and could not be changed from the app; now they are
  // the source's preferences, read by the plugin from its storage.
  const sandbox = host();
  const p = sandbox.__sozoLoadLnReader(
    `const { storage } = require('@libs/storage');
     module.exports.default = { site: 'https://s.test/',
       pluginSettings: {
         hideLocked: { value: false, label: 'Hide locked', type: 'Switch' },
         customJs: { value: '', label: 'Custom JS', type: 'Text' },
         order: { value: 'asc', label: 'Order', type: 'Select',
           options: [{ label: 'Oldest', value: 'asc' }, { label: 'Newest', value: 'desc' }] },
       },
       parseChapter: async () => String(storage.get('hideLocked')) + '|' + String(storage.get('missing')) };`,
    { id: 'p' },
  );
  const prefs = p.getSourcePreferences();
  assert.equal(prefs[0].key, 'hideLocked');
  assert.equal(prefs[0].switchPreferenceCompat.value, false);
  assert.equal(prefs[1].editTextPreference.title, 'Custom JS');
  assert.deepEqual([...prefs[2].listPreference.entryValues], ['asc', 'desc']);

  // The app seeds the saved values before a call; the plugin reads them.
  sandbox.__sozoPrefs = { hideLocked: true };
  assert.equal(await p.getHtmlContent('S', 'x'), 'true|undefined');
});

test('what a plugin stores is marked for saving', () => {
  const sandbox = host();
  const req = sandbox.__sozoLnReaderInternals.makeRequire('p');
  const { storage } = req('@libs/storage');
  sandbox.__sozoPrefsDirty = false;
  storage.set('cursor', 5);
  assert.equal(sandbox.__sozoPrefs.cursor, 5);
  assert.equal(sandbox.__sozoPrefsDirty, true);
  storage.set('token', 'x', Date.now() - 1000);
  assert.equal(storage.get('token'), undefined);
});

test('a FormData body goes as multipart, the form it is', async () => {
  // Sent urlencoded, WordPress's admin-ajax and others answered with an empty
  // body and the plugin's JSON.parse failed on it.
  const sandbox = host();
  sandbox.FormData = FormData;
  let seen = null;
  sandbox.window = {
    dartFetch: async (req) => {
      seen = req;
      return { status: 200, data: '[]', headers: {} };
    },
  };
  const p = sandbox.__sozoLoadLnReader(
    `const { fetchApi } = require('@libs/fetch');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async () => {
         const body = new FormData();
         body.append('action', 'load_novels');
         body.append('page', '2');
         return (await fetchApi('https://s.test/wp-admin/admin-ajax.php', {
           method: 'POST', body, headers: { 'Content-Type': 'text/plain' } })).text();
       } };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('S', 'x'), '[]');
  const type = seen.headers['Content-Type'];
  assert.match(type, /^multipart\/form-data; boundary=/);
  const boundary = type.split('boundary=')[1];
  assert.match(seen.body, new RegExp('name="action"\\r\\n\\r\\nload_novels'));
  assert.match(seen.body, new RegExp('name="page"\\r\\n\\r\\n2'));
  assert.ok(seen.body.trimEnd().endsWith('--' + boundary + '--'));
  // The plugin's own Content-Type could not describe this body; it is replaced.
  assert.equal(Object.keys(seen.headers).filter((k) => k.toLowerCase() === 'content-type').length, 1);
});

test('fetchProto makes a gRPC-web call through the bridge, as bytes', async () => {
  // Wuxiaworld's plugin speaks nothing else; it failed on every call.
  const sandbox = realHost();
  const proto = `syntax = "proto3";
    message GetNovelRequest { string slug = 1; }
    message GetNovelResponse { string name = 1; int32 id = 2; }`;
  const { protobuf } = sandbox.__sozoLnReaderInternals.deps;
  const root = protobuf.parse(proto).root;
  let seen = null;
  sandbox.window = {
    dartFetch: async (req) => {
      seen = req;
      const reply = root.lookupType('GetNovelResponse')
        .encode({ name: 'Martial World', id: 36 }).finish();
      const frame = Buffer.alloc(5 + reply.length);
      frame.writeUInt32BE(reply.length, 1);
      Buffer.from(reply).copy(frame, 5);
      return { status: 200, data: frame.toString('base64'), headers: {} };
    },
  };
  const p = sandbox.__sozoLoadLnReader(
    `const { fetchProto } = require('@libs/fetch');
     module.exports.default = { site: 'https://s.test/',
       parseChapter: async () => {
         const r = await fetchProto({ proto: ${JSON.stringify(proto)},
           requestType: 'GetNovelRequest', responseType: 'GetNovelResponse',
           requestData: { slug: 'martial-world' } },
           'https://api.s.test/Novels/GetNovel',
           { headers: { 'Content-Type': 'application/grpc-web+proto' } });
         return r.name + '|' + r.id;
       } };`,
    { id: 'p' },
  );
  assert.equal(await p.getHtmlContent('S', 'x'), 'Martial World|36');
  assert.equal(seen.method, 'POST');
  assert.equal(seen.responseType, 'base64');
  assert.equal(seen.headers['Content-Type'], 'application/grpc-web+proto');
  const body = Buffer.from(seen.bodyBase64, 'base64');
  assert.equal(body[0], 0);
  assert.equal(body.readUInt32BE(1), body.length - 5);
  // The library belongs to the sandbox's realm, and so must its bytes.
  const Bytes = vm.runInContext('Uint8Array', sandbox);
  const request = root.lookupType('GetNovelRequest').decode(Bytes.from(body.subarray(5)));
  assert.equal(request.slug, 'martial-world');
});

/* ---- the fixed builds the app ships ------------------------------------ */

test('every bundled plugin fix loads as the plugin it replaces', () => {
  const dir = path.join(__dirname, '../../assets/lnreader/patches');
  const deps = fs.readFileSync(path.join(__dirname, '../../assets/js/lnreader_deps.js'), 'utf8');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.js'));
  assert.ok(files.length > 0);
  for (const file of files) {
    const sandbox = { console: { warn: () => {}, error: () => {}, log: () => {} }, URL, URLSearchParams, TextEncoder, TextDecoder };
    sandbox.globalThis = sandbox;
    vm.createContext(sandbox);
    vm.runInContext(deps, sandbox);
    vm.runInContext(shim, sandbox);
    const id = file.replace(/\.js$/, '');
    const code = fs.readFileSync(path.join(dir, file), 'utf8');
    const plugin = sandbox.__sozoLoadLnReader(code, { id: 'ln.' + id });
    assert.equal(typeof plugin.getHtmlContent, 'function', file);
    assert.ok(plugin.baseUrl.startsWith('https://'), file);
    const exported = {};
    new Function('module', 'exports', 'require', code)({ exports: exported }, exported, sandbox.__sozoLnReaderInternals.makeRequire(id));
    assert.equal((exported.default || exported).id, id, file);
  }
});
