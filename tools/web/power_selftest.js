/* tools/web/power.js 音频恢复的自测（docs/317）：node tools/web/power_selftest.js
 * 假 AudioContext 按 iOS WebKit 的脾气：非手势里 resume() 不生效、只有手势里 resume 才回到 running；系统可以把它打成 interrupted。
 * 走一遍：首次点按解锁 → 切到后台（挂起）→ 回到前台（非手势 resume 无效）→ 第一下 touchstart 恢复 → 前台被中断（interrupted）→ 下一下 pointerdown 恢复；
 * 都 running 后手势监听撤掉。全部通过打印 "POWER JS failures=0"，退出码 0。
 */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "power.js"), "utf8");

function bus() {
  const m = {};
  return {
    on(t, f) { (m[t] = m[t] || []).push(f); },
    off(t, f) { m[t] = (m[t] || []).filter((x) => x !== f); },
    fire(t) { (m[t] || []).slice().forEach((f) => f({ type: t })); },
    n(t) { return (m[t] || []).length; },
  };
}
const docBus = bus(), winBus = bus();
let inGesture = false;
const document = {
  hidden: false,
  addEventListener: (t, f) => docBus.on(t, f),
  removeEventListener: (t, f) => docBus.off(t, f),
};
class FakeCtx {
  constructor() { this.state = "suspended"; this.sampleRate = 48000; this.b = bus(); this.destination = {}; }
  addEventListener(t, f) { this.b.on(t, f); }
  _set(s) { if (this.state !== s) { this.state = s; this.b.fire("statechange"); } }
  resume() { if (inGesture) this._set("running"); return Promise.resolve(); }   // iOS：手势外 resume 白调
  suspend() { this._set("suspended"); return Promise.resolve(); }
  createBuffer() { return {}; }
  createBufferSource() { return { connect() {}, start() {} }; }
}
const window = {
  AudioContext: FakeCtx,
  addEventListener: (t, f) => winBus.on(t, f),
};
const ctxEnv = { window, document, navigator: { maxTouchPoints: 5 }, screen: { width: 390, height: 844 }, location: { search: "" }, URLSearchParams };
new Function(...Object.keys(ctxEnv), src)(...Object.values(ctxEnv));

let fails = 0;
function ok(c, what) { console.log((c ? "ok   " : "FAIL ") + what); if (!c) fails++; }
function tap(t) { inGesture = true; docBus.fire(t); inGesture = false; }

const C = new window.AudioContext();
ok(C.state === "suspended", "新建上下文是 suspended（自动播放限制）");
tap("touchend");
ok(C.state === "running", "第一下点按解锁");
ok(docBus.n("touchend") === 0, "都 running 后撤掉手势监听");
document.hidden = true; docBus.fire("visibilitychange");
ok(C.state === "suspended", "切到后台挂起");
document.hidden = false; docBus.fire("visibilitychange");
ok(C.state === "suspended", "回到前台：非手势 resume 在 iOS 上无效（模拟）");
ok(docBus.n("touchstart") === 1, "回到前台重新挂上手势监听");
tap("touchstart");
ok(C.state === "running", "回来后的第一下 touchstart 恢复声音");
tap("click");
ok(docBus.n("touchstart") === 0, "恢复后下一下手势撤掉监听");
C._set("interrupted");
ok(docBus.n("pointerdown") === 1, "前台被系统中断（interrupted）→ 挂上手势监听");
tap("pointerdown");
ok(C.state === "running", "interrupted 后下一下 pointerdown 恢复");
inGesture = false; winBus.fire("pageshow");
ok(C.state === "running", "pageshow 时已 running 不受影响");
ok(window.__syAudioState() === "running", "__syAudioState 报状态");
console.log("POWER JS failures=" + fails);
process.exit(fails ? 1 : 0);
