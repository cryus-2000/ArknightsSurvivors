// Run with node tools/test_web_canvas_selection.cjs and Playwright WebKit installed.
const assert = require('node:assert/strict');
const path = require('node:path');
const {webkit} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function run() {
  const browser = await webkit.launch({headless: true});
  try {
    const page = await browser.newPage({viewport: {width: 844, height: 390}, hasTouch: true, isMobile: true});
    await page.setContent(`<meta name="viewport" content="width=device-width,initial-scale=1">
      <style>html,body{margin:0}body{touch-action:none}canvas{display:block;width:800px;height:280px}</style>
      <canvas id="canvas">Your browser does not support the canvas tag.</canvas>
      <div>Game margin</div><textarea readonly>完整报告 6:02</textarea><input value="玩家名字">
      <div contenteditable="true">输入法</div><img alt="分享卡">`);
    const dragOntoGame = async () => {
      await page.evaluate(() => getSelection().removeAllRanges());
      const edge = await page.locator('#canvas').boundingBox();
      await page.mouse.move(edge.x + 2, edge.y + edge.height + 1);
      await page.mouse.down();
      await page.mouse.move(edge.x + 80, edge.y + 90, {steps: 10});
      await page.mouse.up();
      return page.evaluate(() => getSelection().type === 'Range' &&
        getSelection().containsNode(document.querySelector('#canvas'), true));
    };
    assert.equal(await dragOntoGame(), true, 'fixture must reproduce the native canvas selection');
    await page.addStyleTag({path: path.join(__dirname, 'web', 'loader.css')});
    assert.equal(await dragOntoGame(), false);

    for (const selector of ['textarea', 'input', '[contenteditable]']) {
      const control = page.locator(selector);
      await control.click();
      await page.keyboard.press('Control+a');
      const selected = await control.evaluate(el => el.isContentEditable ? getSelection().toString() :
        el.value.slice(el.selectionStart, el.selectionEnd));
      assert.ok(selected.length > 0, selector);
    }
    await page.keyboard.type('IME');
    assert.equal(await page.locator('[contenteditable]').innerText(), 'IME');

    await page.addScriptTag({path: path.join(__dirname, 'web', 'share.js')});
    await page.evaluate(() => {
      window.toy = {isSupport: () => true, saveImageToAlbum: data => {
        window.albumPayload = data.base64Data;
        return Promise.resolve();
      }};
    });
    const save = () => page.evaluate(() => new Promise(resolve => window.__syShare.save('YWJj', resolve)));
    assert.equal(await save(), 'album');
    assert.equal(await page.evaluate(() => window.albumPayload), 'data:image/png;base64,YWJj');
    await page.evaluate(() => { delete window.toy; });
    const [download, outcome] = await Promise.all([page.waitForEvent('download'), save()]);
    assert.equal(outcome, 'download');
    assert.equal(download.suggestedFilename(), '方舟幸存者_战绩.png');
    console.log('PASS canvas selection, report text, native editing, album and download');
  } finally {
    await browser.close();
  }
}
run().catch(err => { console.error(err); process.exitCode = 1; });
