// Run against an exported web directory. PLAYWRIGHT_MODULE may point to a bundled installation.
// --bypass requires a debug export; it injects --memlog to exercise the boot skip path.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(process.argv[2]);
const bypass = process.argv.includes('--bypass');
const output = path.resolve(process.env.BOOT_PROBE_OUT || 'output/playwright/web-boot');
const types = {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.css':'text/css'};
const server = http.createServer((req,res) => {
  const file = path.resolve(root, '.' + decodeURIComponent(new URL(req.url,'http://localhost').pathname));
  if (file !== root && !file.startsWith(root + path.sep)) {res.writeHead(403).end();return;}
  const target = file === root ? path.join(root,'index.html') : file;
  try {
    let data = fs.readFileSync(target);
    if (bypass && path.basename(target)==='index.html') {
      const html = data.toString();
      assert(html.includes('"args":[]'), 'export config must contain empty args');
      data = Buffer.from(html.replace('"args":[]','"args":["--","--memlog"]'));
    }
    res.writeHead(200,{'Content-Type':types[path.extname(target)]||'application/octet-stream'}).end(data);
  } catch (e) {res.writeHead(404).end(String(e));}
});
(async()=>{
  fs.mkdirSync(output,{recursive:true});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    browser = await chromium.launch({channel:'msedge',headless:true,args:['--mute-audio']});
    const page = await browser.newPage({viewport:{width:1280,height:720}});
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if (/SCRIPT ERROR|Parse Error/.test(m.text())) errors.push(m.text());});
    await page.addInitScript(()=>{
      window.bootProbe={calls:[],removedBeforeDone:false,maxLoaders:0};
      for (const key of ['__syBootUp','__syBootProgress','__syBootDone']) {
        let fn;
        Object.defineProperty(window,key,{configurable:true,get:()=>fn,set:value=>{
          fn=(...args)=>{const result=value(...args);window.bootProbe.calls.push({key,args,pct:window.__syPct,time:performance.now()});return result;};
        }});
      }
      new MutationObserver(records=>{
        const p=window.bootProbe;
        p.maxLoaders=Math.max(p.maxLoaders,document.querySelectorAll('#sy-load').length);
        for (const record of records) for (const node of record.removedNodes) {
          if (node.id==='sy-load' && !p.calls.some(c=>c.key==='__syBootDone')) p.removedBeforeDone=true;
        }
      }).observe(document,{childList:true,subtree:true});
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:'domcontentloaded',timeout:60000});
    await page.waitForFunction(()=>window.bootProbe.calls.some(c=>c.key==='__syBootDone'),{},{timeout:240000});
    await page.waitForFunction(()=>!document.getElementById('sy-load'),{},{timeout:10000});
    const result=await page.evaluate(()=>window.bootProbe);
    assert.equal(result.maxLoaders,1);
    assert.equal(result.removedBeforeDone,false);
    assert.equal(result.calls.filter(c=>c.key==='__syBootDone').length,1);
    assert.equal(result.calls.some(c=>c.key==='__syBootUp'),!bypass);
    const progress=result.calls.filter(c=>c.key==='__syBootProgress').map(c=>c.pct);
    for(let i=1;i<progress.length;i++) assert(progress[i]>=progress[i-1], 'boot progress must be monotonic');
    assert.deepEqual(errors,[]);
    await page.screenshot({path:path.join(output,bypass?'bypass.png':'normal.png')});
    fs.writeFileSync(path.join(output,bypass?'bypass.json':'normal.json'),JSON.stringify({...result,errors},null,2));
    console.log(`WEB BOOT ${bypass?'bypass':'normal'} passed; ${progress.length} progress reports`);
  } finally {if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1});
