// 歌蕾蒂娅「转平面」（docs/263，开关 fx/px_plane）：pixelfx 画法，按本作俯视斜角重画（同 docs/246 斯卡蒂）。
// 一个文件按 part 出多种件；每种按 layer 分层导出：
//   up 立起层 —— 离地的东西（水刺、水柱、浪头、龙卷水墙），原点 = 脚底地面点，进单位层按 y 排序；
//   bk 立起层的「身后半圈」（S2 水环 / S3 龙卷的远半圈），游戏里排在中心点之后的更远处；
//   gd 贴地层 —— 地面上的东西（冲击环、湿痕、锚印、积水边），已按 SY（0.72）压扁，画在地面层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转。
// 色：本人深海蓝 7 阶（house.js OP.gladiia）+ 最暗压底一阶；精二点缀深渊紫（OP.gladiia_abyss）；S3 龙卷用 OP.gladiia_tide 冷白灰蓝（用户已过的龙卷版）。
// 不用危险红。同一招元素 ≤ 3。view: "raw" 出「旧做法」对照（不压扁、光晕烤进颜色，游戏里小数缩放贴上去）。
import { fit, clamp, smooth, ease, noise, noise2, TAU, hex, WHITE } from "../../core/index.js";

export const meta = {
  name: "Gladiia plane",
  desc: "Gladiia's hook, anchor and maelstrom moves redrawn for a 3/4 top-down plane: water spikes and splash crowns, flat ground ripples, a tide funnel, and squashed ground rings, wakes and anchor marks.",
  tags: ["water", "hook", "topdown", "gladiia", "one-shot"],
  size: [220, 230],
  origin: [110, 160],
  duration: 1.2,
  loop: false,
  fps: 15,   // 统一动画时钟：本作特效帧条一律 15 fps
  bg: "dark",
  options: {
    palette: ["#0d1a2e", "#182f51", "#294a78", "#3a65a0", "#4c80c7", "#8bacdb", "#c9d9ee", "#ffffff"],
    tide: ["#141c29", "#243246", "#3b4c64", "#5c7090", "#8798b3", "#b4c0d2", "#dbe2ec", "#f6f8fb"],
    accent: "#b3a8ee",
    accent2: "#7a6cc8",
    part: "hit",
    layer: "up",
    view: "plane",
    R: 38,
    H: 12,
    el: 0,
    big: 0,
    mode: "loop",
    dir: 0,
    span: 2.27,
    W: 12,
    SY: 0.72,
    dur: 0.42,
    seed: 3,
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1
const R0 = (v) => Math.round(v);

// 一根水刺：从 (x0, y0) 沿 a 方向长 l，根部宽 wb，往尖收；颜色 body / edge / tip
function spike(p, x0, y0, a, l, wb, cb, ce, ct) {
  const ca = Math.cos(a), sa = Math.sin(a), nx = -sa, ny = ca;
  for (let s = 0; s <= l; s += 0.5) {
    const k = s / Math.max(1, l), w = wb * (1 - k);
    const x = x0 + ca * s, y = y0 + sa * s;
    for (let q = -w / 2; q <= w / 2 + 0.01; q += 0.5) {
      const c = k > 0.8 ? ct : Math.abs(q) > w / 2 - 0.6 ? ce : cb;
      p.px(R0(x + nx * q), R0(y + ny * q), c);
    }
  }
}

function disc(p, cx, cy, r, fn) {
  for (let y = Math.floor(cy - r); y <= Math.ceil(cy + r); y++)
    for (let x = Math.floor(cx - r); x <= Math.ceil(cx + r); x++) {
      const d = Math.hypot(x - cx, y - cy);
      if (d <= r) { const c = fn(x - cx, y - cy, d / Math.max(0.5, r)); if (c !== undefined) p.px(x, y, c); }
    }
}

// ---------------------------------------------------------------- 钩索落地：水团 + 粗水刺（原作 glady_attack_01_hit 的深蓝水刺爆开）
// 精一：体量 ×1.2、多两根刺；精二（质变）：深渊紫的芯 + 中心冲起一道细水柱
function hit(p, t, o, C, A1, A2) {
  const R = +o.R, el = +o.el, n = C.length, raw = o.view === "raw";
  const k = [1, 1.2, 1.4][el], cy = -6;
  if (t < 0.067) {   // 第 0 拍：白热芯
    disc(p, 0, cy, 4 + el, (x, y, q) => (q < 0.6 ? WHITE : C[n - 2]));
    for (let i = 0; i < 6; i++) { const a = -Math.PI * (0.1 + 0.8 * i / 5); spike(p, 0, cy, a, 6 + R * 0.12 * k, 2, C[n - 2], C[n - 2], WHITE); }
    if (raw) p.light(0, cy, C[n - 2], 1.2);
    return;
  }
  const fade = smooth(0.15, 0.4, t);
  if (t < 0.34) {   // 水团（左上受光、右下暗边），越来越小
    const rl = (4 + el) * k * (1 - 0.6 * smooth(0.06, 0.3, t));
    disc(p, 0, cy, rl, (x, y, q) => {
      if (q > 0.85) return C[2];
      if (el >= 2 && q < 0.45) return q < 0.25 ? A1 : A2;   // 精二：深渊紫的芯
      return x + y < -rl * 0.4 ? C[5] : C[3];
    });
  }
  const N = 5 + 2 * el + (R > 45 ? 1 : 0), L = R * 0.42 * k;
  for (let i = 0; i < N; i++) {
    const a = -Math.PI * (-0.12 + 1.24 * (i + 0.8 * nz(i * 3.1, o.seed + 11)) / N) + (nz(i * 5.3, o.seed + 15) - 0.5) * 0.5, lj = 0.45 + 0.55 * nz(i * 1.7, o.seed + 13);
    const grow = ease.outCubic(clamp((t - 0.067) / 0.07 + 0.3)), l = L * lj * grow * (1 - 0.75 * fade);
    if (l >= 2) spike(p, Math.cos(a) * 2, cy + Math.sin(a) * 2, a, l, (1.8 + 1.6 * nz(i * 2.9, o.seed + 17) + el * 0.5) * (1 - 0.5 * fade), t < 0.13 ? C[5] : C[4], C[n - 3], t < 0.2 ? WHITE : C[n - 2]);
    if (t > 0.18) {   // 刺尖缩回、下垂成落地水珠
      const u = t - 0.18, tx = Math.cos(a) * L * lj, ty = cy + Math.sin(a) * L * lj;
      const x = tx + Math.cos(a) * 30 * u, y = ty + Math.sin(a) * 30 * u + 220 * u * u;
      if (y < 3) { p.px(R0(x), R0(y), u < 0.08 ? C[n - 2] : C[n - 3]); if (i % 2 === 0) p.px(R0(x) + 1, R0(y), C[n - 4]); }
    }
  }
  if (el >= 2) crown(p, t - 0.05, o, C, A1, { N: 12, H: 14, spread: 34, r0: 3, acc: true, seed: 5 });   // 精二：落点再炸开一小冠水花（深渊紫水滴）
  if (raw) p.light(0, cy, C[n - 3], 0.6 * (1 - fade));
}

function hitGround(p, t, o, C) {
  const R = +o.R, SY = o.view === "raw" ? 1 : +o.SY, n = C.length;
  if (t < 0.4) {   // 断续的冲击环（外沿亮、内侧一格暗）
    const r = R * (0.6 + 0.4 * ease.outCubic(clamp(t / 0.15)));
    const m = Math.ceil(r * TAU * 1.2), gone = smooth(0.2, 0.4, t);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 5.3, o.seed + 21) < 0.25 + 0.75 * gone) continue;
      const rr = r * (0.94 + 0.12 * nz(a * 9.1, o.seed + 23));
      p.px(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), t < 0.1 ? C[n - 2] : C[n - 3]);
      p.px(R0(Math.cos(a) * (rr - 1.5)), R0(Math.sin(a) * (rr - 1.5) * SY), C[1]);
    }
  }
  wet(p, t, R * 0.32, 0.5, o.seed + 25, C, SY);
}

// 一块不规则湿痕：按固定噪声成团消散（不抖动）
function wet(p, t, rb, life, sd, C, SY) {
  const gone = smooth(life * 0.4, life, t);
  if (gone >= 1) return;
  for (let y = Math.floor(-rb * SY) - 1; y <= Math.ceil(rb * SY) + 1; y++)
    for (let x = Math.floor(-rb) - 1; x <= Math.ceil(rb) + 1; x++) {
      const pz = y / SY, d = Math.hypot(x, pz), a = Math.atan2(pz, x);
      if (d > rb * (0.7 + 0.4 * nz(a * 3, sd))) continue;
      if (noise2(x * 0.32, y * 0.42, sd) * 0.5 + 0.5 < 0.25 + gone * 0.75) continue;
      p.px(x, y, d > rb * 0.75 ? C[1] : C[2]);
    }
}

// ---------------------------------------------------------------- 拖回到位：拍水（水冠 + 湿痕）；精一起地上一枚锚印（「锚定」眩晕）
function arrive(p, t, o, C, A1) {
  const big = +o.big, n = C.length, SY = +o.SY;
  const r0 = big ? 8 : 5, M = big ? 16 : 10, sp = big ? 26 : 18;
  if (t < 0.067) {   // 第 0 拍：扁的白色拍水
    for (let x = -r0 - 2; x <= r0 + 2; x++) { p.px(x, -1, WHITE); p.px(x, 0, C[n - 2]); }
    for (let x = -r0; x <= r0; x++) p.px(x, -2, C[n - 2]);
    return;
  }
  if (t < 0.36) {
    const u = t - 0.067;
    for (let i = 0; i < M; i++) {
      const a = (i + nz(i * 2.1, o.seed + 31)) / M * TAU, v = sp * (0.6 + 0.4 * nz(i * 1.3, o.seed + 33));
      const x = Math.cos(a) * (r0 + v * u), y = Math.sin(a) * (r0 + v * u) * SY - (70 * u - 330 * u * u) * (big ? 1.3 : 1);
      if (y > 2) continue;
      p.px(R0(x), R0(y), u < 0.07 ? WHITE : u < 0.15 ? C[n - 2] : C[n - 3]);
      if (big && i % 2 === 0) p.px(R0(x), R0(y) + 1, C[n - 4]);
    }
  }
}

const ANCHOR = [
  "..###..",
  "..#.#..",
  "..###..",
  "...#...",
  ".#####.",
  "...#...",
  "#..#..#",
  "##.#.##",
  ".#####.",
];

function arriveGround(p, t, o, C, A1) {
  const big = +o.big, el = +o.el, n = C.length, SY = +o.SY;
  wet(p, t, big ? 11 : 7, 0.6, o.seed + 41, C, SY);
  if (t < 0.3) {   // 两三道往外的溅痕
    for (let i = 0; i < (big ? 5 : 3); i++) {
      const a = (i + nz(i * 3.7, o.seed + 43)) / (big ? 5 : 3) * TAU, L = (big ? 12 : 7) * ease.outCubic(clamp(t / 0.12));
      for (let s = 2; s < L; s += 1) if (nz(s * 0.7 + i * 5, o.seed + 45) > 0.3 + smooth(0.1, 0.3, t))
        p.px(R0(Math.cos(a) * (r0(big) + s)), R0(Math.sin(a) * (r0(big) + s) * SY), s < L * 0.5 ? C[n - 3] : C[n - 4]);
    }
  }
  if (el >= 1 && t >= 0.05) {   // 锚印：亮一拍 → 钢蓝 → 0.8 秒后按噪声散掉
    const gone = smooth(0.8, 1.05, t), hot = t < 0.13;
    const H = ANCHOR.length, Wd = ANCHOR[0].length, s = big ? 2 : 1;
    for (let j = 0; j < H; j++) for (let i = 0; i < Wd; i++) {
      if (ANCHOR[j][i] !== "#") continue;
      for (let dy = 0; dy < s; dy++) for (let dx = 0; dx < s; dx++) {
        const x = (i - (Wd >> 1)) * s + dx, y = Math.round((j - H + 2) * s * SY) + dy;
        if (nz(x * 0.9 + 7, o.seed + y * 0.53) < gone) continue;
        const c = hot ? WHITE : (j < 3 ? C[n - 2] : el >= 2 && (j === 8) ? A1 : C[5]);
        for (const [ex, ey] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1]]) {   // 一格暗描边（先画，被本体盖住的不显）
          const ii = i + ex / s, jj = j + ey / s;
          if (!(ANCHOR[Math.round(jj)] && ANCHOR[Math.round(jj)][Math.round(ii)] === "#")) p.dot(x + ex, y + ey, C[0], 0.85);
        }
        p.px(x, y, c);
      }
    }
  }
}
const r0 = (big) => (big ? 8 : 5);

// ---------------------------------------------------------------- 水花冠（11-05 用户「水柱有点搞笑」：不做竖直水柱）：贴地炸开——
// 第 0 拍一块扁的白色拍水，随后一圈水滴有重量地往外上方甩出、受重力落回地面（落地成一点暗水），根部一圈不规整白沫；顶端不规则，没有柱身。
// N 水滴数、H 甩起的大致高度（美术像素）、spread 往外的速度、r0 起点半径；精二（acc）四分之一水滴点深渊紫
function crown(p, t, o, C, A1, k) {
  const n = C.length, SY = +o.SY, G = 420, N = k.N, H = k.H, sp = k.spread, r0 = k.r0, sd = (k.seed || 0) + o.seed;
  if (t < 0) return;
  if (t < 0.067) {   // 第 0 拍：扁的白色拍水
    const w = Math.round(r0 * (k.wide || 1)) + 3;
    for (let x = -w; x <= w; x++) { p.px(x, 0, WHITE); if (Math.abs(x) < w - 1) p.px(x, -1, C[n - 2]); }
    for (let i = 0; i < 5; i++) { const x = R0((nz(i * 2.7, sd + 301) - 0.5) * 2 * w); p.px(x, -2 - (i % 2), WHITE); }
    return;
  }
  const u = t - 0.067;
  for (let i = 0; i < N; i++) {
    const a = (i + 0.9 * nz(i * 2.1, sd + 303)) / N * TAU, q = nz(i * 1.3, sd + 305);
    const vz = Math.sqrt(2 * G * H) * (0.45 + 0.55 * q), vh = sp * (0.5 + 0.5 * nz(i * 3.7, sd + 307));
    const rr = r0 + vh * u, gx = Math.cos(a) * rr, gy = Math.sin(a) * rr * SY, z = vz * u - 0.5 * G * u * u;
    if (z < -0.5) {   // 落回地面：一点暗水，停一拍
      const tl = (2 * vz) / G;
      if (u - tl < 0.1) p.px(R0(Math.cos(a) * (r0 + vh * tl)), R0(Math.sin(a) * (r0 + vh * tl) * SY), C[3]);
      continue;
    }
    let c = u < 0.06 ? WHITE : vz - G * u > 0 ? C[n - 2] : C[n - 3];   // 上升亮、下落暗一阶
    if (k.acc && i % 4 === 1 && u >= 0.06) c = A1;
    const X = R0(gx), Y = R0(gy - z);
    p.px(X, Y, c);
    if (q > (k.big ? 0.25 : 0.6)) { p.px(X + 1, Y, C[n - 3]); if (k.big && q > 0.7) p.px(X, Y + 1, C[n - 4]); }   // 一部分是 2 格大水滴（重钩更多更大）
    if (u < 0.14) p.px(R0(gx - Math.cos(a) * 1.5), R0(gy - z + 1.5), C[4]);   // 刚甩出时拖一格尾
  }
  if (u < 0.22) {   // 根部一圈不规整白沫（贴地，不立起）
    const rf = r0 + sp * 0.12 * ease.outCubic(clamp(u / 0.15)), m = Math.ceil(rf * TAU);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU, qq = nz(a * 5.1, sd + 309);
      if (qq < 0.35 + smooth(0.08, 0.22, u) * 0.6) continue;
      p.px(R0(Math.cos(a) * rf), R0(Math.sin(a) * rf * SY - (qq > 0.8 ? 1 : 0)), qq > 0.7 ? WHITE : C[n - 3]);
    }
  }
}

// ---------------------------------------------------------------- 水波纹（精二「冲撞」/ 反震 / 扩散）：贴地压扁的细涟漪往外扩散后淡掉（11-05 用户「水波纹太像水墙」：不立起、不厚）
// gd：1 格细线（前沿 + 晚半拍的第二道），颜色低调，越外越暗、按噪声断开散掉；up：沿涟漪零星跳起的几点水沫（1–3 格高）；bk 空
function ringWave(p, t, o, C, A1, gd) {
  const R = +o.R, SY = o.view === "raw" ? 1 : +o.SY, n = C.length, el = +o.el, D = +o.dur;
  if (t > D || o.layer === "bk") return;
  for (const [dt, ks] of [[0, 1], [0.09, 0.78]]) {
    const tt = t - dt;
    if (tt < 0) continue;
    const k = ease.outCubic(clamp(tt / (D * 0.8))), r = R * ks * (0.25 + 0.75 * k), gone = smooth(D * 0.35, D, t);
    const m = Math.ceil(r * TAU * 1.1);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU, q = nz(a * 4.3 + dt * 9, o.seed + 51);
      if (q < 0.2 + 0.8 * gone) continue;
      const rr = r * (0.96 + 0.08 * nz(a * 7.7, o.seed + 53)), x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY;
      if (gd || o.view === "raw") {
        let c = k < 0.3 ? C[5] : k < 0.65 ? C[4] : C[3];
        if (dt > 0) c = C[3];
        if (el >= 2 && q > 0.93) c = A1;
        p.px(R0(x), R0(y), c);
      } else if (dt === 0 && q > 0.9 && tt < D * 0.6) {   // 零星跳起的水沫
        const hop = 3 * Math.sin(Math.PI * clamp(tt / (D * 0.6)));
        p.px(R0(x), R0(y - 1 - hop * nz(a * 13, o.seed + 55)), el >= 2 && q > 0.96 ? A1 : C[n - 3]);
      }
    }
  }
  if (o.view === "raw") p.light(0, 0, C[n - 3], 0.4 * (1 - t / D));
}

// ---------------------------------------------------------------- 回卷（S2 每次掷钩拉近身边 / 连携「聚拢」）：贴地的细涟漪往中心收、越收越快，身后拖几道往外的细水纹；big：汇到中心炸开一冠水花
function backwash(p, t, o, C, A1, gd) {
  const R = +o.R, SY = +o.SY, n = C.length, el = +o.el, D = +o.dur, spout = !!+o.big;
  if (o.layer === "bk") return;
  const g = ease.inCubic(clamp(t / D)), r = R * (1 - 0.8 * g);
  if (t < D) {
    const m = Math.ceil(r * TAU * 1.1);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU, q = nz(a * 3.3, o.seed + 71);
      if (q < 0.3) continue;
      const rr = r * (0.94 + 0.12 * nz(a * 6.1, o.seed + 73)), x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY;
      if (gd) {
        p.px(R0(x), R0(y), el >= 2 && q > 0.94 ? A1 : g < 0.4 ? C[4] : C[5]);
        if (q > 0.72) {   // 往外拖的细水纹（越收越快、纹越长）
          const L = 2 + 7 * g * nz(a * 9, o.seed + 75);
          for (let s = 2; s <= L; s += 1) p.px(R0(x + Math.cos(a) * s), R0(y + Math.sin(a) * SY * s), C[2]);
        }
      } else if (q > 0.9) {
        p.px(R0(x), R0(y - 1 - 2 * nz(a * 11, o.seed + 77)), C[n - 3]);
      }
    }
  }
  if (spout && t >= D - 0.03) {
    if (gd) hitGround(p, t - (D - 0.03), Object.assign({}, o, { R: R * 0.35 }), C);
    else crown(p, t - (D - 0.03), o, C, A1, { N: 22, H: +o.H2 || 30, spread: 70, r0: 4, seed: 11 });
  }
}

// 「水花冠」作为独立件（暗涌）
function geyserUp(p, t, o, C, A1) {
  const H = +o.H, el = +o.el;
  crown(p, t, o, C, A1, { N: 12 + 3 * el, H: H, spread: 30 + H * 0.8, r0: 3, acc: el >= 2, seed: 7 });
}

// S1「缺水的大洋裂断」重钩落地：一大冠水花炸开（底部宽、往外上方甩出成团水滴、有重量地落回）+ 根部一圈粗水刺；
// 精一水花更多更高；精二（质变）水滴点深渊紫 + 0.16 秒后第二冠回落溅起
function s1hit(p, t, o, C, A1, A2) {
  const R = +o.R, el = +o.el, n = C.length;
  crown(p, t, o, C, A1, { N: 30 + 10 * el, H: 30 + 8 * el + R * 0.2, spread: 50 + R * 1.0, r0: 5 + el, acc: el >= 2, big: true, wide: 2, seed: 3 });
  if (el >= 2) crown(p, t - 0.16, o, C, A1, { N: 14, H: 12, spread: 30 + R * 0.6, r0: 6, acc: true, seed: 9 });
  if (t >= 0.067 && t < 0.36) {
    const N = 6 + el, L = R * 0.35, fade = smooth(0.12, 0.36, t);
    for (let i = 0; i < N; i++) {
      const a = -Math.PI * (-0.08 + 1.16 * (i + 0.7 * nz(i * 2.3, o.seed + 99)) / N), lj = 0.5 + 0.5 * nz(i * 1.9, o.seed + 101);
      const l = L * lj * (1 - 0.8 * fade);
      if (l >= 2) spike(p, Math.cos(a) * 4, Math.sin(a) * 2, a, l, 2 + 1.5 * nz(i * 3.3, o.seed + 103), C[4], C[n - 3], WHITE);
    }
  }
}

function s1hitGround(p, t, o, C) {
  const R = +o.R, SY = +o.SY, n = C.length;
  if (t < 0.5) {   // 落坑：断续亮边 + 2 格暗内边 + 往外的放射湿痕
    const r = R * (0.7 + 0.3 * ease.outCubic(clamp(t / 0.12))), gone = smooth(0.25, 0.5, t), m = Math.ceil(r * TAU * 1.2);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 4.9, o.seed + 111) < 0.2 + 0.8 * gone) continue;
      const rr = r * (0.93 + 0.14 * nz(a * 8.3, o.seed + 113));
      p.px(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), t < 0.1 ? WHITE : C[n - 3]);
      for (let d = 1; d <= 2; d++) p.px(R0(Math.cos(a) * (rr - d)), R0(Math.sin(a) * (rr - d) * SY), C[1]);
    }
    for (let i = 0; i < 9; i++) {
      const a = (i + nz(i * 2.7, o.seed + 115)) / 9 * TAU;
      for (let s = r * 0.3; s < r * (0.7 + 0.25 * nz(i, o.seed + 117)); s += 1)
        if (nz(s * 0.6 + i * 9, o.seed + 119) > 0.35 + 0.65 * gone) p.px(R0(Math.cos(a) * s), R0(Math.sin(a) * s * SY), C[1]);
    }
  }
  wet(p, t, R * 0.4, 0.6, o.seed + 121, C, SY);
}

// ---------------------------------------------------------------- S2「缺水的掌握怒海」起手：身边一圈倾斜的水环升起（原作 skill_02_start 的大水环），脚下冲起一柱
// half: bk 远半圈（排在她身后）/ up 近半圈 + 水柱；精二（质变）两道反向水环 + 深渊紫高光
function s2ring(p, t, o, C, A1, half) {
  const R = +o.R, SY = +o.SY, n = C.length, el = +o.el;
  const rings = el >= 2 ? [[R, 26, 1, 2], [R * 0.68, 15, -1, 2]] : [[R, 24, 1, 2]];
  for (const [Rr, Z, dirn, th] of rings) {
    const grow = ease.outCubic(clamp(t / 0.28)), r = Rr * (0.7 + 0.3 * grow), z0 = Z * grow, gone = smooth(0.32, 0.56, t);
    const m = Math.ceil(r * TAU * 1.2), rot = dirn * t * 4;
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU, sa = Math.sin(a);
      if ((half === "bk") !== (sa < 0)) continue;
      if (nz((a - rot) * 2.3, o.seed + 131 + Rr) < 0.12 + gone) continue;   // 断口 + 散掉
      const tilt = Math.cos(a) * 4;   // 环微微倾斜（不是正水平）
      const x = Math.cos(a) * r, y = sa * r * SY - z0 - tilt;
      for (let j2 = 0; j2 < th; j2++) {
        let c = j2 === 0 ? (nz((a - rot) * 6, o.seed + 133) > 0.55 ? WHITE : C[n - 3]) : j2 === th - 1 ? C[3] : C[4];
        if (sa < 0) c = j2 === 0 ? C[n - 3] : C[2];   // 远半圈暗
        if (el >= 2 && j2 === 0 && nz((a - rot) * 11, o.seed + 135) > 0.7) c = A1;
        p.px(R0(x), R0(y + j2), c);
      }
      if (gone > 0.05 && nz(a * 23, o.seed + 137) > 0.75) {   // 散掉时滴落
        const u = t - 0.32;
        p.px(R0(x), R0(y + 3 + 200 * u * u), C[n - 4]);
      }
    }
  }
  if (half !== "bk" && t >= 0.12) crown(p, t - 0.12, o, C, A1, { N: 14 + 4 * el, H: 16 + 4 * el, spread: 34, r0: 4, acc: el >= 2, seed: 13 });
}

function s2ringGround(p, t, o, C) {
  const R = +o.R, SY = +o.SY, n = C.length;
  if (t > 0.5) return;
  const r = R * (0.7 + 0.3 * ease.outCubic(clamp(t / 0.28))), gone = smooth(0.2, 0.5, t), m = Math.ceil(r * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 3.9, o.seed + 141) < 0.25 + 0.75 * gone) continue;
    const rr = r * (0.95 + 0.1 * nz(a * 7, o.seed + 143));
    p.px(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), C[2]);
    p.px(R0(Math.cos(a) * (rr - 1.5)), R0(Math.sin(a) * (rr - 1.5) * SY), C[1]);
  }
  wet(p, t, 9, 0.5, o.seed + 145, C, SY);
}

// S2 持续（循环，跟着人走）：脚下一圈断续的浪沫边慢慢转 + 一格暗内边；精二点深渊紫
function s2aura(p, t, o, C, A1) {
  const R = +o.R, SY = +o.SY, n = C.length, el = +o.el, P = +o.dur, rot = (t / P) * TAU / 3;
  const m = Math.ceil(R * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, b = a - rot;
    const q = nz(Math.cos(b * 3) * 2 + 5, o.seed + 151 + Math.round(Math.sin(b * 3) * 3));
    if (q < 0.42) continue;
    const rr = R * (0.94 + 0.1 * q);
    const c = q > 0.82 ? WHITE : q > 0.62 ? C[n - 3] : C[4];
    p.px(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), el >= 2 && q > 0.9 ? A1 : c);
    p.px(R0(Math.cos(a) * (rr - 1.5)), R0(Math.sin(a) * (rr - 1.5) * SY), C[1]);
  }
}

// ---------------------------------------------------------------- S3「缺水的碎漩狂舞」：龙卷水墙（用户认可的龙卷版，转平面）
// 上宽下窄的水墙，按高度一层层横向流纹（远半圈暗、近半圈亮），近半圈不铺实心（只画流纹 + 两侧轮廓 + 上沿），中间的怪看得见；
// 脚下一圈不规整的白浪；地面只画边 + 淡渐变。mode：open 0.3 秒从地面卷起 / loop 0.6 秒无缝循环（流纹三重对称，每圈转 120°）/ close 0.5 秒收拢成柱 → 炸开塌落
function tideBands(o) {
  const out = [];
  for (let i = 0; i < 4; i++) out.push({ ph: nz(i * 3.3, o.seed + 161) * TAU / 3, len: 0.35 + 0.5 * nz(i * 1.7, o.seed + 163), tw: 0.6 + 1.2 * nz(i * 2.9, o.seed + 165), z0: i * 0.7 });
  return out;
}

function tornado(p, t, o, T, A1, layer) {
  const R = +o.R, H = +o.H, SY = o.view === "raw" ? 1 : +o.SY, n = T.length, mode = o.mode, raw = o.view === "raw";
  let Hn = H, Rn = R, rot = 0, flash = false, bright = 0, burst = -1;
  if (mode === "open") {
    const u = clamp(t / 0.3), e = ease.outCubic(u);
    Hn = H * (0.15 + 0.85 * e); Rn = R * (0.65 + 0.35 * e); rot = u * 0.6; flash = t < 0.067;
  } else if (mode === "loop") {
    rot = (t / +o.dur) * TAU / 3;
  } else {
    const u = clamp(t / 0.25), e = ease.inCubic(u);
    Rn = R * (1 - 0.72 * e); Hn = H * (1 + 0.3 * e); rot = u * 1.6; bright = e;
    if (t >= 0.25) burst = t - 0.25;
  }
  const rz = (z) => Rn * (0.76 + 0.24 * (z / Math.max(1, Hn)));
  if (layer === "gd") {   // 地面：只画边（断续白浪脚）+ 往里 6 格的淡渐变（α ≤ 0.14，按噪声成团）
    const rb = burst >= 0 ? R * (0.3 + 0.85 * ease.outCubic(clamp(burst / 0.2))) : Rn;
    if (burst >= 0 && burst > 0.25) return;
    const m = Math.ceil(rb * TAU * 1.2);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      const q = nz((a - rot) * 4.1, o.seed + 171);
      const rr = rb * (0.96 + 0.08 * q);
      if (q > 0.3) p.px(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), q > 0.75 ? T[n - 2] : T[4]);
      p.px(R0(Math.cos(a) * (rr - 1.5)), R0(Math.sin(a) * (rr - 1.5) * SY), T[1]);
      if (burst < 0) for (let d = 3; d < 9; d++) if (nz(a * 7 + d * 3.1, o.seed + 173) > 0.45)
        p.dot(R0(Math.cos(a) * (rr - d)), R0(Math.sin(a) * (rr - d) * SY), T[3], 0.14 * (1 - d / 9));
    }
    return;
  }
  if (burst >= 0) {   // 收拢成柱后炸开：水花往外甩、受重力落下（只在近层画，远层空）
    if (layer !== "up") return;
    const N = 34;
    for (let i = 0; i < N; i++) {
      const a = (i + nz(i * 1.3, o.seed + 181)) / N * TAU, v = 60 + 60 * nz(i * 2.1, o.seed + 183), zh = Hn * (0.2 + 0.8 * nz(i * 3.7, o.seed + 185));
      const x = Math.cos(a) * (Rn + v * burst), y = Math.sin(a) * (Rn + v * burst) * SY - zh - 30 * burst + 330 * burst * burst;
      if (y > Math.sin(a) * (Rn + v * burst) * SY + 1) continue;
      p.px(R0(x), R0(y), burst < 0.06 ? WHITE : burst < 0.14 ? T[n - 2] : T[4]);
      if (i % 2 === 0) p.px(R0(x) + 1, R0(y), T[n - 3]);
    }
    if (burst < 0.1) {   // 柱身最后一拍：一道白
      for (let z = 0; z <= Hn * (1 - burst * 6); z += 1) for (let q = -2; q <= 2; q++) p.px(q, R0(-z), Math.abs(q) < 2 ? WHITE : T[n - 2]);
    }
    return;
  }
  const near = layer === "up";
  const bands = tideBands(o);
  const am = Math.ceil(Rn * TAU * 1.3);
  // 远半圈：暗色水墙（半透明 0.55）+ 暗流纹；近半圈：只画流纹
  for (let z = 0; z <= Hn; z += 1) {
    const r = rz(z), kz = z / Math.max(1, Hn);
    for (let j = 0; j < am; j++) {
      const a = (j / am) * TAU, sa = Math.sin(a);
      if (near !== (sa >= 0)) continue;
      const x = Math.cos(a) * r, y = sa * r * SY - z;
      let streak = -1;
      for (let b = 0; b < bands.length; b++) {
        const B = bands[b];
        if ((Math.round(z + B.z0 * 5) % 5) !== 0) continue;
        const ab = ((a - (B.ph + rot + B.tw * kz)) % (TAU / 3) + TAU / 3) % (TAU / 3);
        if (ab < B.len * (near ? 0.38 : 0.6) * (0.5 + 0.5 * nz(z * 0.37 + b, o.seed + 191))) { streak = b; break; }
      }
      const edge = Math.abs(Math.cos(a)) > 0.965;   // 两侧轮廓（侧面看过去水墙最厚）
      if (!near) {
        let c = streak >= 0 ? T[2 + (streak % 2)] : T[1];
        if (bright > 0 && streak >= 0) c = T[5];
        if (edge) c = T[4];
        p.dot(R0(x), R0(y), c, streak >= 0 || edge ? 0.9 : 0.45);
      } else {
        if (streak < 0 && !edge) continue;
        let c = streak >= 0 ? (streak % 2 ? T[5] : T[4]) : T[n - 3];
        if (flash || bright > 0.6) c = WHITE;
        if (kz > 0.93) c = T[n - 2];
        p.px(R0(x), R0(y), c);
      }
    }
  }
  // 上沿：近半圈亮、远半圈暗；脚下一圈不规整白浪（断续亮边 + 浪尖起落）
  const r1 = rz(Hn);
  for (let j = 0; j < am; j++) {
    const a = (j / am) * TAU, sa = Math.sin(a);
    if (near !== (sa >= 0)) continue;
    if (nz((a - rot) * 5.3, o.seed + 195) < 0.18) continue;
    p.px(R0(Math.cos(a) * r1), R0(sa * r1 * SY - Hn), near ? (flash ? WHITE : T[n - 1]) : T[4]);
    const r0b = rz(0), q = nz((a + rot) * 6.1, o.seed + 197);
    if (q > 0.35) {
      const hh = 1 + Math.round(3 * q);
      for (let z = 0; z < hh; z++) p.px(R0(Math.cos(a) * (r0b + 1)), R0(sa * (r0b + 1) * SY - z), z === hh - 1 ? T[n - 1] : near ? T[5] : T[3]);
    }
  }
  if (raw && near) p.light(0, -Hn * 0.5, T[5], 0.6);
}

// ---------------------------------------------------------------- 每跳（S3 伤害 + 拉扯）：地上四段浪沫弧从外往里收
function tick(p, t, o, T) {
  const R = +o.R, SY = +o.SY, n = T.length;
  if (t > 0.32) return;
  const g = ease.inCubic(clamp(t / 0.3)), r = R * (0.98 - 0.55 * g);
  for (let s = 0; s < 4; s++) {
    const a0 = (s / 4) * TAU + nz(s * 2.2, o.seed + 201) * 0.8 - t * 3, L = 0.9;
    for (let a = a0; a < a0 + L; a += 1 / r) {
      const k = (a - a0) / L, rr = r * (1 + 0.05 * Math.sin(k * 9));
      p.px(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), k > 0.75 ? T[n - 1] : T[5]);
      if (k < 0.6) p.px(R0(Math.cos(a) * (rr + 2)), R0(Math.sin(a) * (rr + 2) * SY), T[3]);
    }
  }
}

// ---------------------------------------------------------------- 回收斩（成长节点）：腰高水平刀痕（同 docs/246 的刀剑感：月牙、外缘白刃线、第 0 拍扫出 55%）
function slash(p, t, o, C, A1, gd) {
  const R = +o.R, Wd = +o.W, SY = +o.SY, H0 = gd ? 0 : 11, th = +o.dir * D2R, span = +o.span, n = C.length;
  const a0 = -span / 2, head = a0 + span * (0.55 + 0.45 * clamp(t / 0.067)), tail = a0 + span * 0.22 * smooth(0.07, 0.3, t);
  const hot = t < 0.1, cool = smooth(0.1, +o.dur, t);
  if (head - tail < 0.03 || cool >= 0.72) return;
  const Wr = Wd * (1 - 0.7 * cool), B = R + 3;
  if (gd) {
    for (let a = tail; a <= head; a += 0.4 / R) {
      const u = (a - tail) / Math.max(0.001, head - tail), wr = Wr * 0.5 * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.8)), 0.75);
      for (let d = 0; d < wr; d += 1) p.dot(R0(Math.cos(a + th) * (R - d)), R0(Math.sin(a + th) * (R - d) * SY), C[0], 0.45 * (1 - cool));
    }
    return;
  }
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 1.5 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x) - th;
    a = ((a - a0) % TAU + TAU) % TAU + a0;
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);
    const wr = Wr * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.8)), 0.75);
    if (wr < 0.7) return;
    const q = (R + 0.8 * nz(a * 14, o.seed + 3) - r) / wr;
    if (q < 0 || q > 1) return;
    let ci = q < 0.13 ? (hot ? n - 1 : n - 2) : q < 0.34 ? n - 3 : q < 0.6 ? n - 4 : q < 0.85 ? n - 5 : n - 6;
    if (q >= 0.85) out.a = 0.55;
    if (hot && u > 0.82 && q < 0.5) ci = n - 1;
    ci = clamp(ci - Math.round(cool * 2.5) - (u < 0.2 ? 1 : 0), 1, n - 1);
    out.c = C[ci];
    if (out.a === undefined) out.a = 1;
  });
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), T = fit(o.tide, 8), A1 = hex(o.accent), A2 = hex(o.accent2);
  const ly = o.layer, gd = ly === "gd";
  switch (o.part) {
    case "hit": return gd ? hitGround(p, t, o, C) : hit(p, t, o, C, A1, A2);
    case "arrive": return gd ? arriveGround(p, t, o, C, A1) : arrive(p, t, o, C, A1);
    case "wave": return ringWave(p, t, o, C, A1, gd);
    case "backwash": return backwash(p, t, o, C, A1, gd);
    case "s1hit": return gd ? s1hitGround(p, t, o, C) : s1hit(p, t, o, C, A1, A2);
    case "geyser": return gd ? hitGround(p, t, Object.assign({}, o, { R: +o.R }), C) : geyserUp(p, t, o, C, A1);
    case "s2cast": return gd ? s2ringGround(p, t, o, C) : s2ring(p, t, o, C, A1, ly);
    case "s2aura": return gd ? s2aura(p, t, o, C, A1) : undefined;
    case "tornado": return tornado(p, t, o, T, A1, ly);
    case "tick": return gd ? tick(p, t, o, T) : undefined;
    case "slash": return slash(p, t, o, C, A1, gd);
  }
}
