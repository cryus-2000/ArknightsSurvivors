// 斯卡蒂「转平面」试验（docs/246，开关 fx/px_plane）：pixelfx 画法，但按本作俯视斜角重画，不是横版侧视图贴上去。
// 一个文件按 part 出五种件；每种分两层导出（layer）：
//   up 立起层 —— 离地的东西（腰高的水平刀痕、竖直水柱、潮刃浪头），原点 = 脚底地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（接触阴影、水痕、冲击环、积水），已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转；
// 方向件（ribbon / blade）按 dir（度，平面角，y 向下 = 朝镜头）逐向生成，游戏挑最近的一张（另一半水平翻转）。
// view: "raw" 出「旧做法」对照：横版 / 正俯视的原样画（圆不压扁、刀光是平躺的整圆弧、光晕烤进颜色），游戏里旋转 + 小数缩放贴上去。
// 色：本人深海蓝（house.js OP.skadi）；精二点缀海绿 #5ff0cc；不用危险红。同一招元素 ≤ 3。
import { fit, clamp, smooth, ease, noise, noise2, TAU, hex, WHITE } from "../../core/index.js";

export const meta = {
  name: "Skadi plane",
  desc: "Skadi's greatsword and tide moves redrawn for a 3/4 top-down plane: standing blade curtains, water columns and tide crests, and squashed ground rings, wakes and shadows.",
  tags: ["water", "slash", "topdown", "skadi", "one-shot"],
  size: [320, 260],
  origin: [160, 180],
  duration: 0.8,
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
// 分档（11-05 用户「浪花没什么用，换一个」→ 每升一档多一个新元素，不靠水花）：
//   精一：刀身加厚 + 斩击后地上留一道发光的深海裂痕（贴地层 rift）；
//   精二：再加从裂痕里往上长出的深海暗影触须（深蓝身、海绿尖，扭一下缩回裂口）+ 白刃线内侧一道海绿副刃（刃变重）。
function sweep(t, span, full) {
  const a0 = -span / 2;
  const head = a0 + span * (full ? 0.4 + 0.6 * clamp(t / 0.1) : 0.55 + 0.45 * clamp(t / 0.067));
  // 11-05 用户「还有碎斩击」：收刀不再从刀尾往前吃成细碎尾巴，整道月牙一起变薄变暗；刀尾只往前收一点
  const tail = a0 + span * 0.22 * smooth(0.07, full ? 0.36 : 0.3, t);
  return [a0, head, tail];
}

function smear(p, t, o, C, ACC, full, k) {
  // k：{R, Wr, dt 延迟, dim 暗几阶, edge 是否画白刃}
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : +o.H0, th = +o.dir * D2R, el = +o.el, n = C.length;
  const tt = t - k.dt;
  if (tt < 0) return;
  const span = full ? TAU * 0.84 : +o.span;   // 旋斩：一整道约 300° 的连续月牙（不断开、不画整圈）
  const [a0, head, tail] = sweep(tt, span, full);
  const st = o.style || "basic";   // basic 普攻 / s1 迅捷打击（更白更重、刀头甩水扇）/ s3 涌潮悲歌（深海暗蓝 + 海绿浪沫刃 + 向外甩水）
  const hot = tt < (st === "s1" ? 0.13 : 0.1), cool = smooth(0.1, +o.dur, tt);
  if (head - tail < 0.03 || cool >= 0.72) return;   // 收到只剩细线前就整道消失（不留细环）
  const R = k.R, Wr = k.Wr * (1 - 0.7 * cool);
  const B = R + 3;
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 1.5 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x) - th;
    a = ((a - a0) % TAU + TAU) % TAU + a0;            // 折到 [a0, a0 + 2π)
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);   // 0 刀尾 → 1 刀头
    let wr = Wr * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.8)), 0.75);
    if (full) wr *= 0.75 + 0.45 * nz(a * 1.3, o.seed + 41);   // 旋斩粗细起伏（不断开）
    if (wr < 0.7) return;
    const jag = 0.8 * nz(a * 14, o.seed + 3);
    const q = (R + jag - r) / wr;                        // 0 外缘（刃）→ 1 内沿
    if (q < 0 || q > 1) return;
    let ci;
    const eq = st === "s1" ? 0.2 : 0.13;
    if (q < eq) ci = k.edge && hot ? n - 1 : n - 2;      // 白刃线（S1 两格）
    else if (q < 0.34) ci = n - 3;
    else if (q < 0.6) ci = n - 4;
    else if (q < 0.85) ci = n - 5;
    else { ci = n - 6; out.a = 0.55; }                   // 内沿抖动变稀，不平涂
    if (cool > 0.6) out.a = (out.a === undefined ? 1 : out.a) * 0.6;   // 收刀最后两拍整道抖动变稀
    if (q > 0.18 && q < 0.85 && nz(r * 0.85 + o.seed, o.seed + 91) > 0.68) ci += 1;   // 速度纹
    if (hot && u > 0.82 && q < 0.5) ci = n - 1;          // 刀头热白
    if (st === "s1" && q < 0.6) ci += 1;                 // S1 整体亮一阶（更白、更重）
    if (st === "s3") ci -= 1;                            // S3 深海暗蓝
    ci = clamp(ci - k.dim - Math.round(cool * 2.5) - (u < 0.2 ? 1 : 0), 1, n - 1);
    out.c = C[ci];
    if (st === "s3" && !hot && q < 0.16) out.c = ACC;    // S3 刃线换海绿浪沫
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
  if (st === "s1" && tt > 0.03 && tt < 0.32) {   // S1：刀头顺切线甩出一扇水花（有重力、往下落）
    const ha = head + th, tx = -Math.sin(ha), ty = Math.cos(ha) * SY, hx = Math.cos(ha) * R, hy = Math.sin(ha) * R * SY - H0;
    const N = 16 + 4 * el, u = tt - 0.03;
    for (let i = 0; i < N; i++) {
      const sp = 150 + 150 * nz(i * 3.1, o.seed + 201), da = (nz(i * 1.7, o.seed + 203) - 0.5) * 1.4;
      const dx = tx * Math.cos(da) - ty * Math.sin(da), dy = tx * Math.sin(da) + ty * Math.cos(da);
      const x = hx + dx * sp * u + Math.cos(ha) * sp * 0.25 * u, y = hy + dy * sp * u + 260 * u * u;
      const c = u < 0.12 ? WHITE : u < 0.2 ? C[n - 2] : C[n - 4];
      const X = Math.round(x), Y = Math.round(y);
      p.px(X, Y, c);
      if (i % 2 === 0) { p.px(X + 1, Y, c); p.px(X, Y + 1, C[n - 3]); }   // 一半是 2 格大水珠
      if (u < 0.2) p.px(Math.round(x - dx * 2), Math.round(y - dy * 2), C[n - 4]);   // 拖一格尾
    }
  }
  if (st === "s3" && tt > 0.04 && tt < 0.34) {   // S3：沿弧向外甩水（径向、有重力）
    const u = tt - 0.04;
    for (let i = 0; i < 16; i++) {
      const a = tail + (head - tail) * nz(i * 2.3, o.seed + 301) + th, sp = 50 + 60 * nz(i * 1.9, o.seed + 303);
      const x = Math.cos(a) * (R + sp * u), y = Math.sin(a) * (R + sp * u) * SY - H0 - 40 * u + 300 * u * u;
      p.px(Math.round(x), Math.round(y), u < 0.12 ? C[n - 1] : i % 2 ? ACC : C[n - 3]);
    }
  }
}

// 裂痕上的点（rift 与 riftTendrils 共用同一条裂口几何）
function riftPt(o, a, R, th, SY) {
  const rr = R * 0.8 + 2.6 * (nz(a * 6.5, o.seed + 913) - 0.5) * 2;
  return [Math.cos(a + th) * rr, Math.sin(a + th) * rr * SY];
}

// 精二：深海暗影触须（贴「深海猎人」）——从地上的深海裂痕里往上长出 3–4 条卷曲的触须（深蓝身 + 暗边、2 格海绿尖），
// 刀收之后还在：0.06 秒起长出、扭动，约 0.5 秒缩回裂口。立起层（竖直，底端贴地）
function riftTendrils(p, t, o, C, ACC, full) {
  const R = +o.R, SY = +o.SY, th = +o.dir * D2R, n = C.length;
  const span = full ? TAU * 0.84 : +o.span, a0 = -span / 2;
  const grow = smooth(0.06, 0.16, t), shrink = smooth(0.34, 0.56, t);
  if (grow <= 0 || shrink >= 0.99) return;
  const m = full ? 5 : 4;
  for (let i = 0; i < m; i++) {
    const a = a0 + span * (0.18 + (0.66 / (m - 1)) * i + 0.06 * (nz(i * 3.3, o.seed + 901) - 0.5));
    const [bx, by] = riftPt(o, a, R, th, SY);
    const L = (20 + 12 * nz(i * 1.7, o.seed + 903)) * grow * (1 - shrink);
    if (L < 2) continue;
    const sg = i % 2 ? 1 : -1;
    let x = bx, y = by, dir = -Math.PI / 2 + sg * 0.25;      // 往上长，略外斜
    for (let s = 0; s <= L; s += 0.5) {
      const u = s / Math.max(1, L);
      dir += sg * (0.045 + 0.06 * u) + 0.03 * Math.sin(t * 24 + i * 2.1);   // 越往上卷得越紧，整条在扭
      x += Math.cos(dir) * 0.5;
      y += Math.sin(dir) * 0.5;
      const X = Math.round(x), Y = Math.round(y), wide = u < 0.5;
      p.px(X - 1, Y, C[0]);                                   // 暗边
      if (wide) p.px(X + 1, Y, C[0]);
      p.px(X, Y, u > 0.84 ? ACC : u > 0.6 ? C[3] : C[2]);
      if (wide) p.px(X + (sg > 0 ? 1 : -1), Y, C[2]);        // 根部 2 格粗
    }
  }
}

function ribbon(p, t, o, C, ACC, full) {
  const R = +o.R, W = +o.W, el = +o.el;
  if (el >= 2 && o.view !== "raw") riftTendrils(p, t, o, C, ACC, full);   // 精二：从裂痕里长出的暗影触须（先画，刀身盖在上面）
  smear(p, t, o, C, ACC, full, { R, Wr: W, dt: 0, dim: 0, edge: true });
}

// 精一起：斩击后地上留一道发光的深海裂痕——顺着刀痕在地面上裂开（刀头扫到哪裂到哪），暗色裂口 + 1 格海绿发光芯，
// 几处小分叉；0.15 秒起芯慢慢暗下去，约 0.6 秒整道消失（比刀痕晚走：刀已收、地上还亮着一会儿）
function rift(p, t, o, C, ACC, full) {
  const R = +o.R, SY = +o.SY, th = +o.dir * D2R, n = C.length;
  const span = full ? TAU * 0.84 : +o.span;
  const [a0, head] = sweep(t, span, full);
  const glow = 1 - smooth(0.15, 0.5, t), fade = smooth(0.42, 0.66, t);
  if (fade >= 0.99) return;
  const rr0 = R * 0.8;
  for (let a = a0 + span * 0.08; a <= Math.min(head, a0 + span * 0.96); a += 0.5 / rr0) {
    if (nz(a * 9, o.seed + 911) < fade) continue;            // 消失时从两头碎开
    if (nz(a * 2.4, o.seed + 919) < 0.2) continue;           // 裂口断续（不成一条细线环）
    const [fx, fy] = riftPt(o, a, R, th, SY);
    const x = Math.round(fx), y = Math.round(fy);
    p.px(x, y + 1, C[0]);
    p.px(x, y - 1, C[0]);
    const lit = glow > 0.08 && nz(a * 17, o.seed + 915) > 0.22 * (1 - glow);
    p.px(x, y, lit ? ACC : C[1]);
    if (lit && glow > 0.45) p.px(x + 1, y, C[n - 2]);            // 亮的时候 2 格宽
    if (nz(a * 3.1, o.seed + 917) > 0.86) {                   // 小分叉（往外 3 格）
      for (let s = 1; s <= 3; s++) p.px(Math.round(Math.cos(a + th) * (rr + s * 1.2) + s * 0.4), Math.round(Math.sin(a + th) * (rr + s * 1.2) * SY), s === 1 && lit ? ACC : C[0]);
    }
  }
}

// 地面：刀痕在地上的投影阴影（外半圈，半透明抖动）
function ribbonGround(p, t, o, C, ACC, full) {
  if (o.view === "raw") return;
  if (+o.el >= 1) rift(p, t, o, C, ACC, full);
  const R = +o.R, W = +o.W, SY = +o.SY, th = +o.dir * D2R;
  const span = full ? TAU * 0.84 : +o.span;
  const [a0, head, tail] = sweep(t, span, full);
  const cool = smooth(0.1, +o.dur, t);
  if (head - tail < 0.03 || cool >= 0.72) return;
  for (let a = tail; a <= head; a += 0.4 / R) {
    const u = (a - tail) / Math.max(0.001, head - tail);
    const wr = W * 0.5 * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.8)), 0.75);
    for (let d = 0; d < wr; d += 1) {
      const rr = R - d, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY;
      p.dot(Math.round(x), Math.round(y), C[0], 0.45 * (1 - cool));
    }
    const st = o.style || "basic";
    if ((st === "s1" || st === "s3") && u > 0.15) {   // S1 / S3：刀痕下面地上一道泡沫水痕（宽 3 格，暗水 + 稀疏白沫）
      for (let d = 0; d < 3; d++) {
        const rr = R * 0.84 - d, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY;
        const foam = nz(a * 11 + d * 7, o.seed + 401) > 0.78;
        p.dot(Math.round(x), Math.round(y), foam ? C[6] : C[3], (foam ? 0.9 : 0.6) * (1 - cool));
      }
    }
  }
}

// S2 跃浪击：碎浪（11-05 用户「海浪那种溃散的感觉要做出来，不要做成那种扇形」）。
// 不是一整片扇面水墙，而是一道不规则的浪：浪线前后错落、高低不一、有缺口，两边不对称；
// 立起（0–0.1 秒）→ 浪顶往前卷出白唇（0.1–0.2）→ 浪头碎成一块块白沫往前翻滚、受重力落下，浪身塌下（0.18–0.36）
// → 地上留一摊往前漫开的碎白沫，越来越稀、孔越来越多直到散掉（贴地层，0.25–0.6）。
// 每根浪柱的基点、高度、碎块都由种子散列决定（不抽随机数）。
function breakerCols(o) {
  const R = +o.R, hA = +o.span / 2, th = +o.dir * D2R, SY = +o.SY, el = +o.el;
  const cols = [];
  const a0 = -hA * (0.75 + 0.35 * nz(1.3, o.seed + 701)), a1 = hA * (0.75 + 0.35 * nz(2.9, o.seed + 703));   // 两边不对称
  for (let a = a0; a <= a1; a += 0.5 / R) {
    const gap = nz(a * 4.1, o.seed + 705);
    if (gap < 0.2) continue;                                            // 缺口
    const rj = R * (0.86 + 0.28 * nz(a * 2.3, o.seed + 707));           // 浪线前后错落
    const peak = 0.35 + 0.55 * nz(a * 2.1, o.seed + 709) + 0.15 * nz(a * 6.3, o.seed + 711);   // 宽缓起伏的浪峰
    const edge = Math.min(1, (a - a0) / 0.35, (a1 - a) / 0.35);          // 两头收低
    const h = +o.H * (0.25 + peak) * Math.max(0.15, edge);
    const pa = a + th;
    cols.push({ a, pa, gx: Math.cos(pa) * rj, gy: Math.sin(pa) * rj * SY, h, ox: Math.cos(pa), oy: Math.sin(pa) * SY, near: Math.sin(pa), i: cols.length });
  }
  return cols;
}

function breaker(p, t, o, C, ACC) {
  const SY = +o.SY, el = +o.el, n = C.length;
  const rise = ease.outCubic(clamp(t / 0.1)), curl = smooth(0.08, 0.2, t), brk = smooth(0.17, 0.36, t);
  const cols = breakerCols(o).sort((A, B) => A.gy - B.gy);
  const s0 = +o.H * 0.7 * ease.outQuad(clamp(t / 0.42));                 // 整道浪往前走（不是原地立起的墙）
  for (const c0 of cols) {
    const c = Object.assign({}, c0, { gx: c0.gx + c0.ox * s0, gy: c0.gy + c0.oy * s0 });
    const hb = c.h * rise * (1 - 0.92 * brk);                            // 浪身塌下
    const strk = nz(c.a * 23, o.seed + 713);                             // 顺浪方向的水纹
    if (hb >= 1 && brk < 0.85) {
      // ① 背面缓坡：从身后（朝斯卡蒂一侧）贴地处缓缓升到浪顶，表面由深到浅；坡长跟着浪高一起塌，塌完就没
      const B = hb * 1.5;
      for (let sb = -B; sb <= 0; sb += 0.5) {
        const u = (sb + B) / B, z = hb * Math.pow(u, 1.7);
        const x = c.gx + c.ox * sb, y = c.gy + c.oy * sb - z;
        let ci = u < 0.35 ? n - 6 : u < 0.65 ? n - 5 : u < 0.88 ? n - 4 : n - 3;
        const band = nz(u * 7 + c.a * 2.5, o.seed + 713);              // 和浪顶平行的横纹（不按浪柱取色，免得排成放射线）
        if (band > 0.7) ci += 1; else if (band < 0.25) ci -= 1;
        if (u < 0.3 && nz(sb * 2 + c.a * 40, o.seed + 715) < 0.5) continue;   // 坡脚抖动变稀
        let col = C[clamp(ci - Math.round(brk * 2), 1, n - 1)];
        if (el >= 2 && u > 0.55 && u < 0.7) col = ACC;
        p.px(Math.round(x), Math.round(y), col);
        p.px(Math.round(x), Math.round(y) + 1, col);
      }
      // ② 前脸：浪顶往前倾、脸是凹弧（上面伸出去，下面收回来）；朝镜头的一侧亮一阶
      for (let z = 0; z <= hb; z += 0.5) {
        const k = z / hb, off = curl * hb * 0.45 * k * k;
        const x = c.gx + c.ox * off, y = c.gy + c.oy * off - z;
        const kj = k + 0.22 * (nz(c.a * 9.3, o.seed + 741) - 0.5) + 0.1 * (nz(z * 0.7 + c.a * 3, o.seed + 743) - 0.5);   // 色带随浪柱起伏错开（不成一块平板）
        if (k < 0.18 && nz(z * 2 + c.a * 50, o.seed + 745) < 0.5) continue;
        let ci = kj > 0.86 ? n - 1 : kj > 0.6 ? n - 3 : kj > 0.3 ? n - 4 : n - 5;
        if (c.near > 0.3 && k <= 0.86) ci += 1;
        if (c.near < -0.2 && k <= 0.86) ci -= 2;                          // 背向镜头的前脸看不太到：压暗
        p.px(Math.round(x), Math.round(y), C[clamp(ci - Math.round(brk * 2), 1, n - 1)]);
      }
    }
    // 白唇：浪顶往前卷出的一截白沫（碎开前）
    if (curl > 0 && brk < 0.6 && hb >= 2) {
      const L = 2 + 5 * curl * (0.5 + nz(c.a * 9, o.seed + 717));
      for (let s = 0; s <= L; s += 0.5) {
        const u = s / L;
        const x = c.gx + c.ox * (hb * 0.45 * curl + s), y = c.gy - hb - 1 + c.oy * (hb * 0.45 * curl + s) + u * u * 3;
        p.px(Math.round(x), Math.round(y), u < 0.6 ? WHITE : C[n - 2]);
      }
    }
    // 碎块：浪头碎成白沫团往前翻滚、受重力落下（每根浪柱 1–2 团，大小 2–3 格）
    if (brk > 0.02) {
      const m = 1 + (nz(c.a * 13, o.seed + 719) > 0.55 ? 1 : 0) + (el >= 2 ? 1 : 0);
      for (let j = 0; j < m; j++) {
        const sd = c.i * 7 + j * 3;
        const u = (t - 0.17 - 0.03 * nz(sd, o.seed + 721)) ;
        if (u <= 0) continue;
        const v = 40 + 50 * nz(sd * 1.7, o.seed + 723), up = 30 + 40 * nz(sd * 2.3, o.seed + 725);
        const fx = c.gx + c.ox * (c.h * 0.45 + v * u), fy0 = c.gy - c.h * (0.75 + 0.2 * nz(sd, o.seed + 727)) + c.oy * (c.h * 0.45 + v * u);
        const fy = fy0 - up * u + 420 * u * u;
        if (fy > c.gy + c.oy * v * u + 2) continue;                      // 落地就没了（地上的白沫交给贴地层）
        const sz = nz(sd * 3.1, o.seed + 729) > 0.5 ? 3 : 2;
        const col = u < 0.08 ? WHITE : u < 0.16 ? C[n - 2] : C[n - 3];
        for (let dx = 0; dx < sz; dx++) for (let dy = 0; dy < sz - (dx === sz - 1 ? 1 : 0); dy++) p.px(Math.round(fx) + dx, Math.round(fy) + dy, col);
      }
    }
  }
}

// 碎浪地面：浪脚暗湿带 → 碎沫摊开：往前漫的一片碎白沫（噪声取阈值，越往后阈值越高 = 孔越多、越稀），只在浪线前方，不画扇面边
function breakerGround(p, t, o, C, ACC) {
  const R = +o.R, SY = +o.SY, n = C.length, th = +o.dir * D2R;
  const rise = clamp(t / 0.1), spread = smooth(0.22, 0.5, t), fade = smooth(0.32, +o.dur, t);
  if (fade >= 0.99) return;
  const s0 = +o.H * 0.7 * ease.outQuad(clamp(t / 0.42));
  const cols = breakerCols(o).map((c0) => Object.assign({}, c0, { gx: c0.gx + c0.ox * s0, gy: c0.gy + c0.oy * s0 }));
  for (const c of cols) {
    if (rise > 0.3 && spread < 0.7) for (let d = -1; d <= 1; d++) {   // 浪脚暗湿带（实色细带，浪还立着的时候）
      const x = c.gx + c.ox * d, y = c.gy + c.oy * d;
      p.px(Math.round(x), Math.round(y), C[1]);
    }
    if (spread <= 0) continue;
    const reach = (12 + 34 * nz(c.a * 3.7, o.seed + 731)) * spread;      // 每根往前漫的距离不一样
    for (let s = 0; s <= reach; s += 1) {
      for (let w = -2; w <= 2; w++) {
        const x = c.gx + c.ox * s - c.oy / SY * w * 0.8, y = c.gy + c.oy * s + c.ox * SY * w * 0.8;
        const nn = noise2(x * 0.35, y * 0.5, o.seed + 733) * 0.5 + 0.5;
        const thr = 0.28 + 0.6 * fade + 0.22 * (s / Math.max(1, reach));
        if (nn < thr) continue;                                          // 孔
        const col = nn > thr + 0.25 ? WHITE : nn > thr + 0.12 ? C[n - 2] : C[n - 4];
        p.px(Math.round(x), Math.round(y), col);
      }
    }
  }
}

// S3 涌潮悲歌持续期间：脚下一滩不规则积水（循环 0.4 秒）——只画边 + 内侧淡抖动，边上几点水光慢慢挪
function pool(p, t, o, C, ACC) {
  const R = +o.R, SY = +o.SY, n = C.length, ph = (t / 0.4) * TAU;
  const rad = (a) => R * (0.82 + 0.18 * nz(a * 1.4 + 3, o.seed + 601) + 0.02 * Math.sin(a * 5 + ph));
  const m = Math.ceil(R * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, r = rad(a), ca = Math.cos(a), sa = Math.sin(a);
    if (nz(a * 2.2, o.seed + 605) < 0.3) continue;   // 积水边断续（不是整圈）
    for (let k = 0; k < 3; k += 0.5) p.px(Math.round(ca * (r - k)), Math.round(sa * (r - k) * SY), k < 1 ? (sa < 0 ? C[2] : C[3]) : C[1]);
    if (nz(a * 6 + ph * 0.3, o.seed + 603) > 0.82) p.px(Math.round(ca * (r - 1)), Math.round(sa * (r - 1) * SY), C[5]);
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
  // 内侧：一圈 2 格深色内边（用颜色阶代替透明度网点，11-05 2 倍下网点太显）
  if (fade < 0.7) for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 3.1, o.seed + 23) < 0.18 + fade * 0.5) continue;
    const rr = r + 1.6 * nz(a * 5, o.seed + 11) - th - 1;
    for (let k = 0; k < 2; k += 0.5) p.px(Math.round(Math.cos(a) * (rr - k)), Math.round(Math.sin(a) * (rr - k) * SY), C[1]);
  }
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

// ---- 分支招（11-05 用户「分支招数能不能做出点差距出来」）

// 涌潮（S1 分支一 / 悲歌期间每秒一圈）：脚下涌出一圈矮水涌——低矮的立起水边（带白沫浪顶）往外推开，高低不一、有断口，不是平贴地的环
function swell(p, t, o, C, ACC, gd) {
  const R = +o.R, H = +o.H, SY = +o.SY, el = +o.el, n = C.length;
  const g = ease.outCubic(clamp(t / 0.32)), r = R * (0.25 + 0.75 * g), fade = smooth(0.2, +o.dur, t);
  if (fade >= 0.99) return;
  const m = Math.ceil(r * TAU * 1.1);
  const pts = [];
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, k = nz(a * 3.7, o.seed + 801);
    if (k < 0.42) continue;                                             // 断口（多、宽）
    const h = H * (0.2 + 1.1 * Math.pow(nz(a * 5.3, o.seed + 803), 1.5)) * (1 - fade) * clamp(t / 0.06);
    pts.push({ a, x: Math.cos(a) * r, y: Math.sin(a) * r * SY, h, near: Math.sin(a) });
  }
  if (gd) {   // 水涌脚下：前沿内侧 2 格暗湿带 + 身后零星白沫
    for (const q of pts) {
      for (let d = 1; d <= 2; d++) p.px(Math.round(q.x * (1 - d / r)), Math.round(q.y * (1 - d / r)), C[1]);
      if (nz(q.a * 17, o.seed + 805) > 0.8) p.px(Math.round(q.x * 0.85), Math.round(q.y * 0.85), C[n - 3]);
    }
    return;
  }
  pts.sort((A, B) => A.y - B.y);
  for (const q of pts) {
    if (q.h < 1) continue;
    const ca = Math.cos(q.a), sa = Math.sin(q.a) * SY, B = q.h * 2.4;
    for (let sb = -B; sb <= 0; sb += 0.5) {   // 内侧缓坡
      const u = (sb + B) / B, z = q.h * Math.pow(u, 1.6);
      if (u < 0.3 && nz(sb * 3 + q.a * 30, o.seed + 807) < 0.5) continue;
      let ci = u < 0.45 ? n - 5 : u < 0.8 ? n - 4 : u < 0.93 ? n - 2 : n - 1;
      if (q.near < -0.3 && u < 0.93) ci -= 1;
      let col = C[clamp(ci - Math.round(fade * 2), 1, n - 1)];
      if (el >= 2 && u > 0.5 && u < 0.7) col = ACC;
      p.px(Math.round(q.x + ca * sb), Math.round(q.y + sa * sb - z), col);
    }
    for (let z = 0; z <= q.h; z += 0.5) {     // 外侧前脸（略前倾）
      const k = z / q.h, off = k * k * q.h * 0.35;
      let ci = k > 0.8 ? n - 1 : k > 0.4 ? n - 4 : n - 5;
      if (q.near > 0.3 && k <= 0.8) ci += 1;
      if (q.near < -0.3 && k <= 0.8) ci -= 2;
      p.px(Math.round(q.x + ca * off), Math.round(q.y + sa * off - z), C[clamp(ci - Math.round(fade * 2), 1, n - 1)]);
    }
  }
}

// 回澜（S2 分支二「海水回卷」）：反过来——四周海水往脚下倒卷回来，浪沫边越收越快（不规则、有断口，身后拖往外的水纹），
// 汇到中心后冲起一柱水
function backwash(p, t, o, C, ACC, gd) {
  const R = +o.R, SY = +o.SY, n = C.length;
  const g = ease.inCubic(clamp(t / 0.3)), r = R * (1 - 0.85 * g);
  if (t < 0.32) {
    const m = Math.ceil(r * TAU * 1.1);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 3.3, o.seed + 811) < 0.28) continue;
      const rr = r * (0.9 + 0.2 * nz(a * 6.1, o.seed + 813));
      const x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY;
      if (gd) {   // 地上：前沿暗湿带 + 往外拖的水纹（越收越快，纹越长）
        p.px(Math.round(x), Math.round(y), C[1]);
        const L = 2 + 10 * g * nz(a * 9, o.seed + 815);
        for (let s = 1; s <= L; s += 1) if (nz(a * 31 + s, o.seed + 817) > 0.4)
          p.px(Math.round(x + Math.cos(a) * s), Math.round(y + Math.sin(a) * SY * s), s < 3 ? C[n - 4] : C[n - 5]);
        continue;
      }
      // 立起：一道往里卷的矮浪沫边（高 3–7、顶白沫、往圆心倾）
      const h = 3 + 4 * nz(a * 4.7, o.seed + 819);
      for (let z = 0; z <= h; z += 0.5) {
        const k = z / h, lean = -k * k * 3;
        p.px(Math.round(x + Math.cos(a) * lean), Math.round(y - z + Math.sin(a) * SY * lean), k > 0.65 ? WHITE : k > 0.35 ? C[n - 3] : C[n - 5]);
      }
    }
  }
  if (!gd && t >= 0.27) {   // 汇到中心：冲起一柱水（时间平移的水柱）
    splash(p, t - 0.27, Object.assign({}, o, { H: 54, R: 34 }), C, ACC);
  }
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "ribbon": return gd ? ribbonGround(p, t, o, C, ACC, false) : ribbon(p, t, o, C, ACC, false);
    case "spin": return gd ? ribbonGround(p, t, o, C, ACC, true) : ribbon(p, t, o, C, ACC, true);
    case "splash": return gd ? splashGround(p, t, o, C, ACC) : splash(p, t, o, C, ACC);
    case "blade": return gd ? bladeGround(p, t, o, C) : blade(p, t, o, C, ACC);
    case "curtain": return gd ? breakerGround(p, t, o, C, ACC) : breaker(p, t, o, C, ACC);   // S2 碎浪
    case "swell": return swell(p, t, o, C, ACC, gd);
    case "backwash": return backwash(p, t, o, C, ACC, gd);
    case "pool": return gd ? pool(p, t, o, C, ACC) : undefined;
    case "ring": return gd || o.view === "raw" ? ring(p, t, o, C, ACC) : undefined;
  }
}
