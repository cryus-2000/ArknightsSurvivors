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
let inGesture = false, resumeAnywhere = false, plays = 0;
const timers = [];
const document = {
  hidden: false,
  createElement: () => ({ setAttribute() {}, play() { plays++; return Promise.resolve(); } }),
  addEventListener: (t, f) => docBus.on(t, f),
  removeEventListener: (t, f) => docBus.off(t, f),
};
class FakeCtx {
  constructor() { this.state = "suspended"; this.sampleRate = 48000; this.b = bus(); this.destination = {}; this.currentTime = 0; this.cycles = 0; }
  addEventListener(t, f) { this.b.on(t, f); }
  _set(s) { if (this.state !== s) { this.state = s; this.b.fire("statechange"); } }
  resume() { if (inGesture || resumeAnywhere) this._set("running"); return Promise.resolve(); }   // iOS：手势外 resume 白调
  suspend() { if (inGesture) this.cycles++; this._set("suspended"); return Promise.resolve(); }
  createBuffer() { return {}; }
  createBufferSource() { return { connect() {}, start() {} }; }
}
const window = {
  AudioContext: FakeCtx,
  addEventListener: (t, f) => winBus.on(t, f),
};
const ctxEnv = { setInterval: (f) => timers.push(f), URL: { createObjectURL: () => "blob:x" }, Blob: function () {}, window, document, navigator: { maxTouchPoints: 5 }, screen: { width: 390, height: 844 }, location: { search: "" }, URLSearchParams };
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
// 11-08 iOS 26.6：回前台时非手势 resume 生效、state 已是 running，但输出没接回 → 下一下手势仍要在手势里 suspend+resume 重启、播静音 <audio>
document.hidden = true; docBus.fire("visibilitychange");
resumeAnywhere = true;
document.hidden = false; docBus.fire("visibilitychange");
resumeAnywhere = false;
ok(C.state === "running", "回前台非手势 resume 生效（iOS 26 模拟）");
ok(docBus.n("touchstart") === 1, "即使已 running，回前台也挂着手势监听");
const c0 = C.cycles, p0 = plays;
tap("touchend");
ok(C.cycles === c0 + 1 && C.state === "running", "回来后第一下手势：手势内 suspend 再 resume");
ok(plays === p0 + 1, "第一下手势播静音 <audio> 激活媒体会话");
tap("touchend");
ok(C.cycles === c0 + 2, "第二下手势再重启一次（STALE_N=2）");
ok(docBus.n("touchend") === 0, "之后撤掉监听");
tap("touchend");
ok(C.cycles === c0 + 2, "撤掉后不再重启");
// 看门狗：running 但时钟不走 → 重新挂监听、下一下手势重启
timers.forEach((f) => f()); C.currentTime = 0; timers.forEach((f) => f());
ok(docBus.n("touchend") === 1, "看门狗：running 但 currentTime 不走 → 挂上手势监听");
tap("touchend");
ok(C.cycles === c0 + 3, "看门狗之后的手势重启输出");
console.log("POWER JS failures=" + fails);
process.exit(fails ? 1 : 0);
