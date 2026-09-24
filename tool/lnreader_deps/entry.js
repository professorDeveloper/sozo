// Bundled by `npm install && npm run build` in this folder into
// assets/js/lnreader_deps.js, which the Mangayomi runtime loads before
// assets/js/lnreader.js. The packages are the ones LNReader plugins are
// written against; they run unmodified.
import * as cheerio from 'cheerio/slim';
import * as htmlparser2 from 'htmlparser2';
import dayjs from 'dayjs';
globalThis.__lnDeps = { cheerio, htmlparser2, dayjs };
