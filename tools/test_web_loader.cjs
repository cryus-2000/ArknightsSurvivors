const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
function fixture() {
  const elements = new Map(), intervals = new Map(), timeouts = new Map();
  let seq = 0;
  const child = () => ({style:{},className:'',innerHTML:'',textContent:''});
  const root = child(); root.classes = new Set(); root.classList = {add:x=>root.classes.add(x)};
  root.querySelectorAll = () => [root.l1,root.l2,root.l3];
  [root.l1,root.l2,root.l3] = [child(),child(),child()];
  const parts = new Map(['.sy-ring','.sy-num','.sy-tips .bd'].map(k=>[k,child()]));
  root.querySelector = k => parts.get(k);
  root.remove = () => { root.parentNode=null; elements.delete('sy-load'); };
  const body={appendChild:d=>{d.parentNode=body;elements.set(d.id,d);}};
  const document={body,createElement:()=>root,getElementById:id=>elements.get(id)||null};
  elements.set('status',child()); elements.set('status-notice',child());
  const window={fetch:async()=>new Response(new Uint8Array([1]))};
  const context={window,document,performance:{now:()=>1000},console,Response,Uint8Array,Math,Promise,
    setInterval:f=>{intervals.set(++seq,f);return seq},clearInterval:id=>intervals.delete(id),
    setTimeout:f=>{timeouts.set(++seq,f);return seq},clearTimeout:id=>timeouts.delete(id)};
  const source=fs.readFileSync(path.join(__dirname,'web/loader.js'),'utf8').replace('/*SHUIYUE_MANIFEST*/null',JSON.stringify({'index.pck':{size:1,parts:[['part',1,1]]}}));
  vm.runInNewContext(source,context);
  return {window,root,parts,elements,intervals,timeouts,tick:()=>[...intervals.values()].forEach(f=>f()),flush:()=>{for(const [id,f] of [...timeouts]){timeouts.delete(id);f();}}};
}
(async()=>{
 const f=fixture();
 await f.window.fetch('index.pck');
 f.tick();
 f.window.__syBootUp();
 assert(!f.root.classes.has('sy-out'),'engine boot handoff must retain the same loader');
 assert.equal(typeof f.window.__syBootProgress,'function');
 f.window.__syBootProgress(.9,'读取界面');
 assert.equal(f.window.__syPct,.9);
 f.tick(); assert.equal(f.window.__syPct,.9,'timer must not reset real game progress');
 f.window.__syBootProgress(.82,'准备画面');
 assert.equal(f.window.__syPct,.9,'progress must never move backward');
 f.elements.delete('status'); f.tick();
 assert(!f.root.classes.has('sy-out'),'engine status removal must not reveal a second loader');
 f.window.__syBootProgress(1,'准备主菜单');
 assert(!f.root.classes.has('sy-out'),'only explicit title-ready signal dismisses overlay');
 f.window.__syBootDone(); f.window.__syBootDone();
 assert(f.root.classes.has('sy-out')); assert.equal(f.intervals.size,0);
 f.flush(); assert(!f.elements.has('sy-load'));
 const bypass=fixture();bypass.window.__syBootDone();
 assert.equal(bypass.window.__syPct,1,'skip path may finish without the normal handshake');
 bypass.flush();assert(!bypass.elements.has('sy-load'));
 const error=fixture();error.elements.get('status-notice').style.display='block';error.tick();
 assert(error.root.classes.has('sy-out'),'engine errors stay visible');error.flush();
 console.log('WEB LOADER lifecycle passed');
})().catch(e=>{console.error(e);process.exitCode=1});
