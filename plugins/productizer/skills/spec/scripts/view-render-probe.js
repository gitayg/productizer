// view-render-probe.js <page.html>
//
// The measuring instrument behind check-view-rendered.sh. It opens a BUILT
// page in headless Chrome, opens the architecture panel through the page's own
// showTab(), and prints what the page DREW - one tab-separated record per
// line. It asserts nothing: every judgement is made by the shell script that
// reads this, so a reading can be looked at by hand when a case goes red.
//
// WHY A BROWSER AND NOT A PARSER. Everything this reads is produced by the
// page's JavaScript from the VZ_ARCH blob and then resolved by the CSS
// cascade: the border style a state ends up wearing, the glyph, the word, and
// whether a state box is a hatch or a flat fill. A reader that parsed the HTML
// would be reading the template's intentions, which is what build-view.sh's
// own self-test already reads. This reads the drawing.
//
// THREE MODES, ONE LAUNCH. The page is read three times without reloading the
// browser: as it comes, under `forced-colors: active`, and under
// `prefers-contrast: more`. Both of those are set through a raw CDP
// `Emulation.setEmulatedMedia` call, because puppeteer's own
// emulateMediaFeatures rejects them as unknown feature names - which is also
// why `prefers-contrast` went four releases written down as done and never
// written at all. A mode nobody can emulate is a mode nobody checked.
//
// NO NETWORK. Every request whose URL is not file: is aborted, so the page's
// font <link> cannot make this test depend on a name server. A page that
// needed the network to draw its states would fail here, which is correct: the
// page is meant to be a static file.
//
// EXIT CODES
//   0  a reading was printed
//   2  could not run - bad usage, no page, no puppeteer, or a browser that
//      would not launch. Never a silent empty reading: a page that drew
//      nothing and a browser that never opened print the same zero counts, and
//      only one of them is a finding.
'use strict';

const MODES = [
  ['default', []],
  ['forced-colors', [{ name: 'forced-colors', value: 'active' }]],
  ['prefers-contrast', [{ name: 'prefers-contrast', value: 'more' }]]
];

function die(msg) {
  process.stderr.write('view-render-probe: ' + msg + '\n');
  process.exit(2);
}

// One line per record. Tabs separate fields and nothing printed may contain
// one: a page's own text is read into these lines, and a stray tab would move
// every field after it into the wrong column.
function say(fields) {
  process.stdout.write(fields.map(function (f) {
    return String(f).replace(/[\t\r\n]+/g, ' ').trim();
  }).join('\t') + '\n');
}

// What the page drew, read out of the live DOM. Runs inside the page.
function reading() {
  var cs = function (e) { return getComputedStyle(e); };
  var txt = function (e) { return e ? e.textContent : ''; };
  var out = { nodes: [], drows: [], dcounts: [], stats: [], unread: [], dunk: [] };
  var i;
  var nodes = document.querySelectorAll('.ag-node');
  for (i = 0; i < nodes.length; i++) {
    var n = nodes[i], s = cs(n);
    out.nodes.push({
      id: n.getAttribute('data-ag') || '',
      cls: n.className,
      word: txt(n.querySelector('.ag-w')),
      glyph: txt(n.querySelector('.ag-g')),
      style: s.borderTopStyle,
      width: s.borderTopWidth,
      hatch: s.backgroundImage && s.backgroundImage !== 'none' ? 'hatch' : 'flat',
      label: txt(n.querySelector('.ag-lab')),
      aria: n.getAttribute('aria-label') || ''
    });
  }
  var rows = document.querySelectorAll('.ag-delta .ag-drow');
  for (i = 0; i < rows.length; i++) {
    var r = rows[i], b = r.querySelector('.ag-dbadge'), bs = b ? cs(b) : null;
    out.drows.push({
      id: txt(r.querySelector('.ag-did')),
      cls: b ? b.className : '',
      word: b ? txt(b) : '',
      glyph: b ? txt(b.querySelector('.ag-dg')) : '',
      style: bs ? bs.borderTopStyle : '',
      width: bs ? bs.borderTopWidth : '',
      meta: txt(r.querySelector('.ag-dmeta'))
    });
  }
  var dc = document.querySelectorAll('.ag-delta .ag-strip .ag-stat');
  for (i = 0; i < dc.length; i++) {
    var d = dc[i], db = d.querySelector('.ag-dbadge');
    out.dcounts.push({
      label: db ? txt(db.querySelector('.ag-dg')) + '|' + txt(db).replace(txt(db.querySelector('.ag-dg')), '')
                : txt(d.querySelector('span')),
      value: txt(d.querySelector('b')),
      cls: d.className
    });
  }
  var st = document.querySelectorAll('.ag > .ag-strip > .ag-stat');
  for (i = 0; i < st.length; i++) {
    out.stats.push({
      label: txt(st[i].querySelector('span')),
      value: txt(st[i].querySelector('b')),
      cls: st[i].className
    });
  }
  var ur = document.querySelectorAll('.ag-unread');
  for (i = 0; i < ur.length; i++) {
    out.unread.push({ glyph: txt(ur[i].querySelector('.ag-g')), text: txt(ur[i]).slice(0, 400) });
  }
  var du = document.querySelectorAll('.ag-delta .ag-dunk');
  for (i = 0; i < du.length; i++) {
    out.dunk.push({ glyph: txt(du[i].querySelector('.ag-g')), text: txt(du[i]).slice(0, 400) });
  }
  out.mounted = !!document.getElementById('vz-arch');
  out.panel = !!document.querySelector('#p-vz.on');
  return out;
}

(async function () {
  var argv = process.argv.slice(2);
  if (argv.length !== 1 || argv[0].charAt(0) === '-') {
    die('usage: view-render-probe.js <page.html>. One built page, no flags.');
  }
  var page_path = argv[0];
  var fs = require('fs');
  if (!fs.existsSync(page_path)) die('no page at the path given: it cannot be read, so nothing was measured');

  var puppeteer;
  try {
    puppeteer = require('puppeteer');
  } catch (e) {
    die('puppeteer could not be required. Set NODE_PATH to a directory holding it. ' +
        'Nothing was rendered and nothing is asserted.');
  }

  var browser;
  try {
    browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  } catch (e) {
    die('a headless browser would not launch: ' + String(e && e.message).slice(0, 200));
  }
  try {
    var page = await browser.newPage();
    await page.setViewport({ width: 1400, height: 1000, deviceScaleFactor: 1 });
    await page.setRequestInterception(true);
    page.on('request', function (req) {
      if (req.url().indexOf('file:') === 0) req.continue(); else req.abort();
    });
    var errors = [];
    page.on('pageerror', function (e) { errors.push(String(e && e.message).slice(0, 200)); });

    var cdp = await page.createCDPSession();
    for (var m = 0; m < MODES.length; m++) {
      var name = MODES[m][0], features = MODES[m][1];
      await cdp.send('Emulation.setEmulatedMedia', { features: features });
      if (m === 0) {
        await page.goto('file://' + require('path').resolve(page_path), { waitUntil: 'domcontentloaded' });
      } else {
        await page.reload({ waitUntil: 'domcontentloaded' });
      }
      // The media feature is read back from inside the page rather than
      // assumed from the CDP call: an emulation that silently did nothing is
      // how a mode gets reported as checked when it was not.
      var matched = await page.evaluate(function () {
        return { forced: matchMedia('(forced-colors: active)').matches,
                 contrast: matchMedia('(prefers-contrast: more)').matches };
      });
      await page.evaluate(function () { if (typeof showTab === 'function') showTab('vz'); });
      await new Promise(function (r) { setTimeout(r, 250); });
      var got = await page.evaluate(reading);

      say(['mode', name, 'forced=' + matched.forced, 'contrast=' + matched.contrast,
           'mounted=' + got.mounted, 'panel=' + got.panel]);
      say(['count', name, 'nodes=' + got.nodes.length, 'drows=' + got.drows.length,
           'dcounts=' + got.dcounts.length, 'stats=' + got.stats.length,
           'unread=' + got.unread.length, 'dunk=' + got.dunk.length]);
      got.nodes.forEach(function (n) {
        say(['node', name, n.id, n.word, n.glyph, n.style, n.width, n.hatch, n.cls, n.aria]);
      });
      got.drows.forEach(function (r) {
        say(['drow', name, r.id, r.word, r.glyph, r.style, r.width, r.cls, r.meta]);
      });
      got.dcounts.forEach(function (d) { say(['dcount', name, d.label, d.value, d.cls]); });
      got.stats.forEach(function (s) { say(['stat', name, s.label, s.value, s.cls]); });
      got.unread.forEach(function (u) { say(['unread', name, u.glyph, u.text]); });
      got.dunk.forEach(function (u) { say(['dunk', name, u.glyph, u.text]); });
    }
    errors.forEach(function (e) { say(['pageerror', e]); });
  } catch (e) {
    try { await browser.close(); } catch (ignored) { /* the reading already failed */ }
    die('the page could not be read: ' + String(e && e.message).slice(0, 200));
  }
  await browser.close();
  process.exit(0);
}());
