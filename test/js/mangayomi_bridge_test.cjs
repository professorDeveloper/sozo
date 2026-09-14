const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const shim = fs.readFileSync(path.join(__dirname, '../../assets/js/mangayomi_bridge.js'), 'utf8');
function host() {
  const calls = [];
  const sandbox = { URLSearchParams, TextEncoder, TextDecoder, DOMParser: class {},
    dartFetch: async (request) => { calls.push(request); return {status:200,data:'ok',headers:{}}; },
  };
  sandbox.window = sandbox;
  sandbox.flutter_inappwebview = {callHandler: async (name, request) => {
    calls.push({handler:name, ...request});
    return {value:request.method === 'book' ? {chapters:['Opening']} : '<p>Prose</p>'};
  }};
  vm.createContext(sandbox);
  vm.runInContext(shim, sandbox);
  return {sandbox, calls};
}
test('form POST encodes WordPress action and preserves lowercase content-type', async () => {
  const {sandbox, calls} = host();
  await vm.runInContext(`new Client().post('https://novel.example/ajax', {'content-type':'application/x-www-form-urlencoded; charset=UTF-8'}, {action:'nd_getchapters', mypostid:'42', tags:['a b','c&d']})`, sandbox);
  const form = new URLSearchParams(calls[0].body);
  assert.equal(form.get('action'), 'nd_getchapters');
  assert.equal(form.get('mypostid'), '42');
  assert.deepEqual(form.getAll('tags'), ['a b','c&d']);
  assert.equal(calls[0].headers['Content-Type'], undefined);
});
test('object requests without explicit media type remain JSON', async () => {
  const {sandbox, calls} = host();
  await vm.runInContext(`new Client().post('https://api.example', {}, {query:'novel'})`, sandbox);
  assert.equal(calls[0].headers['Content-Type'], 'application/json');
  assert.deepEqual(JSON.parse(calls[0].body), {query:'novel'});
});
test('image headers resolve in one host call with each page URL', async () => {
  const {sandbox} = host();
  sandbox.__sozoLoadMangayomi(`class DefaultExtension extends MProvider { getHeaders(url) { return {Referer:url}; } }`, {id:'source'});
  const headers = await sandbox.__sozoImageHeaders(['https://cdn/1', 'https://cdn/2']);
  assert.equal(headers[0].Referer, 'https://cdn/1');
  assert.equal(headers[1].Referer, 'https://cdn/2');
});
test('EPUB helpers send headers and chapter identity to the binary host', async () => {
  const {sandbox, calls} = host();
  const book = await sandbox.parseEpub('Book', 'https://cdn/book.epub', {Cookie:'session=x'});
  assert.equal(book.chapters[0], 'Opening');
  assert.equal(await sandbox.parseEpubChapter('Book','https://cdn/book.epub',{},'Opening'), '<p>Prose</p>');
  assert.equal(calls[0].handler, 'mangayomiEpub');
  assert.equal(calls[0].headers.Cookie, 'session=x');
  assert.equal(calls[1].chapter, 'Opening');
});
