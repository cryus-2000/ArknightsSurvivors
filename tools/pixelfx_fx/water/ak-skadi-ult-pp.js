// 斯卡蒂终结技「斩浪」转平面（docs/246 §16，开关 ult/px_plane）：只换画面，分镜 / 时序 / 判定照原终结技（ult_moves_b._sd_*，docs/199 §7.16）：
//   起手（windup 慢放 0.5 真实秒）：大剑举到头顶，刃上一道冰蓝光从剑根走到剑尖，四周水珠往剑尖收；
//   下劈（招式 0.12 秒）：一道巨型竖劈月牙从头顶劈到身前地面，地上沿出手方向裂开一道发冰蓝光的长裂痕；
//   推浪（0.15 秒起，0.8 秒推完判定）：身前立起一道碎浪（不是墙：浪冠一段段高低错落、有断口，浪唇白沫往前卷），压着往前推；
//   劈浪（浪头到前方 520 世界像素）：冲击帧（整屏白 + 黑剪影，游戏里 ult 自己画，不改）→ 一道剑光顺着出手方向把浪从中间劈开 →
//   两半往两侧滑开、塌成碎沫 → 劈口炸起水柱、水珠落地 → 收尾：劈过的那段留稀疏湿痕和碎沫，慢慢收掉。
// 两层：up 立起层（剑光、浪、水柱、水珠）/ gd 贴地层（裂痕、浪前阴影、湿痕、碎沫，按 SY 压扁）。1 像素 = 1 美术像素 = 2 世界像素。
// 色：本人深海蓝 8 阶 + 点缀冰蓝 #c4dcff；同一招主元素：剑光 / 浪 / 水，不加别的。
import { fit, clamp, smooth, ease, noise, noise2, TAU, hex, WHITE } from "../../core/index.js";
import { crown, dotA } from "./ak-skadi-pp.js";   // 水花冠：和普攻 / 技能同一画法（11-05 用户否掉实心冰块柱）

export const meta = {
  name: "Skadi ult plane",
  desc: "Skadi's ultimate (wave cleave) redrawn on the 3/4 top-down plane: raised greatsword charge, giant overhead cleave, a broken tide pushing forward, split by a sword light into two collapsing halves with water spouts.",
  tags: ["water", "slash", "topdown", "skadi", "ultimate", "one-shot"],
  size: [1120, 700],
  origin: [560, 360],
  duration: 1.6,
  loop: false,
  fps: 15,
  bg: "dark",
  options: {
    palette: ["#081226", "#1b325c", "#30508e", "#446ec0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"],
    accent: "#c4dcff",
    part: "ult",       // ult 招式本体（t = 出招后秒数）/ charge 起手（t = 起手真实秒，0..0.5）
    layer: "up",       // up / gd
    dir: 0,            // 出手平面角（度）
    HW: 230,           // 浪半宽（美术像素；判定 ult/sd_w 920 世界 / 2 / 2）
    H: 58,             // 浪高
    CRASH: 260,        // 劈浪位置（ult/sd_crash_x 520 世界 / 2）
    T: 0.8, T0: 0.15, BACK: 100, L: 750,   // 浪头 F(t)：同 _sd_step（世界值 / 2）
    SY: 0.72,
    seed: 5,
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;
const VS_PIV = 22;

// 浪头前沿离脚底的距离（美术像素），同 _sd_step：F = −back + (L + back)·k·(1.35 − 0.35k)
function front(o, t) {
  const k = clamp((t - +o.T0) / +o.T);
  return -+o.BACK + (+o.L + +o.BACK) * k * (1.35 - 0.35 * k);
}
function crashT(o) {
  let t = +o.T0;
  while (t < 2 && front(o, t) < +o.CRASH) t += 0.002;
  return t;
}

// 平面坐标 → 画布：沿出手方向 a、侧向 l（右手侧为正）、离地 z
function P(o, a, l, z = 0) {
  const th = +o.dir * D2R, SY = +o.SY;
  const fx = Math.cos(th), fy = Math.sin(th), nx = -fy, ny = fx;
  return [fx * a + nx * l, (fy * a + ny * l) * SY - z];
}

// ---------------------------------------------------------------- 起手：剑举过头顶，冰蓝光沿刃走到剑尖，水珠往剑尖收
function charge(p, t, o, C, ACC) {
  const n = C.length, k = clamp(t / 0.5), th = +o.dir * D2R;
  if (o.layer === "gd") {   // 脚下一圈水往里收（贴地，压扁，断续）
    const r = 46 * (1 - ease.inQuad(k)) + 10, SY = +o.SY;
    for (let a = 0; a < TAU; a += 1.2 / r) {
      if (nz(a * 4.1, o.seed + 11) < 0.45) continue;
      const x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
      p.px(Math.round(x), Math.round(y), C[k > 0.7 ? n - 3 : n - 5]);
    }
    return;
  }
  // 蓄力点在她头顶上方（剑举起的位置随干员帧条变，不画剑身刃光，免得和帧条里的剑对不上）
  const tx = -Math.cos(th) * 6, ty = -VS_PIV - 24;
  if (k > 0.3) {   // 一道竖直的冰蓝细光从肩往上长到蓄力点
    const g = ease.outCubic(clamp((k - 0.3) / 0.45));
    for (let z = 0; z <= 22 * g; z += 0.5) p.px(Math.round(tx), Math.round(-VS_PIV - 2 - z), z > 22 * g - 3 ? WHITE : ACC);
  }
  if (k > 0.72) {   // 蓄力点星芒（十字，长短跳一拍）
    const m = k > 0.9 ? 7 : 4;
    for (let i = -m; i <= m; i++) {
      const c = Math.abs(i) <= 1 ? WHITE : Math.abs(i) <= m - 2 ? ACC : C[n - 3];
      p.px(Math.round(tx) + i, Math.round(ty), c);
      p.px(Math.round(tx), Math.round(ty) + i, c);
    }
    p.light(tx, ty, ACC, 0.9);
  }
  // 水珠往剑尖收（8 颗，起点按序号散布，越近越亮）
  for (let i = 0; i < 9; i++) {
    const a = i * 2.39996 + 0.5, r0 = 60 + 22 * nz(i * 1.7, o.seed + 13);
    const q = clamp((k - 0.05 * (i % 3)) / 0.8);
    if (q <= 0 || q >= 1) continue;
    const e = ease.inCubic(q), r = r0 * (1 - e);
    const x = tx + Math.cos(a) * r, y = ty + Math.sin(a) * r * 0.8 + 6 * (1 - e);
    const c = q > 0.75 ? WHITE : q > 0.4 ? ACC : C[n - 3];
    p.px(Math.round(x), Math.round(y), c);
    if (q < 0.7) p.px(Math.round(x - Math.cos(a) * 1.5), Math.round(y - Math.sin(a) * 1.2), C[n - 4]);   // 拖一格尾
  }
}

// ---------------------------------------------------------------- 下劈：巨型竖劈月牙（S1 竖斩放大 2.4 倍）
function cleave(p, t, o, C, ACC) {
  const t0 = 0.06, tt = t - t0;   // 0.06 起刀、0.12 落地（判定那一帧）
  if (tt < 0) return;
  const n = C.length, th = +o.dir * D2R, SY = +o.SY, Rv = 118, W = 30;
  const p0 = 125 * D2R, p1 = -10 * D2R, span = p0 - p1;
  const head = p0 - span * clamp(tt / 0.06), tail = p0 - span * 0.3 * smooth(0.06, 0.24, tt);
  const hot = tt < 0.12, cool = smooth(0.08, 0.34, tt);
  if (cool >= 0.75 || tail - head < 0.03) return;
  for (let ph = head; ph <= tail; ph += 0.3 / Rv) {
    const u = (tail - ph) / Math.max(0.001, tail - head);
    const wr = W * (1 - 0.7 * cool) * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.5)), 0.7);
    if (wr < 0.8) continue;
    for (let d = 0; d <= wr; d += 0.5) {
      const r = Rv - d, hz = r * Math.cos(ph), z = VS_PIV + r * Math.sin(ph);
      if (z < 0) continue;
      const q = d / wr;
      let ci = q < 0.12 ? n - 1 : q < 0.35 ? n - 2 : q < 0.6 ? n - 3 : q < 0.85 ? n - 4 : n - 5;
      if (hot && u > 0.75 && q < 0.5) ci = n - 1;
      ci = clamp(ci - Math.round(cool * 3), 1, n - 1);
      let col = C[ci];
      if (q > 0.12 && q < 0.2 && !hot) col = ACC;   // 刃口内侧一线冰蓝
      p.px(Math.round(Math.cos(th) * hz), Math.round(Math.sin(th) * hz * SY - z), col);
    }
  }
}

// 下劈地面：落点前方一条长直裂（白热 → 冰蓝芯，收得慢）+ 落地一圈矮水圈（压扁、断续）
function cleaveGround(p, t, o, C, ACC) {
  const n = C.length, SY = +o.SY, tt = t - 0.12;
  if (tt < 0) return;
  const grow = ease.outCubic(clamp(tt / 0.12)), fade = smooth(0.5, 1.3, t), glow = 1 - smooth(0.2, 0.9, t);
  if (fade < 0.99) {
    const a0 = 30, a1 = 30 + 190 * grow;
    for (let a = a0; a <= a1; a += 0.5) {
      if (nz(a * 0.7, o.seed + 41) < fade) continue;
      const j = 3 * (nz(a * 0.3, o.seed + 43) - 0.5) * 2 * (a / 220);
      const [x, y] = P(o, a, j);
      const w = a < 90 ? 1 : 0;   // 近端宽一格
      for (let s = -1 - w; s <= 1 + w; s++) p.px(Math.round(x), Math.round(y) + s, Math.abs(s) <= w - 0 && Math.abs(s) < 1 + w ? (tt < 0.1 ? WHITE : glow > 0.1 && nz(a * 1.3, o.seed + 45) > 0.2 * (1 - glow) ? ACC : C[1]) : C[0]);
      if (nz(a * 0.25, o.seed + 47) > 0.86) {   // 分叉
        const sg = nz(a, o.seed + 49) > 0.5 ? 1 : -1;
        for (let s = 1; s <= 5; s++) { const [bx, by] = P(o, a + s * 0.8, j + sg * s * 1.2); p.px(Math.round(bx), Math.round(by), s <= 2 && glow > 0.2 ? ACC : C[0]); }
      }
    }
    if (tt < 0.1) p.light(...P(o, 70, 0), ACC, 1.0);
  }
  // 落地水圈
  const rr = 30 + 70 * ease.outCubic(clamp(tt / 0.3)), rf = smooth(0.15, 0.4, tt);
  if (rf < 0.99) for (let a = -1.9; a <= 1.9; a += 0.8 / rr) {
    if (nz(a * 5, o.seed + 51) < 0.3 + 0.6 * rf) continue;
    const [x, y] = P(o, 70 + Math.cos(a) * rr * 0.6, Math.sin(a) * rr);
    p.px(Math.round(x), Math.round(y), C[rf < 0.3 ? n - 2 : n - 4]);
  }
}

// ---------------------------------------------------------------- 浪：一根根浪柱（侧向每 1 像素一根），高度按「几段浪冠 + 断口」起伏
function waveCols(o) {
  const HW = +o.HW, H = +o.H, cols = [];
  for (let l = -HW; l <= HW; l += 1) {
    const e = Math.min(1, (HW - Math.abs(l)) / (HW * 0.18));           // 两端收
    const seg = Math.sin(l / HW * Math.PI * 3.3 + 1.1) * 0.5 + 0.5;    // 几段浪冠
    const fine = nz(l * 0.09, o.seed + 61);
    let h = H * (0.28 + 0.62 * Math.pow(seg, 1.4) + 0.18 * fine) * Math.pow(e, 0.6);   // 几个浪峰高、峰间低（不是一样高的墙）
    const gap = nz(l * 0.045, o.seed + 63);                              // 断口：浪冠塌下去的地方
    if (gap < 0.25) h *= 0.3 + gap * 2.0;
    const lag = 10 * (nz(l * 0.02, o.seed + 65) - 0.5) + 6 * (1 - e);  // 浪线不直：有前有后
    cols.push({ l, h, lag, ph: nz(l * 0.13, o.seed + 67) });
  }
  return cols;
}

function wave(p, t, o, C, ACC) {
  const n = C.length, tc = crashT(o), T0 = +o.T0;
  if (t < T0) return;
  const F0 = front(o, t), F = Math.max(40, Math.min(F0, +o.CRASH + 6));   // 浪从她身前 40 处立起（判定前沿起点在身后，画面不画到她身上）
  const rise = 0.12 + 0.88 * ease.inOutQuad(clamp((t - T0) / 0.3));
  const curl = smooth(T0 + 0.05, T0 + 0.25, t);
  const ac = t - tc;                                                     // 劈浪后
  const pre = ac < 0 ? smooth(-PRE, 0, ac) : 0;                          // 炸开前 2 拍：往劈口中心收
  const split = ac > 0 ? ease.outCubic(clamp(ac / SHOCK_T)) : 0;         // 两半和冲击环同步往外
  const brk = ac > 0 ? smooth(0.0, 0.22, ac) : 0;   // 两半随冲击环塌平（别留一道直的浪线）
  if (brk >= 0.98) return;
  const cols = waveCols(o).map((c) => {
    const side = c.l >= 0 ? 1 : -1;
    return Object.assign({}, c, { a: F - c.lag + 10 * pre * (1 - Math.abs(c.l) / +o.HW), ll: c.l * (1 - 0.14 * pre) + side * 110 * split, side, pre });
  }).filter((c) => !(ac > 0 && Math.abs(c.l) < 4 + 70 * split));      // 劈口
  // 远的先画（屏幕 y 小的先）
  cols.sort((A, B) => P(o, A.a, A.ll)[1] - P(o, B.a, B.ll)[1]);
  const th = +o.dir * D2R;
  const near = (side) => Math.sin(th);                                   // 浪脸朝向镜头的程度（朝下出手 = 朝镜头）
  for (const c of cols) {
    let hb = c.h * rise * (1 - 0.9 * brk) * (1 + 0.06 * Math.sin(t * 18 + c.ph * 9)) * (1 + 0.18 * c.pre);
    if (hb < 1) continue;
    const fwd = 2 * ac > 0 ? 0 : 0;
    // ① 背坡：从浪后贴地缓升到浪顶
    const B = hb * 1.6;
    for (let sb = -B; sb <= 0; sb += 0.5) {
      const u = (sb + B) / B, z = hb * Math.pow(u, 1.7);
      if (u < 0.3 && nz(sb * 2 + c.l * 0.7, o.seed + 71) < 0.55) continue;
      const uj = u + 0.08 * (nz(c.l * 0.11 + u * 3, o.seed + 73) - 0.5);   // 色带边缘抖一格，不画横纹
      let ci = uj < 0.35 ? n - 6 : uj < 0.65 ? n - 5 : uj < 0.88 ? n - 4 : n - 3;
      const [x, y] = P(o, c.a + sb, c.ll, z);
      p.px(Math.round(x), Math.round(y), C[clamp(ci - Math.round(brk * 2), 1, n - 1)]);
    }
    // ② 前脸：浪顶往前探的凹弧
    for (let z = 0; z <= hb; z += 0.5) {
      const k = z / hb, off = curl * hb * 0.62 * k * k * k;   // 浪顶往前探出更多（卷浪），浪脚收回
      if (k < 0.15 && nz(z * 2 + c.l * 0.9, o.seed + 75) < 0.5) continue;
      const kj = k + 0.12 * (nz(c.l * 0.05, o.seed + 77) - 0.5);
      let ci = kj > 0.88 ? n - 1 : kj > 0.62 ? n - 3 : kj > 0.32 ? n - 4 : n - 5;
      if (near() > 0.3 && k <= 0.88) ci += 1;
      if (near() < -0.3 && k <= 0.88) ci -= 2;
      const [x, y] = P(o, c.a + off, c.ll, z);
      p.px(Math.round(x), Math.round(y), C[clamp(ci - Math.round(brk * 2), 1, n - 1)]);
    }
    // ③ 浪唇白沫：浪顶往前卷出一截（连续，每根长短不一）；浪顶点缀冰蓝
    if (curl > 0 && brk < 0.5 && hb >= 3) {
      const L = 2 + 9 * curl * (0.4 + c.ph) * (hb / +o.H + 0.3);
      for (let s = 0; s <= L; s += 0.5) {
        const u = s / L;
        const [x, y] = P(o, c.a + hb * 0.62 * curl + s, c.ll, hb + 1 - u * u * 6);
        p.px(Math.round(x), Math.round(y), u < 0.55 ? WHITE : u < 0.8 ? ACC : C[n - 2]);
      }
    }
  }
  // ④ 浪冠飞沫：浪冠前方一排小水珠往前飞、落下（劈浪前）
  if (ac < 0.05) for (let i = 0; i < 46; i++) {
    const l = -+o.HW * 0.9 + (+o.HW * 1.8) * nz(i * 3.3 + Math.floor(t * 15) * 0.7, o.seed + 81);
    const age = ((t * 15 + i * 0.37) % 3) / 15;
    const [x, y] = P(o, F + 6 + 70 * age, l, +o.H * rise * (0.7 + 0.3 * nz(i, o.seed + 83)) + 40 * age - 380 * age * age);
    p.px(Math.round(x), Math.round(y), age < 0.07 ? WHITE : C[n - 3]);
  }
}

// 劈浪：剑光一道顺着出手方向从身前劈到浪后（一帧到位，白 → 冰蓝 → 收）
function crashBlade(p, t, o, C, ACC) {
  const tc = crashT(o), ac = t - tc, n = C.length;
  if (ac < 0 || ac > 0.26) return;
  const a0 = 30, a1 = +o.CRASH + 80, w = ac < 0.07 ? 4 : ac < 0.14 ? 3 : 1;
  for (let a = a0; a <= a1; a += 0.5) {
    const u = (a - a0) / (a1 - a0), ww = w * Math.sin(Math.PI * Math.pow(u, 0.8));
    for (let s = -ww; s <= ww; s += 0.5) {
      const [x, y] = P(o, a, s, 26 + 10 * u);
      const q = Math.abs(s) / Math.max(0.5, ww);
      p.px(Math.round(x), Math.round(y), ac < 0.07 ? (q < 0.6 ? WHITE : ACC) : q < 0.4 ? ACC : C[n - 3]);
    }
  }
  if (ac < 0.1) p.light(...P(o, +o.CRASH, 0, 30), WHITE, 1.0);
}

// ---------------------------------------------------------------- 劈口水爆（11-05 用户「新版本主要是缺少最后的爆炸的冲击力」「爆炸是冲击力最为关键的部分」）
// 预备（炸开前 2 拍）：浪往劈口中心收、水往里吸、周围压暗 → 爆点：实心亮核（白芯裹冰蓝，亮 2 拍，约判定一半大）→
// 冲击波：一圈压扁的厚水环 0.25 秒（约 4 拍）推到判定边缘，推过的地面闪一下，环边甩出大水团和水滴；落水水爆 / 浪的两半和环同步往外。
// 游戏里冲击帧（整屏白 + 黑剪影，ult 自己画）落在爆点第 0 拍上、顿帧期间招式时间不走，所以亮核两拍在冲击帧之后照样看得到。
const PRE = 0.134, SHOCK_T = 0.25, CORE_R = 64;
function boomC(o) { return [+o.CRASH + 10, 0]; }           // 爆心（平面：沿出手方向 a、侧向 l）
function shockR(o, ac) { return 26 + (+o.HW - 26) * ease.outCubic(clamp(ac / SHOCK_T)); }
// 冲击环到达平面距离 r 的时刻（落水水爆 / 水团按它出发）
function shockAt(o, r) { const f = clamp((r - 26) / (+o.HW - 26)); return SHOCK_T * (1 - Math.cbrt(1 - f)); }

function boomUp(p, t, o, C, ACC) {
  const tc = crashT(o), ac = t - tc, n = C.length, [ba, bl] = boomC(o);
  // 预备：16 颗水珠往爆心吸（离地 6–20），越近越亮
  if (ac < 0 && ac > -PRE) {
    const q = 1 + ac / PRE;
    for (let i = 0; i < 16; i++) {
      const a = i * 2.39996, r0 = 70 + 50 * nz(i * 1.3, o.seed + 401), r = r0 * (1 - ease.inQuad(q));
      const [x, y] = P(o, ba + Math.cos(a) * r, bl + Math.sin(a) * r, 6 + 14 * nz(i * 2.1, o.seed + 403));
      p.px(Math.round(x), Math.round(y), q > 0.6 ? WHITE : ACC);
      p.px(Math.round(x - Math.cos(a) * 1.5), Math.round(y), C[n - 3]);
    }
  }
  if (ac < 0) return;
  // 爆点亮核：两拍实心（白芯 55%、冰蓝环、海蓝外缘，外缘有起伏），第 3 拍缩成一圈冰蓝亮边、第 4 拍散
  const beat = Math.floor(ac * 15 + 1e-6);
  if (beat <= 3) {
    const R = CORE_R * [0.92, 1.0, 0.8, 0.55][beat], zc = 18;
    const [cx, cy] = P(o, ba, bl, zc);
    const hollow = beat >= 2 ? [0, 0, 0.62, 0.8][beat] : 0;
    for (let y = -R * 0.7; y <= R * 0.7; y += 1) for (let x = -R; x <= R; x += 1) {
      const a = Math.atan2(y / 0.7, x), rr = R * (0.9 + 0.1 * nz(a * 3 + beat, o.seed + 405));
      const d = Math.hypot(x, y / 0.7) / rr;
      if (d > 1 || d < hollow) continue;
      const c = beat <= 1 ? (d < 0.55 ? WHITE : d < 0.85 ? ACC : C[n - 3]) : d < hollow + 0.12 ? WHITE : d < 0.9 ? ACC : C[n - 3];
      p.px(Math.round(cx + x), Math.round(cy + y), c);
    }
    if (beat <= 1) p.light(cx, cy, WHITE, 1.0);
  }
  // 冲击环的立起浪唇（前半圈、矮）+ 环边甩出的大水团 / 水滴
  const rs = shockR(o, ac), ff = smooth(SHOCK_T * 0.8, SHOCK_T + 0.18, ac);
  if (ff < 0.99) for (let a = 0; a < TAU; a += 0.8 / rs) {
    const q = nz(a * 3.3, o.seed + 407);
    if (q < 0.2 + 0.7 * ff) continue;
    const h = (3 + 5 * nz(a * 6.1, o.seed + 409)) * (1 - ff);
    for (let z = 0; z <= h; z += 1) {
      const [x, y] = P(o, ba + Math.cos(a) * (rs + z * 0.5), bl + Math.sin(a) * (rs + z * 0.5), z);
      p.px(Math.round(x), Math.round(y), z >= h - 1 ? WHITE : z > h * 0.5 ? C[n - 2] : C[n - 3]);
    }
  }
  for (const b of shockBlobs(o)) {
    const u = ac - b.t0;
    if (u <= 0 || u >= b.T) continue;
    const r = b.r0 + b.v * u, z = b.vz * u - 260 * u * u;
    const [x, y] = P(o, ba + Math.cos(b.a) * r, bl + Math.sin(b.a) * r, z);
    const c = u < 0.06 ? WHITE : z > 12 ? C[n - 2] : C[n - 3];
    for (let dx = 0; dx < b.sz; dx++) for (let dy = 0; dy < b.sz; dy++) p.px(Math.round(x) + dx, Math.round(y) + dy, dy === 0 && dx < b.sz - 1 ? c : C[n - 3]);
  }
}

// 环边甩出的水团（3 格大团 + 2 格水滴，共 14）：冲击环推到它那里才出发
function shockBlobs(o) {
  const out = [], HW = +o.HW;
  for (let i = 0; i < 14; i++) {
    const a = (i + 0.6 * nz(i * 1.9, o.seed + 411)) / 14 * TAU;
    const r0 = HW * (0.35 + 0.5 * nz(i * 2.7, o.seed + 413));
    const vz = 80 + 60 * nz(i * 3.9, o.seed + 415);
    out.push({ a, r0, t0: shockAt(o, r0), v: 90 + 80 * nz(i * 5.1, o.seed + 417), vz, T: 2 * vz / 520, sz: i % 3 === 0 ? 3 : 2 });
  }
  return out;
}

function boomGround(p, t, o, C, ACC) {
  const tc = crashT(o), ac = t - tc, n = C.length, [ba, bl] = boomC(o), HW = +o.HW;
  // 预备：爆心周围压暗（统一透明度），留出对比；爆点后 0.15 秒退掉
  const dk = ac < 0 ? smooth(-PRE, 0, ac) : 1 - smooth(0, 0.15, ac);
  if (dk > 0.02) for (let y = -150 * +o.SY; y <= 150 * +o.SY; y += 1) for (let x = -150; x <= 150; x += 1) {
    if (x * x + (y / +o.SY) * (y / +o.SY) > 150 * 150) continue;
    const [cx, cy] = P(o, ba, bl);
    dotA(p, Math.round(cx + x), Math.round(cy + y), C[0], 0.32 * dk);
  }
  if (ac < 0) return;
  // 冲击环：压扁的厚水环（实色三阶 + 白外沿，不规则浪唇），推过的地面闪一下（环后 26 美术像素宽一圈浅色，统一透明度）
  const rs = shockR(o, ac), ff = smooth(SHOCK_T * 0.8, SHOCK_T + 0.2, ac), th = 7 * (1 - 0.5 * ease.outCubic(clamp(ac / SHOCK_T)));
  if (ff < 0.99) for (let a = 0; a < TAU; a += 0.7 / rs) {
    const q = nz(a * 3.3, o.seed + 407);
    if (q < 0.15 + 0.7 * ff) continue;
    const lip = rs * (1 + 0.05 * (nz(a * 7.7, o.seed + 419) - 0.5) * 2);
    for (let d = -th; d <= 1; d += 0.5) {
      const [x, y] = P(o, ba + Math.cos(a) * (lip + d), bl + Math.sin(a) * (lip + d));
      const c = d > -0.6 ? WHITE : d > -th * 0.4 ? C[n - 2] : d > -th * 0.75 ? C[n - 3] : C[n - 4];
      p.px(Math.round(x), Math.round(y), c);
    }
    if (ac < SHOCK_T + 0.05) for (let d = th; d <= th + 26; d += 1) {   // 推过的地面闪一下
      const [x, y] = P(o, ba + Math.cos(a) * (lip - d), bl + Math.sin(a) * (lip - d));
      dotA(p, Math.round(x), Math.round(y), C[n - 3], 0.35 * (1 - (d - th) / 26) * (1 - smooth(0, SHOCK_T + 0.05, ac)));
    }
  }
  // 水团的地面影子 + 落地白点
  for (const b of shockBlobs(o)) {
    const u = ac - b.t0;
    if (u <= 0) continue;
    const fl = Math.min(u, b.T), r = b.r0 + b.v * fl;
    const [x, y] = P(o, ba + Math.cos(b.a) * r, bl + Math.sin(b.a) * r);
    if (u < b.T) for (let dx = 0; dx < b.sz; dx++) dotA(p, Math.round(x) + dx, Math.round(y), C[0], 0.55);
    else if (u < b.T + 0.2) for (let dx = 0; dx < b.sz; dx++) p.px(Math.round(x) + dx, Math.round(y), u < b.T + 0.07 ? WHITE : C[n - 3]);
  }
}

// 水柱：劈口一路炸起（劈浪处两侧各 2–3 根大的 + 往她身前 3 根越来越小的），先冲高后散成水珠落下
function spouts(o) {
  const HW = +o.HW, CR = +o.CRASH, s = [];
  const L = [[-0.55, 0.02, 1.0], [-0.28, 0.0, 0.85], [0.32, 0.05, 0.95], [0.62, 0.09, 0.75], [-0.8, 0.12, 0.6]];
  for (const [f, dl, k] of L) s.push({ a: CR + 10 + 30 * nz(f * 9, o.seed + 91), l: f * HW, dl, H: 70 * k, W: 9 * k + 3 });
  for (let q = 0; q < 3; q++) s.push({ a: CR - 60 - 60 * q, l: (nz(q * 4.4, o.seed + 93) - 0.5) * 36, dl: 0.04 + 0.05 * q, H: 52 - 10 * q, W: 7 - q });
  const [ba, bl] = boomC(o);
  for (const q of s) q.dl = shockAt(o, Math.hypot(q.a - ba, q.l - bl));   // 和冲击环同步：环推到哪、哪里炸
  return s;
}

function spoutUp(p, t, o, C, ACC, gd = false) {   // 劈浪落水水爆（贴地为主，同普攻 / 技能 crown）
  const tc = crashT(o);
  for (const [i, s] of spouts(o).entries()) {
    const [x, y] = P(o, s.a, s.l);
    crown(p, t - tc - s.dl, C, ACC, { x, y, W: s.W * 2.4, H: 16, SY: +o.SY, seed: +o.seed * 13 + i * 17, layer: gd ? "gd" : "up", nd: s.H > 60 ? 14 : s.H > 45 ? 11 : 8 });
  }
}

// 地面：浪前一条贴地暗影（浪压过来）+ 浪后湿痕（稀疏暗色带孔，别成色板）+ 劈浪后两侧碎沫摊开，慢慢收
function waveGround(p, t, o, C, ACC) {
  const n = C.length, tc = crashT(o), T0 = +o.T0, HW = +o.HW;
  if (t < T0) return;
  const F = Math.max(14, Math.min(front(o, t), +o.CRASH + 6)), ac = t - tc;
  const rise = clamp((t - T0) / 0.25);
  if (ac < 0.05) for (let l = -HW; l <= HW; l += 1) {   // 浪前暗影（浪脚贴地的深色细带）
    const e = Math.min(1, (HW - Math.abs(l)) / (HW * 0.18));
    for (let d = 2; d <= 2 + 6 * rise * e; d += 1) {
      if (nz(l * 0.3 + d, o.seed + 111) < 0.35) continue;
      const [x, y] = P(o, F + d, l);
      p.px(Math.round(x), Math.round(y), C[0]);
    }
  }
  // 湿痕：浪拖过去留下十几道顺着出手方向的断续水纹（稀疏，不铺色板）；劈浪后 1.1 秒收完
  const wf = ac > 0 ? smooth(0.2, 1.15, ac) : 0;
  if (wf < 0.99) for (let i = 0; i < 26; i++) {
    const l = -HW * 0.92 + HW * 1.84 * ((i + 0.5 * nz(i * 2.1, o.seed + 113)) / 26);
    const a0 = 24 + 40 * nz(i * 1.3, o.seed + 114), a1 = F - 10 - 30 * nz(i * 3.7, o.seed + 116);
    for (let a = a0; a <= a1; a += 1) {
      const nn = nz(a * 0.12 + i * 9.1, o.seed + 118);
      if (nn < 0.45 + 0.5 * wf) continue;
      const [x, y] = P(o, a, l + 2 * (nz(a * 0.05 + i, o.seed + 120) - 0.5));
      p.px(Math.round(x), Math.round(y), nn > 0.9 ? C[3] : C[1]);
    }
  }
  // 劈浪后：浪脚碎沫往前 / 两侧摊开
  if (ac > 0) {
    const sp = ease.outCubic(clamp(ac / SHOCK_T)), ff = smooth(0.3, 1.1, ac);
    if (ff < 0.99) for (let l = -HW; l <= HW; l += 1) {
      if (Math.abs(l) < 30) continue;
      const side = l >= 0 ? 1 : -1, reach = (10 + 40 * nz(l * 0.07, o.seed + 115)) * sp;
      for (let s = 0; s <= reach; s += 1) {
        const [x, y] = P(o, +o.CRASH + s - 8, l + side * 50 * sp * (s / Math.max(1, reach)));
        const nn = noise2(x * 0.35, y * 0.5, o.seed + 117) * 0.5 + 0.5;
        const thr = 0.35 + 0.55 * ff + 0.2 * s / Math.max(1, reach);
        if (nn < thr) continue;
        p.px(Math.round(x), Math.round(y), nn > thr + 0.22 ? WHITE : nn > thr + 0.1 ? ACC : C[n - 4]);
      }
    }
  }
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  if (o.part === "charge") return charge(p, t, o, C, ACC);
  if (gd) {
    cleaveGround(p, t, o, C, ACC);
    waveGround(p, t, o, C, ACC);
    boomGround(p, t, o, C, ACC);
    spoutUp(p, t, o, C, ACC, true);
    return;
  }
  wave(p, t, o, C, ACC);
  cleave(p, t, o, C, ACC);
  crashBlade(p, t, o, C, ACC);
  boomUp(p, t, o, C, ACC);
  spoutUp(p, t, o, C, ACC);
}
