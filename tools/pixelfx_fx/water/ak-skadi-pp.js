// 斯卡蒂「转平面」试验（docs/246，开关 fx/px_plane）：pixelfx 画法，但按本作俯视斜角重画，不是横版侧视图贴上去。
// 一个文件按 part 出五种件；每种分两层导出（layer）：
//   up 立起层 —— 离地的东西（腰高的水平刀痕、竖直水柱、潮刃浪头），原点 = 脚底地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（接触阴影、水痕、冲击环、积水），已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转；
// 方向件（ribbon / blade）按 dir（度，平面角，y 向下 = 朝镜头）逐向生成，游戏挑最近的一张（另一半水平翻转）。
// view: "raw" 出「旧做法」对照：横版 / 正俯视的原样画（圆不压扁、刀光是平躺的整圆弧、光晕烤进颜色），游戏里旋转 + 小数缩放贴上去。
// 色：本人深海蓝（house.js OP.skadi）；精二点缀海绿 #5ff0cc；不用危险红。同一招元素 ≤ 3。
import { fit, clamp, smooth, ease, noise, TAU, hex, WHITE } from "../../core/index.js";

export const meta = {
  name: "Skadi plane",
  desc: "Skadi's greatsword and tide moves redrawn for a 3/4 top-down plane: standing blade curtains, water columns and tide crests, and squashed ground rings, wakes and shadows.",
  tags: ["water", "slash", "topdown", "skadi", "one-shot"],
  size: [240, 200],
  origin: [120, 140],
  duration: 0.5,
  loop: false,
  fps: 15,   // 统一动画时钟（协调人 11-05）：本作特效帧条一律 15 fps，60 Hz 下每帧正好停 4 个游戏帧；时长不对增删帧，不改 fps
  bg: "dark",
  options: {
    palette: ["#081226", "#1b325c", "#30508e", "#446ec0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"],
    accent: "#5ff0cc",
    part: "ribbon",   // ribbon 横扫刀光幕 / spin 全向旋斩 / splash 水柱 / blade 潮刃浪头（循环）/ ring 贴地冲击环
    layer: "up",      // up / gd
    view: "plane",    // plane / raw
    R: 56,            // 半径（美术像素）
    span: 2.8,        // 弧长（弧度）
    dir: 0,           // 平面角（度）
    H0: 11,           // 刀光幕离地高度（腰）
    W: 7,             // 刀光幕高
    H: 40,            // 水柱 / 浪头高
    el: 0,
    SY: 0.72,
    dur: 0.42,
    seed: 3,
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1

// 斩击（11-05 用户「斩击没有刀剑感」后重写）：腰高的水平刀痕——大剑横扫扫过的那一片，按俯视斜角压扁（SY）、抬到腰高（H0）。
// 刀剑感来自：① 月牙形（中段厚、两头收成针尖，最厚处偏刀头）；② 外缘 1 像素白刃线（刀尖走过的路）+ 刀头一道径向刃光（剑身那一下的反光）；
// ③ 顺着弧走的速度纹；④ 快：第 0 帧就扫出 55%，第 1 帧扫满，之后从刀尾往前收。命中斩痕在游戏里画（fx_pxplane._cuts）。
// 精一：内圈晚一帧再来一刀（双刃，暗一阶）；精二：白刃线内侧一道海绿副刃 + 刃外浪沫点。
function sweep(t, span, full) {
  const a0 = -span / 2;
  const head = a0 + span * (full ? 0.4 + 0.6 * clamp(t / 0.1) : 0.55 + 0.45 * clamp(t / 0.067));
  const tail = a0 + span * smooth(0.06, full ? 0.36 : 0.3, t);
  return [a0, head, tail];
}

function smear(p, t, o, C, ACC, full, k) {
  // k：{R, Wr, dt 延迟, dim 暗几阶, edge 是否画白刃}
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : +o.H0, th = +o.dir * D2R, el = +o.el, n = C.length;
  const tt = t - k.dt;
  if (tt < 0) return;
  const span = full ? TAU : +o.span;
  const [a0, head, tail] = sweep(tt, span, full);
  const hot = tt < 0.1, cool = smooth(0.1, +o.dur, tt);
  if (head - tail < 0.03 || cool >= 0.99) return;
  const R = k.R, Wr = k.Wr * (1 - 0.45 * cool);
  const B = R + 3;
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 1.5 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x) - th;
    a = ((a - a0) % TAU + TAU) % TAU + a0;            // 折到 [a0, a0 + 2π)
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);   // 0 刀尾 → 1 刀头
    let wr = Wr * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.8)), 0.75);
    if (full) {
      const g = nz(a * 1.6, o.seed + 41) * 0.75 + nz(a * 4.7, o.seed + 43) * 0.25;
      if (g < 0.3) return;
      wr *= 0.45 + 1.2 * (g - 0.3);
    }
    if (wr < 0.7) return;
    const jag = 0.8 * nz(a * 14, o.seed + 3);
    const q = (R + jag - r) / wr;                        // 0 外缘（刃）→ 1 内沿
    if (q < 0 || q > 1) return;
    let ci;
    if (q < 0.13) ci = k.edge && hot ? n - 1 : n - 2;    // 白刃线
    else if (q < 0.34) ci = n - 3;
    else if (q < 0.6) ci = n - 4;
    else if (q < 0.85) ci = n - 5;
    else { ci = n - 6; out.a = 0.55; }                   // 内沿抖动变稀，不平涂
    if (q > 0.18 && q < 0.85 && nz(r * 0.85 + o.seed, o.seed + 91) > 0.68) ci += 1;   // 速度纹
    if (hot && u > 0.82 && q < 0.5) ci = n - 1;          // 刀头热白
    ci = clamp(ci - k.dim - Math.round(cool * 2.5) - (u < 0.2 ? 1 : 0), 1, n - 1);
    out.c = C[ci];
    if (out.a === undefined) out.a = 1;
    if (el >= 2 && k.edge && !hot && q > 0.13 && q < 0.26) out.c = ACC;   // 精二海绿副刃
  });
  if (!k.edge) return;
  // 刀头径向刃光（剑身那一下的反光），只在出手两帧
  if (tt < 0.067) {   // 只在出手第一帧：刀尖外 40% 一道刃光，靠刀尖处 2 格粗
    const ha = head + th;
    for (let d = R * 0.6; d <= R + 1; d += 0.5) {
      const x = Math.cos(ha) * d, y = Math.sin(ha) * d * SY - H0;
      p.px(Math.round(x), Math.round(y), d > R * 0.82 ? WHITE : C[n - 2]);
      if (d > R * 0.8) p.px(Math.round(x - Math.sin(ha)), Math.round(y + Math.cos(ha) * SY), C[n - 2]);
    }
  }
  if (raw) {   // 旧做法：光晕烤进颜色
    for (let a = tail; a <= head; a += 0.12) p.light(Math.cos(a + th) * R * 0.9, Math.sin(a + th) * R * 0.9, C[n - 2], 0.35 * (1 - cool));
  }
  if (el >= 2 && cool < 0.7) for (let a = tail; a <= head; a += 0.09) {   // 精二：刃外浪沫点
    if (nz(a * 7, o.seed + 13) < 0.62) continue;
    const rr = R + 2, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY - H0;
    p.px(Math.round(x), Math.round(y), C[n - 1]);
  }
}

function ribbon(p, t, o, C, ACC, full) {
  const R = +o.R, W = +o.W, el = +o.el;
  if (el >= 1) smear(p, t, o, C, ACC, full, { R: R * 0.72, Wr: W * 0.6, dt: 0.067, dim: 1, edge: false });   // 精一：内圈晚一帧的第二刀
  smear(p, t, o, C, ACC, full, { R, Wr: W, dt: 0, dim: 0, edge: true });
}

// 地面：刀痕在地上的投影阴影（外半圈，半透明抖动）
function ribbonGround(p, t, o, C, ACC, full) {
  if (o.view === "raw") return;
  const R = +o.R, W = +o.W, SY = +o.SY, th = +o.dir * D2R;
  const span = full ? TAU : +o.span;
  const [a0, head, tail] = sweep(t, span, full);
  const cool = smooth(0.1, +o.dur, t);
  if (head - tail < 0.03 || cool >= 0.99) return;
  for (let a = tail; a <= head; a += 0.4 / R) {
    const u = (a - tail) / Math.max(0.001, head - tail);
    if (full && nz(a * 1.6, o.seed + 41) * 0.75 + nz(a * 4.7, o.seed + 43) * 0.25 < 0.3) continue;
    const wr = W * 0.5 * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.8)), 0.75);
    for (let d = 0; d < wr; d += 1) {
      const rr = R - d, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY;
      p.dot(Math.round(x), Math.round(y), C[0], 0.45 * (1 - cool));
    }
  }
}

// 水柱：从地面竖直冲起、冠部碎开、回落；raw 同形（旧做法的差别在游戏里的贴法）
function splash(p, t, o, C, ACC) {
  const Hm = +o.H, R = +o.R, el = +o.el, n = C.length;
  const rise = ease.outCubic(clamp(t / 0.09)), fall = ease.inQuad(clamp((t - 0.16) / 0.26));
  const h = Hm * rise * (1 - fall);
  if (h < 1) return;
  const wB = R * 0.32 * (0.7 + 0.3 * rise) * (1 + fall * 0.6);   // 底宽（回落时摊开）
  const hot = t > 0.05 && t < 0.12;
  const cols = el >= 2 ? 3 : el >= 1 ? 2 : 1;   // 精一两股、精二三股（形状差）
  for (let k = 0; k < cols; k++) {
    const side = cols === 1 ? 0 : (k / (cols - 1) - 0.5) * 2;   // -1 左股 / 0 中 / 1 右股
    const mid = Math.abs(side) < 0.01;
    const hk = h * (mid ? 1 : 0.62);
    for (let y = 0; y >= -hk; y--) {
      const u = -y / Math.max(1, hk);                       // 0 底 → 1 顶
      const off = side * wB * (0.45 + 0.9 * u);             // 侧股往外斜（精一 / 精二的形状差）
      const half = wB * (mid ? 1 : 0.5) * (1 - 0.55 * u) * (0.85 + 0.25 * nz(y * 0.3 + k * 9, o.seed + 3 + Math.floor(t * 20)));
      for (let x = Math.round(off - half); x <= Math.round(off + half); x++) {
        const s = (x - off) / Math.max(1, half);            // -1 左 → 1 右（光从左上来）
        let ci = s < -0.55 ? n - 2 : s < 0.1 ? n - 3 : s < 0.6 ? n - 4 : n - 6;
        if (u > 0.82) ci = n - 1;                           // 冠部白沫
        if (hot && Math.abs(s) < 0.4) ci = n - 1;
        ci = clamp(ci - Math.round(fall * 2), 1, n - 1);
        let col = C[ci];
        if (el >= 2 && Math.abs(s) < 0.25 && u > 0.2 && u < 0.7 && !hot) col = ACC;
        p.px(x, y, col);
      }
    }
    // 冠部碎开的几粒（贴着冠）
    const offT = side * wB * 1.35;
    if (rise > 0.8) for (let i = 0; i < 5; i++) {
      const a = -Math.PI / 2 + (i - 2) * 0.5, d = 3 + 6 * smooth(0.08, 0.3, t);
      p.px(Math.round(offT + Math.cos(a) * d * 1.4), Math.round(-hk + Math.sin(a) * d - 1 + fall * 10), C[n - 1 - (i % 2)]);
    }
  }
}

// 贴地冲击环 / 积水：边一圈 + 内侧淡渐变（抖动），不平涂；边沿不规整；raw = 正圆
function ring(p, t, o, C, ACC) {
  const R = +o.R, SY = o.view === "raw" ? 1 : +o.SY, el = +o.el, n = C.length;
  const g = ease.outCubic(clamp(t / 0.22));
  const r = R * (0.35 + 0.65 * g);
  const fade = smooth(0.18, +o.dur, t);
  if (fade >= 0.995) return;
  const th = (el >= 1 ? 3 : 2) + (1 - g) * 2;
  const m = Math.ceil(r * TAU * 1.3);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, ca = Math.cos(a), sa = Math.sin(a);
    const jag = 1.6 * nz(a * 5, o.seed + 11) + 1.0 * nz(a * 13, o.seed + 17);
    const rr = r + jag;
    if (nz(a * 3.1, o.seed + 23) < 0.18 + fade * 0.5) continue;   // 断口：不画整圆
    for (let k = 0; k < th; k += 0.5) {
      const q = k / th;
      let ci = q < 0.3 ? n - 2 : q < 0.7 ? n - 3 : n - 5;
      if (t < 0.08 && q < 0.4) ci = n - 1;
      if (sa < -0.2) ci -= 1;                                  // 远侧暗一阶
      ci = clamp(ci - Math.round(fade * 2.5), 1, n - 1);
      const col = el >= 2 && q > 0.3 && q < 0.6 ? ACC : C[ci];
      p.dot(Math.round(ca * (rr - k)), Math.round(sa * (rr - k) * SY), col, 1 - fade * 0.6);
    }
  }
  // 内侧淡渐变：由外向内抖动变稀（α ≤ 0.25）
  const inner = 0.16 * (1 - fade);
  if (inner > 0.02) p.shade(-r, -r * SY, r, r * SY, (x, y, out) => {
    const d = Math.hypot(x / r, y / (r * SY));
    if (d > 0.9 || d < 0.55) return;
    out.c = C[3];
    out.a = inner * smooth(0.55, 0.9, d);
  });
  if (o.view === "raw") p.glowRing && p.glowRing(0, 0, r, C[n - 2], 0.4 * (1 - fade));
}

// 潮刃浪头（循环）：垂直于飞行方向的一道竖直浪幕，顶上白沫；raw = 平躺的新月
function blade(p, t, o, C, ACC) {
  const L = +o.R, Hm = +o.H, th = +o.dir * D2R, SY = +o.SY, el = +o.el, n = C.length;
  const ph = (t / 0.4) * TAU;   // 循环 0.4 秒 = 15 fps 正好 6 帧
  if (o.view === "raw") {
    for (let k = -L / 2; k <= L / 2; k += 0.5) {
      const u = k / (L / 2), w = 5 * (1 - u * u);
      for (let d = 0; d <= w; d += 0.5) {
        const q = d / Math.max(0.5, w);
        p.px(Math.round(-d - 6 * (1 - u * u) + 6), Math.round(k), C[q < 0.3 ? n - 1 : q < 0.7 ? n - 3 : n - 5]);
      }
    }
    p.light(0, 0, C[n - 2], 0.6);
    return;
  }
  const nx = -Math.sin(th), ny = Math.cos(th) * SY;            // 浪幕在地上的走向（垂直于飞行方向）
  const cols = [];
  for (let k = -L / 2; k <= L / 2; k += 0.5) {
    const u = k / (L / 2);
    const h = Hm * Math.pow(1 - u * u, 0.6) * (0.85 + 0.15 * Math.sin(ph + u * 4));
    const back = 3 * (1 - u * u);                            // 中间往前凸一点
    cols.push({ x: nx * k + Math.cos(th) * back, y: ny * k + Math.sin(th) * SY * back, h, u });
  }
  cols.sort((A, B) => A.y - B.y);
  for (const c of cols) {
    const x = Math.round(c.x);
    for (let y = Math.round(c.y); y >= Math.round(c.y - c.h); y--) {
      const q = (c.y - y) / Math.max(1, c.h);                // 0 底 → 1 顶
      let ci = q > 0.85 ? n - 1 : q > 0.6 ? n - 2 : q > 0.3 ? n - 3 : n - 5;
      let col = C[ci];
      if (el >= 2 && q > 0.35 && q < 0.6) col = ACC;
      p.px(x, y, col);
    }
  }
}

function bladeGround(p, t, o, C) {
  if (o.view === "raw") return;
  const L = +o.R, th = +o.dir * D2R, SY = +o.SY;
  const nx = -Math.sin(th), ny = Math.cos(th) * SY;
  for (let k = -L / 2; k <= L / 2; k += 0.5) {
    const u = k / (L / 2), back = 3 * (1 - u * u);
    const x = nx * k + Math.cos(th) * back, y = ny * k + Math.sin(th) * SY * back;
    p.dot(Math.round(x), Math.round(y) + 1, C[0], 0.5);
    // 身后一道尾迹（两格，往后拖）
    p.dot(Math.round(x - Math.cos(th) * 4), Math.round(y - Math.sin(th) * SY * 4), C[3], 0.35 * (1 - u * u));
  }
}

function splashGround(p, t, o, C, ACC) {
  // 水柱底下的湿印 + 冲击环（同 ring，小一号）
  ring(p, t, o, C, ACC);
  if (o.view === "raw") return;
  const R = +o.R * 0.3, SY = +o.SY, fade = smooth(0.1, +o.dur, t);
  if (fade < 0.99) p.shade(-R, -R * SY, R, R * SY, (x, y, out) => {
    const d = Math.hypot(x / R, y / (R * SY));
    if (d > 1) return;
    out.c = C[0];
    out.a = 0.4 * (1 - fade) * (1 - d * 0.6);
  });
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "ribbon": return gd ? ribbonGround(p, t, o, C, ACC, false) : ribbon(p, t, o, C, ACC, false);
    case "spin": return gd ? ribbonGround(p, t, o, C, ACC, true) : ribbon(p, t, o, C, ACC, true);
    case "splash": return gd ? splashGround(p, t, o, C, ACC) : splash(p, t, o, C, ACC);
    case "blade": return gd ? bladeGround(p, t, o, C) : blade(p, t, o, C, ACC);
    case "ring": return gd || o.view === "raw" ? ring(p, t, o, C, ACC) : undefined;
  }
}
