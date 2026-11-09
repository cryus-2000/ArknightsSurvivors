// Exercise the exported loader in an isolated Chromium renderer, without starting Godot.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const read = file => fs.readFileSync(path.join(__dirname, 'web', file), 'utf8');
const loader = read('loader.js').replace('/*SHUIYUE_MANIFEST*/null', '{}').replace('/*SHUIYUE_BOOT_V*/0', '4');
const html = `<style>${read('loader.css')}</style><body><canvas id="game"></canvas>
  <div id="status-notice"></div><script>${loader}</script></body>`;

async function probe(browser, mode) {
  const page = await browser.newPage({viewport:{width:844,height:390}, deviceScaleFactor:3});
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.route('**/*', route => route.request().isNavigationRequest()
      ? route.fulfill({contentType:'text/html',body:html}) : route.abort());
    const returning = ['title', 'restart'].includes(mode);
    const reload = returning ? '?syrl=' + encodeURIComponent(JSON.stringify({act:mode,t:Date.now()})) : '';
    await page.goto('http://boot.test/' + reload);
    if (returning) {
      // Title._ready consumes the route before shader warmup calls __syBootReady.
      assert.equal(await page.evaluate(() => window.__syRL.take().act), mode);
      assert.equal(await page.evaluate(() => window.__syRL.peek()), null);
    }
    await page.evaluate(mode => {
      if (mode !== 'bypass') {
        window.__syBootUp();
        window.__syBootProgress(.8, '测试');
        window.__syBootReady();
      }
      window.probeRoot = new WeakRef(document.querySelector('#sy-load'));
    }, mode);
    await page.waitForFunction(() => document.querySelector('.p4c').width === innerWidth * 2);
    const before = await page.evaluate(() => Array.from(document.querySelectorAll('#sy-load canvas'))
      .reduce((sum, c) => sum + c.width * c.height * 4, 0));
    if (mode === 'normal') {
      assert.equal(await page.evaluate(() => !!window.__syStart), false);
      await page.waitForTimeout(300);
      await page.keyboard.press('Enter');
    }
    if (mode === 'error') {
      await page.evaluate(() => {document.querySelector('#status-notice').style.display = 'block';});
    } else {
      if (mode !== 'bypass') assert.equal(await page.evaluate(() => window.__syStart), 1);
      await page.evaluate(() => {window.__syBootDone(); window.__syBootDone();});
    }
    await page.waitForFunction(() => !document.querySelector('#sy-load'));
    await page.waitForTimeout(1200);
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('HeapProfiler.collectGarbage');
    const after = await page.evaluate(() => {
      dispatchEvent(new Event('resize'));
      const root = window.probeRoot.deref();
      return {retained:!!root, canvasBytes:root ? Array.from(root.querySelectorAll('canvas'))
        .reduce((sum,c) => sum + c.width*c.height*4,0) : 0,
        hooks:['Up','Progress','Ready','Done'].filter(key => typeof window['__syBoot'+key] === 'function').length,
        gameCanvas:document.querySelector('#game').width};
    });
    console.log(mode, {before, ...after, errors});
    return !after.retained && !after.canvasBytes && !after.hooks && after.gameCanvas === 300 && !errors.length;
  } finally {await page.close();}
}

(async () => {
  const browser = await chromium.launch({channel:'msedge', headless:true, args:['--mute-audio']});
  try {
    const results = [];
    for (const mode of ['normal','title','restart','error','bypass']) results.push(await probe(browser, mode));
    assert(results.every(Boolean), 'detached boot overlay must be collectible in all exit paths');
  } finally {await browser.close();}
})().catch(error => {console.error(error); process.exitCode = 1;});
