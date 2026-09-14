// Run from sozo: node docs/audits/2026-09-14/source-reader/repros/default_novels_probe.cjs
// Actual production JS shim + unchanged primary-source extension scripts.
// DOM and HTTP are fixtures; no live sites or EPUB downloads are exercised.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const fixtureDir = path.join(__dirname, 'novel_fixtures');
const sources = JSON.parse(fs.readFileSync(path.join(fixtureDir, 'sources.json'), 'utf8'));
globalThis.window = globalThis;
globalThis.DOMParser = class {}; // The production wrapper is replaced below by deterministic selectors.
const requests = [];
globalThis.dartFetch = async (request) => {
  requests.push(request);
  return { status: 200, data: '<html>Fixture</html>', headers: {} };
};
vm.runInThisContext(fs.readFileSync('assets/js/mangayomi_bridge.js', 'utf8'));

// Supply detail metadata/mirror selectors independently of HTML scraping.
const element = {
  text: 'Fixture', getSrc: 'https://fixture.example/cover.jpg',
  getHref: 'https://libgen.is/book', innerHtml: '<p>Fixture prose</p>',
  attr: () => '42',
  select: (selector) => selector === 'li > a' ? [element] : [],
  selectFirst: () => element,
};
globalThis.Document = class {
  selectFirst() { return element; }
  select() { return []; }
};

(async () => {
  for (const fixture of sources) {
    assert.equal(fixture.source.itemType, 2);
    assert.equal(fixture.source.sourceCodeLanguage, 1);
    __sozoLoadMangayomi(fs.readFileSync(path.join(fixtureDir, fixture.file), 'utf8'), fixture.source);
    assert.equal(typeof __sozoProvider.getDetail, 'function');
    assert.equal(typeof __sozoProvider.getHtmlContent, 'function');
    console.log('LOAD OK:', fixture.source.name, 'itemType=2');
  }

  const anna = sources.find(x => x.file === 'annasarchive.js');
  __sozoActivateMangayomi(String(anna.source.id));
  __sozoProvider._getMirrorLink = async () => 'https://fixture.example/book.epub';
  assert.equal(typeof globalThis.parseEpub, 'undefined');
  assert.equal(typeof globalThis.parseEpubChapter, 'undefined');
  await assert.rejects(__sozoProvider.getDetail('/md5/fixture'), /parseEpub is not defined/);
  await assert.rejects(__sozoProvider.getHtmlContent('Book', 'https://libgen.is/book;;;Chapter 1'), /parseEpubChapter is not defined/);
  console.log('CONFIRMED: Annas Archive actual getDetail/getHtmlContent throw missing EPUB host APIs');

  const nu = sources.find(x => x.file === 'novelupdates.js');
  __sozoActivateMangayomi(String(nu.source.id));
  requests.length = 0;
  await __sozoProvider.getDetail('https://www.novelupdates.com/series/fixture/');
  const post = requests.find(x => x.method === 'POST');
  assert.ok(post.headers['Content-Type'].startsWith('application/x-www-form-urlencoded'));
  assert.equal(post.body, JSON.stringify({action: 'nd_getchapters', mygrr: '0', mypostid: '42'}));
  assert.equal(new URLSearchParams(post.body).get('action'), null);
  console.log('CONFIRMED: Novel Updates chapter POST declares form encoding but contains JSON:', post.body);
})().catch(e => { console.error(e); process.exitCode = 1; });
