/* tools/web/web_music.js 终局配乐驻留自测（docs/332 §2）：node tools/web/web_music_selftest.js
 * 假 Web Audio（手机口径：24 kHz 上下文、单声道留存），照 sfx.gd _wm_sync 的调用顺序走偏执泡影一局：
 *   一阶段 p1 开播 → 二阶段 p2 听得见才开播（懒加载层）→ 预混到位后底层 p1 在开播那一刻切到 0、停掉并丢掉缓冲
 *   → 整组淡出时底层不复活 → 曲终 stop + free 全部释放；另走二阶段退回（重新解 p1、按预混进度对齐）与预混文件缺失（退回旧行为）。
 * 判定按 __syMus.mb()（JS 里实际留着的解码缓冲）与源的开停，不估算。全部通过打印 "WEB MUSIC failures=0"，退出码 0。
 */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "web_music.js"), "utf8");

const SR = 24000;
const LEN = 203.21453125;
const ONE = (LEN * SR * 4) / 1048576;   // 一首单声道解码缓冲（MiB）
let failures = 0;
function check(ok, label) {
  if (!ok) { failures++; console.log("FAIL: " + label); }
}
const near = (a, b, tol) => Math.abs(a - b) <= (tol || 0.05);

function run(opts) {
  const files = {   // url -> 声道数（出包：p1 / p2 立体声，p1_mono 与预混单声道）
    "music_suno_final_p1.m4a": 2, "music_suno_final_p2.m4a": 2,
    "music_suno_final_p1_mono.m4a": 1, "music_suno_final_p12_mono.m4a": 1,
  };
  if (opts.noMix) delete files["music_suno_final_p12_mono.m4a"];
  const fetched = [];
  let timers = [];
  class Param {
    constructor(v) { this.value = v; this.ev = []; }
    setTargetAtTime(v, t) { this.ev.push([t, v]); }
    setValueAtTime(v, t) { this.ev.push([t, v]); }
    cancelScheduledValues(t) { this.ev = this.ev.filter((e) => e[0] < t); }
    at(t) {   // 只看目标值（足够判定：最后一个 ≤ t 的事件）
      let v = this.value;
      for (const e of this.ev) if (e[0] <= t + 1e-9) v = e[1];
      return v;
    }
  }
  class Buf {
    constructor(ch, len, sr) { this.numberOfChannels = ch; this.length = len; this.sampleRate = sr; this.duration = len / sr; }
    getChannelData() { return new Float32Array(1); }
  }
  const sources = [], gainNodes = [];
  let wall = 0;
  const ctx = {
    state: opts.suspended ? "suspended" : "running", sampleRate: SR, currentTime: 0, destination: {},
    createBiquadFilter: () => ({ type: "", frequency: new Param(20000), Q: new Param(1), connect() {} }),
    createGain() { const g = { gain: new Param(1), connect() {}, disconnect() {} }; gainNodes.push(g); return g; },
    createAnalyser: () => ({ fftSize: 2048, getFloatTimeDomainData() {} }),
    createBuffer: (ch, n, sr) => new Buf(ch, n, sr),
    createBufferSource() {
      const s = { buffer: null, loop: false, started: null, stopped: false, connect() {}, disconnect() {},
        start(when, off) { this.started = [when, off]; }, stop() { this.stopped = true; } };
      sources.push(s);
      return s;
    },
    decodeAudioData(a, res, rej) {
      if (!a.ch) return rej(new Error("bad"));
      res(new Buf(a.ch, Math.round(LEN * SR), SR));
    },
  };
  class Offline {
    constructor(ch, n, sr) { this.ch = ch; this.n = n; this.sr = sr; this.destination = {}; }
    createBufferSource() { return { connect() {}, start() {} }; }
    startRendering() { return Promise.resolve(new Buf(this.ch, this.n, this.sr)); }
  }
  const window = { __syAudioCtx: [ctx], __sySampleRate: SR, OfflineAudioContext: Offline };
  const sandbox = {
    window, location: { search: opts.search || "" }, URLSearchParams, Promise, Math, Object, String, JSON, Float32Array, console,
    performance: { now: () => wall * 1000 },
    setTimeout: (f, ms) => { timers.push([wall + ms / 1000, f]); },
    fetch: (url) => {
      fetched.push(url);
      return Promise.resolve(files[url] ? { ok: true, arrayBuffer: () => Promise.resolve({ byteLength: 1000, ch: files[url] }) }
        : { ok: false, status: 404 });
    },
  };
  new Function(...Object.keys(sandbox), src)(...Object.values(sandbox));
  const M = window.__syMus;
  const flush = async () => { for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r)); };
  const advance = async (sec) => {
    wall += sec;
    if (!opts.suspended) ctx.currentTime += sec;   // 挂起的上下文时钟不走（定时器照墙钟走）
    const due = timers.filter((t) => t[0] <= wall + 1e-9);
    timers = timers.filter((t) => t[0] > wall + 1e-9);
    due.forEach((t) => t[1]());
    await flush();
  };
  return { M, ctx, sources, gainNodes, fetched, flush, advance };
}

const P1 = "music_suno_final_p1.m4a", P2 = "music_suno_final_p2.m4a";

async function main() {
  // ---- 1. 正常一局：一阶段 → 二阶段 → 整组淡出 → 曲终
  {
    const { M, ctx, sources, gainNodes, fetched, flush, advance } = run({});
    M.play([["1", P1, 0, 0, LEN, 1.0]]);
    await flush();
    check(near(M.mb(), ONE), "p1 phase holds one buffer (" + M.mb().toFixed(1) + ")");
    check(fetched.includes("music_suno_final_p1_mono.m4a"), "p1 uses mono premix file");
    const base = sources[0];
    await advance(30);
    // 二阶段：懒加载层听得见了才 play（音量刚起来），随后几帧淡到 1
    M.play([["2", P2, 30, 0, LEN, 0.1]]);
    M.gain([["2", 1.0]]);
    check(near(M.mb(), ONE), "while premix decodes still one buffer");
    await flush();
    check(fetched.includes("music_suno_final_p12_mono.m4a") && !fetched.includes(P2), "p2 slot decodes the p1+p2 premix, not raw p2");
    const mix = sources[1];
    check(mix && mix.started && near(mix.started[1], 30 + 0.03, 0.01), "premix starts at p1's timeline position");
    const when = mix.started[0];
    // 预混开播那一刻底层切到 0（不叠也不空）：gainNodes[0] 底层（总线在它之后建），[1] 总线，[2] 预混
    const bG = gainNodes[0].gain, mG = gainNodes[2].gain;
    check(near(bG.at(when - 0.001), 1.0) && near(bG.at(when), 0.0) && near(mG.at(when), 1.0), "handover is sample-exact at premix start (base " + bG.at(when - 0.001) + "→" + bG.at(when) + ", mix " + mG.at(when) + ")");
    check(!base.stopped, "base still playing until handover");
    await advance(0.2);
    check(base.stopped, "base p1 stopped after handover");
    check(near(M.mb(), ONE), "phase 2 holds one buffer (" + M.mb().toFixed(1) + " MiB, was 2 × " + ONE.toFixed(1) + ")");
    const st = JSON.parse(M.state());
    check(st.mix === 1 && st.ret === 1 && st.on === 1, "state mix/ret/on " + M.state());
    // 整组淡出（victory_flow）：两层音量一起降，底层差值仍为 0，不能复活
    M.gain([["1", 0.5], ["2", 0.5]]);
    await advance(0.5);
    M.gain([["1", 0.0], ["2", 0.0]]);
    await advance(0.5);
    check(sources.length === 2, "group fade does not revive base (sources " + sources.length + ")");
    void ctx;
    // 曲终：sfx.gd 停掉两个占位器（同一批 stop）再 free
    M.stop(["1", "2"]);
    M.free([P1, P2]);
    await flush();
    check(near(M.mb(), 0), "all music freed after track end (" + M.mb().toFixed(1) + ")");
    check(sources.length === 2 && mix.stopped, "end: no revive, premix stopped");
  }
  // ---- 2. 二阶段退回（预混音量降到 0）：重新解底层、按预混进度对齐接上
  {
    const { M, sources, flush, advance } = run({});
    M.play([["1", P1, 0, 0, LEN, 1.0]]);
    await flush();
    await advance(10);
    M.play([["2", P2, 10, 0, LEN, 1.0]]);
    await flush();
    await advance(0.2);
    check(near(M.mb(), ONE), "regress: phase 2 one buffer");
    await advance(20);
    M.gain([["2", 0.0]]);
    await flush();
    const nb = sources[2];
    const mix = sources[1];
    check(nb && nb.started, "regress: base restarted");
    if (nb && nb.started) {
      const mixPos = nb.started[0] - (mix.started[0] - mix.started[1]);
      check(near(nb.started[1], mixPos, 0.001), "regress: restarted base aligned with premix timeline");
    }
    M.gain([["2", 1.0]]);
    await advance(0.3);
    check(nb && nb.stopped && near(M.mb(), ONE), "regress: back to phase 2 releases base again (" + M.mb().toFixed(1) + ")");
  }
  // ---- 3. 预混文件缺失：退回旧行为（p2 原文件，两份同驻、底层不停）
  {
    const { M, sources, fetched, flush, advance } = run({ noMix: true });
    M.play([["1", P1, 0, 0, LEN, 1.0]]);
    await flush();
    M.play([["2", P2, 5, 0, LEN, 1.0]]);
    await flush();
    await advance(0.5);
    check(fetched.includes(P2) && !sources[0].stopped && near(M.mb(), 2 * ONE), "no premix file: falls back to raw p2 (" + M.mb().toFixed(1) + ")");
  }
  // ---- 4. ?muspremix=0 关掉：同旧行为
  {
    const { M, sources, fetched, flush, advance } = run({ search: "?muspremix=0" });
    M.play([["1", P1, 0, 0, LEN, 1.0]]);
    await flush();
    M.play([["2", P2, 5, 0, LEN, 1.0]]);
    await flush();
    await advance(0.5);
    check(!fetched.includes("music_suno_final_p12_mono.m4a") && !sources[0].stopped, "muspremix=0 keeps old behaviour");
  }
  // ---- 5. 上下文挂起（静音自动播放 / 切后台 / iOS 打断）：时钟不走也要放掉 p1（11-11 网页仿真里一直两份同驻）
  {
    const { M, sources, flush, advance } = run({ suspended: true });
    M.play([["1", P1, 0, 0, LEN, 1.0]]);
    await flush();
    await advance(5);
    M.play([["2", P2, 5, 0, LEN, 1.0]]);
    await flush();
    await advance(0.5);
    check(sources[0].stopped && near(M.mb(), ONE), "suspended context still releases base (" + M.mb().toFixed(1) + ")");
  }
  console.log("WEB MUSIC failures=" + failures);
  process.exit(failures ? 1 : 0);
}
main();
