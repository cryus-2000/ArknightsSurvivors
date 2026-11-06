// 斯卡蒂「转平面」试验（docs/246，开关 fx/px_plane）：pixelfx 画法，但按本作俯视斜角重画，不是横版侧视图贴上去。
// 一个文件按 part 出五种件；每种分两层导出（layer）：
//   up 立起层 —— 离地的东西（腰高的水平刀痕、竖直水柱、潮刃浪头），原点 = 脚底地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（接触阴影、水痕、冲击环、积水），已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转；
// 方向件（ribbon / blade）按 dir（度，平面角，y 向下 = 朝镜头）逐向生成，游戏挑最近的一张（另一半水平翻转）。
// view: "raw" 出「旧做法」对照：横版 / 正俯视的原样画（圆不压扁、刀光是平躺的整圆弧、光晕烤进颜色），游戏里旋转 + 小数缩放贴上去。
// 色：本人深海蓝（house.js OP.skadi）；点缀冰蓝 #c4dcff（11-05 用户定，原海绿 #5ff0cc）；不用危险红。同一招元素 ≤ 3。
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
    accent: "#c4dcff",   // 点缀冰蓝（11-05 用户：海绿换掉，选冰蓝）
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
//   精二：刃变重——刀身压成深海暗色、内外两侧各一圈海绿描边（外缘白刃线保留）。（11-05 用户：触须很怪，不要）
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
    if (el >= 2 && k.edge && !hot) {   // 精二：刃变重——刀身压成深海暗色，内外两侧各一圈海绿描边（外缘白刃线保留）
      if (q > 0.13 && q < 0.24) out.c = ACC;
      else if (q >= 0.24 && q < 0.86) out.c = C[clamp(ci - 2, 1, n - 1)];
      else if (q >= 0.86) { out.c = ACC; out.a = 1; }
    }
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
    const x = Math.round(fx), y = Math.round(fy), rr = Math.hypot(fx, fy / SY);
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
    const pa = a + th;
    // 11-07 用户「S2 那个要改」（冰砖感）：朝镜头的浪柱压矮 0.2、背离镜头的压矮 0.5（只看得到背坡）；浪顶逐柱再抖一层碎起伏，不成直边
    const view = 1 - 0.2 * Math.max(0, Math.sin(pa)) - 0.5 * Math.max(0, -Math.sin(pa));
    const chop = 0.86 + 0.18 * nz(a * 6.1, o.seed + 751);
    const taper = Math.min(1, (gap - 0.2) / 0.14);                     // 11-07：缺口两侧渐矮（原来直上直下断开，一块块像方砖）
    const h = +o.H * (0.25 + peak) * Math.max(0.15, edge) * view * chop * Math.max(0.2, Math.sqrt(taper));
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
      if (c.near > -0.3) for (let z = 0; z <= hb; z += 0.5) {   // 11-07：背离镜头的前脸看不到，不画
        const k = z / hb, off = curl * hb * 0.45 * k * k;
        const x = c.gx + c.ox * off, y = c.gy + c.oy * off - z;
        const kj = k + 0.22 * (nz(c.a * 9.3, o.seed + 741) - 0.5) + 0.1 * (nz(z * 0.7 + c.a * 3, o.seed + 743) - 0.5);   // 色带随浪柱起伏错开（不成一块平板）
        if (k < 0.18 && nz(z * 2 + c.a * 50, o.seed + 745) < 0.5) continue;
        let ci = kj > 0.9 ? n - 1 : kj > 0.72 ? n - 3 : kj > 0.45 ? n - 4 : kj > 0.2 ? n - 5 : n - 6;   // 11-07：白只留浪顶一圈
        if (c.near > 0.3 && k > 0.45 && k <= 0.9) ci += 1;
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
// 真半透明（不抖动）：颜色的 alpha 字节直接写进像素（pixelfx 的 p.dot 是有序抖动，像素画里显脏，11-05 用户否过）
export function dotA(p, x, y, c, a) {
  if (a >= 0.999) return p.px(x, y, c);
  if (a <= 0.02) return;
  p.px(x, y, ((c & 0xffffff) | (Math.round(a * 255) << 24)) >>> 0);
}

// 落水水爆（11-05 第二版。第一版「水花冠」用户：有点奇怪——细条水舌像珊瑚 / 手指、棋盘格半透明显脏、看不出被砸起来的水）。
// 俯视下立起的柱子不好读 → 以贴地为主：
//   gd：压扁的环形水爆当主体（白沫环迅速往外扩、环边不规则浪唇；实心海蓝 + 亮边，不抖动）+ 环内一片统一透明度的湿印 +
//       每颗水滴的地面小影子（靠影子读高度）+ 落地白点；
//   up：一圈很矮的水冠（≤ 角色身高一半，16 美术像素），浪唇往外翻、往下落；8–14 颗水滴 / 小水团沿抛物线往外甩、落回。
// 宽度按 W（≤ 判定半径）封顶。S3 起手、S2 破浪下劈、终结技劈浪水柱同一套（ak-skadi-ult-pp.js 调 crown）。
function crownDrops(k) {
  const m = k.nd || 10, out = [];
  for (let i = 0; i < m; i++) {
    const a = (i + 0.5 * nz(i * 1.7, k.seed + 301)) / m * TAU;
    const v = k.W * (0.9 + 0.8 * nz(i * 2.3, k.seed + 303)) / 0.45;          // 落回前飞出约 0.6–1.2 W（不出判定圈太多）
    const vz = 70 + 70 * nz(i * 3.1, k.seed + 305);
    const big = nz(i * 4.7, k.seed + 307) > 0.65;                              // 小水团（3 格）
    const dl = 0.03 + 0.04 * nz(i * 5.9, k.seed + 309);
    const T = (2 * vz) / 520;                                                  // 落回时间（重力 520）
    out.push({ a, v, vz, big, dl, T });
  }
  return out;
}

export function crown(p, t, C, ACC, k) {
  // k：{x, y 落点（画布坐标）, W 半径上限, H 水冠高上限, SY, seed, layer "up" / "gd", raw, nd 水滴数}
  const n = C.length, W = k.W, SY = k.SY, sd = k.seed;
  if (t < 0 || t > 0.62) return;
  const grow = ease.outCubic(clamp(t / 0.26)), fade = smooth(0.24, 0.55, t);
  const gd = k.layer !== "up";
  const ring = (rad, fn) => { for (let a = 0; a < TAU; a += 0.7 / Math.max(4, rad)) fn(a, Math.cos(a), Math.sin(a)); };
  if (gd || k.raw) {
    // ① 环内湿印：统一透明度一整片（不抖动），跟着环长、先褪
    const rw = W * (0.25 + 0.6 * grow);
    if (fade < 0.95) for (let y = -rw * SY; y <= rw * SY; y += 1) for (let x = -rw; x <= rw; x += 1) {
      if ((x * x) / (rw * rw) + (y * y) / (rw * rw * SY * SY) > 1) continue;
      dotA(p, k.x + x, k.y + y, C[1], 0.45 * (1 - fade));
    }
    // ② 水爆环：实心带（内暗外亮），外沿不规则浪唇 + 一圈亮边；前 0.12 秒中心一圈白沫环
    const r = W * (0.22 + 0.78 * grow), th = Math.max(1, 3.5 * (1 - 0.7 * grow));
    if (fade < 0.97) ring(r, (a, ca, sa) => {
      const q = nz(a * 3.7, sd + 311);
      if (q < 0.18 + 0.7 * fade) return;                                       // 断口（越到后面越多，环散成几段）
      const lip = r * (1 + 0.14 * (nz(a * 5.3, sd + 313) - 0.5) * 2) + (q > 0.8 ? 2 : 0);
      for (let d = -th; d <= 0.5; d += 0.5) {
        const rr = lip + d, x = k.x + ca * rr, y = k.y + sa * rr * SY;
        const c = d > -0.6 ? (q > 0.62 ? WHITE : C[n - 2]) : d > -th * 0.5 ? C[n - 3] : C[n - 4];
        dotA(p, Math.round(x), Math.round(y), c, 1);
      }
    });
    if (t < 0.14) ring(r * 0.45, (a, ca, sa) => {
      if (nz(a * 6.1, sd + 315) < 0.3) return;
      dotA(p, Math.round(k.x + ca * r * 0.45), Math.round(k.y + sa * r * 0.45 * SY), WHITE, 1);
    });
    // ③ 水滴：地面小影子（跟着水滴走，离地越高影子越小越淡）+ 落地白点
    for (const d of crownDrops(k)) {
      const u = t - d.dl;
      if (u <= 0) continue;
      const fl = Math.min(u, d.T), gx = k.x + Math.cos(d.a) * d.v * fl, gy = k.y + Math.sin(d.a) * d.v * fl * SY;
      if (u < d.T) {
        const z = d.vz * u - 260 * u * u, sh = z > 14 ? 1 : 2;
        for (let i = 0; i < sh; i++) dotA(p, Math.round(gx) + i, Math.round(gy), C[0], 0.55);
      } else if (u < d.T + 0.2) {
        const c = u < d.T + 0.07 ? WHITE : C[n - 3];
        dotA(p, Math.round(gx), Math.round(gy), c, 1);
        if (d.big) dotA(p, Math.round(gx) + 1, Math.round(gy), c, 1);
      }
    }
    if (!k.raw) return;
  }
  // ④ 矮水冠：一圈往外翻的浪唇（先翻起、0.18 秒后往外倒下塌平），2–3 阶实色；背面先画（屏幕 y 小的先）
  const rc = W * (0.2 + 0.45 * grow), hc = Math.min(k.H, 16) * 0.7 * ease.outCubic(clamp(t / 0.1)) * (1 - smooth(0.16, 0.42, t));
  if (hc >= 1.5) {
    const cols = [];
    ring(rc, (a, ca, sa) => { if (nz(a * 4.9, sd + 321) > 0.38) cols.push([a, ca, sa]); });
    cols.sort((A, B) => A[2] - B[2]);
    for (const [a, ca, sa] of cols) {
      const hh = hc * (0.35 + 0.65 * Math.pow(nz(a * 2.3, sd + 323), 1.5));   // 高低差大：几处翻得高、其余贴着
      const back = sa < -0.2;
      for (let z = 0; z <= hh; z += 0.5) {
        const q = z / hh, out = 7 * q * q * (0.6 + 0.4 * grow);                // 越往上越往外翻
        const x = k.x + ca * (rc + out), y = k.y + sa * (rc + out) * SY - z;
        const c = q > 0.8 ? (back ? C[n - 2] : WHITE) : q > 0.4 ? C[n - 3] : C[n - 4];
        dotA(p, Math.round(x), Math.round(y), back && q <= 0.8 ? C[n - 5] : c, 1);
      }
      // 浪唇往外、往下卷一截
      const lx = k.x + ca * (rc + 4), ly = k.y + sa * (rc + 4) * SY - hh;
      for (let s2 = 1; s2 <= 3; s2++) dotA(p, Math.round(lx + ca * s2), Math.round(ly + s2 * 0.8), s2 === 1 && !back ? WHITE : C[n - 2], 1);
    }
  }
  // ⑤ 水滴 / 小水团：沿抛物线往外、往上，再落回（落地交给贴地层的白点）
  for (const d of crownDrops(k)) {
    const u = t - d.dl;
    if (u <= 0 || u >= d.T) continue;
    const z = d.vz * u - 260 * u * u;
    const x = k.x + Math.cos(d.a) * d.v * u, y = k.y + Math.sin(d.a) * d.v * u * SY - z;
    const c = u < 0.07 ? WHITE : z > 10 ? C[n - 2] : C[n - 3];
    dotA(p, Math.round(x), Math.round(y), c, 1);
    dotA(p, Math.round(x) + 1, Math.round(y), d.big ? c : C[n - 3], 1);
    if (d.big) { dotA(p, Math.round(x), Math.round(y) + 1, C[n - 3], 1); dotA(p, Math.round(x) + 1, Math.round(y) + 1, C[n - 4], 1); }
  }
}

function splash(p, t, o, C, ACC) {
  const el = +o.el, raw = o.view === "raw";
  crown(p, t, C, ACC, { x: 0, y: 0, W: +o.CW || +o.R * 0.5, H: +o.H, SY: raw ? 1 : +o.SY, seed: +o.seed * 7 + 31, raw, layer: o.layer || "up", nd: 8 + 2 * Math.min(3, el + 1) });
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
  // 落水水爆的贴地层（环 + 湿印 + 水滴影子 / 落地白点），同 splash 的参数（CW 两层一致）
  const el = +o.el;
  crown(p, t, C, ACC, { x: 0, y: 0, W: +o.CW || +o.R * 0.5, H: +o.H, SY: +o.SY, seed: +o.seed * 7 + 31, layer: "gd", nd: 8 + 2 * Math.min(3, el + 1) });
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

// S1 迅捷打击·γ型 = 竖斩（11-05 用户「迅捷打击和普攻太相似，换成竖斩和横斩」）：普攻是腰高的水平横斩，S1 是大剑从头顶后方竖着劈下来——
// 刀光是一道立在出手方向竖直平面里的月牙（肩高为轴、劈到身前地面），落地那一下：地上沿出手方向炸开一道直裂。
// 分档同普攻：E1 直裂变成发光的深海裂痕（刀收后还亮一会儿），E2 刀身压成深海暗色 + 内外海绿描边（刃变重）。
const VS_PIV = 22;   // 轴心离地高度（肩）
function vsweep(t) {
  const p0 = 125 * D2R, p1 = -22 * D2R, span = p0 - p1;   // 从头顶后方（125°）劈到身前地下（-22°，地面以下不画）
  const head = p0 - span * (0.5 + 0.5 * clamp(t / 0.067));
  const tail = p0 - span * 0.25 * smooth(0.07, 0.3, t);
  return [p0, head, tail, span];
}

function vslash(p, t, o, C, ACC) {
  const raw = o.view === "raw", Rv = +o.RV, W = +o.W, th = +o.dir * D2R, SY = raw ? 1 : +o.SY, el = +o.el, n = C.length;
  const [p0, head, tail] = vsweep(t);
  const hot = t < 0.13, cool = smooth(0.1, +o.dur, t);
  if (cool < 0.72 && tail - head > 0.03) {
    const cols = [];
    for (let ph = head; ph <= tail; ph += 0.35 / Rv) {
      const u = (tail - ph) / Math.max(0.001, tail - head);  // 0 刀尾（头顶后方）→ 1 刀头（劈下去那端）
      const wr = W * (1 - 0.7 * cool) * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.6)), 0.75);
      if (wr < 0.7) continue;
      for (let d = 0; d <= wr; d += 0.5) {
        const r = Rv - d, hz = r * Math.cos(ph), z = VS_PIV + r * Math.sin(ph);
        if (z < 0) continue;                                    // 劈进地面的部分不画
        const q = d / wr;
        let ci = q < 0.2 ? (hot ? n - 1 : n - 2) : q < 0.45 ? n - 2 : q < 0.7 ? n - 3 : n - 4;
        if (hot && u > 0.8 && q < 0.6) ci = n - 1;
        ci = clamp(ci - Math.round(cool * 2.5) - (u < 0.2 ? 1 : 0), 1, n - 1);
        let col = C[ci];
        if (el >= 2 && !hot) {                                  // 精二：刃变重
          if (q > 0.2 && q < 0.3) col = ACC;
          else if (q >= 0.3 && q < 0.86) col = C[clamp(ci - 2, 1, n - 1)];
          else if (q >= 0.86) col = ACC;
        }
        cols.push([Math.cos(th) * hz, Math.sin(th) * hz * SY - z, col]);
      }
    }
    for (const c of cols) p.px(Math.round(c[0]), Math.round(c[1]), c[2]);
    if (raw) p.light(Math.cos(th) * Rv * 0.6, -VS_PIV, C[n - 2], 0.5 * (1 - cool));
  }
  if (raw) return;
  // 落地矮浪（11-05 试过：读成另外几道刀光，和竖月牙撞了，关掉；S1 = 竖劈月牙 + 落点直裂 / 深海裂痕）
  const ti = t - 0.06;
  if (false && ti > 0) {
    const R = +o.R, g = ease.outCubic(clamp(ti / 0.28)), r = R * (0.4 + 0.6 * g), fade = smooth(0.18, 0.42, ti);
    if (fade < 0.99) {
      const pts = [];
      for (let a = -1.6; a <= 1.6; a += 0.4 / r) {
        if (nz(a * 2.2, o.seed + 931) < 0.14) continue;              // 少量断口（连续的一道矮水涌，不碎成块）
        const env = Math.pow(Math.cos(a / 1.6 * Math.PI / 2), 0.7);
        const h = (2.5 + 2.5 * nz(a * 3.1, o.seed + 933)) * env * (1 - fade) * clamp(ti / 0.05);
        const pa = a + th;
        pts.push({ x: Math.cos(pa) * r, y: Math.sin(pa) * r * SY, h, ca: Math.cos(pa), sa: Math.sin(pa) * SY, near: Math.sin(pa) });
      }
      pts.sort((A, B) => A.y - B.y);
      for (const q of pts) {
        if (q.h < 1) continue;
        const B = q.h * 2.2;
        for (let sb = -B; sb <= 0; sb += 0.5) {                // 内侧缓坡
          const u = (sb + B) / B, z = q.h * Math.pow(u, 1.6);
          if (u < 0.3 && nz(sb * 3 + q.x, o.seed + 935) < 0.5) continue;
          const ci = u < 0.5 ? n - 6 : u < 0.85 ? n - 5 : n - 4;   // 水波：暗、不发白（不跟竖月牙抢）
          p.px(Math.round(q.x + q.ca * sb), Math.round(q.y + q.sa * sb - z), C[clamp(ci - Math.round(fade * 2) - (q.near < -0.3 ? 1 : 0), 1, n - 1)]);
        }
        for (let z = 0; z <= q.h; z += 0.5) {                  // 外侧前脸
          const k = z / q.h, off = k * k * q.h * 0.3;
          const ci = k > 0.8 ? n - 3 : k > 0.4 ? n - 4 : n - 5;
          p.px(Math.round(q.x + q.ca * off), Math.round(q.y + q.sa * off - z), C[clamp(ci - Math.round(fade * 2) - (q.near < -0.3 ? 2 : 0), 1, n - 1)]);
        }
      }
    }
  }
}

// 竖斩地面：刀身投影一道直线阴影；落地后沿出手方向炸开一道直裂（几处小分叉），E0 / E1 白热后变暗；E1 起裂口芯发海绿光、刀收后还亮一会儿（深海裂痕）
function vslashGround(p, t, o, C, ACC) {
  if (o.view === "raw") return;
  const R = +o.R, Rv = +o.RV, th = +o.dir * D2R, SY = +o.SY, el = +o.el, n = C.length;
  const [p0, head] = vsweep(t);
  const cool = smooth(0.1, +o.dur, t);
  const reach = Math.sqrt(Math.max(0, Rv * Rv - VS_PIV * VS_PIV));   // 刀尖落地点
  if (cool < 0.72) for (let h = 4; h <= Math.min(reach, Rv * Math.max(0, Math.cos(head))); h += 1) {   // 刀身投影（跟着刀头往前）
    p.dot(Math.round(Math.cos(th) * h), Math.round(Math.sin(th) * h * SY), C[0], 0.45 * (1 - cool));
  }
  const ti = t - 0.06;
  if (ti <= 0) return;
  const grow = ease.outCubic(clamp(ti / 0.1)), glow = 1 - smooth(0.12, 0.5, t), fade = smooth(el >= 1 ? 0.42 : 0.25, el >= 1 ? 0.66 : 0.42, t);
  if (fade >= 0.99) return;
  const L = (reach - 4) + (R * 0.95 - reach + 4) * grow;
  const nx = -Math.sin(th), ny = Math.cos(th) * SY;
  for (let h = reach - 4; h <= reach - 4 + L; h += 0.5) {
    if (nz(h * 0.9, o.seed + 941) < fade) continue;
    const j = 2.2 * (nz(h * 0.45, o.seed + 943) - 0.5) * 2;   // 裂口左右摆
    const x = Math.round(Math.cos(th) * h + nx * j), y = Math.round(Math.sin(th) * h * SY + ny * j);
    const fresh = ti < 0.1;
    p.px(x, y + 1, C[0]);
    p.px(x, y - 1, C[0]);
    let core = fresh ? WHITE : C[1];
    if (el >= 1 && glow > 0.08 && nz(h * 1.7, o.seed + 945) > 0.2 * (1 - glow)) core = ACC;
    p.px(x, y, core);
    if (nz(h * 0.33, o.seed + 947) > 0.84) {                     // 小分叉
      const sg = nz(h, o.seed + 949) > 0.5 ? 1 : -1;
      for (let s = 1; s <= 3; s++) p.px(Math.round(x + Math.cos(th) * s * 0.6 + nx * sg * s), Math.round(y + Math.sin(th) * s * 0.6 * SY + ny * sg * s), s === 1 && core === ACC ? ACC : C[0]);
    }
  }
}


// S1 = 十字斩（11-05 用户「S1 可以是类似于十字斩，先竖着再横着，这样就不用改范围」）：先竖劈（vslash），
// 落地那一拍（0.12 秒后）接一道比普攻更宽的横扫月牙（弧 200°，对上前方 200° 判定），两刀在身前交成「十」字。
// 分档：E1 竖劈落点的直裂发光（深海裂痕）；E2 两刀都刃变重。横扫这一刀不另加裂痕（免得地上两道裂痕太乱）
const CROSS_DT = 0.12;
function cross(p, t, o, C, ACC) {
  vslash(p, t, o, C, ACC);
  const R = +o.R, W = +o.WH || +o.W;
  smear(p, t, Object.assign({}, o, { span: 3.5, H0: 12 }), C, ACC, false, { R, Wr: W, dt: CROSS_DT, dim: 0, edge: true });
}

function crossGround(p, t, o, C, ACC) {
  vslashGround(p, t, o, C, ACC);
  const tt = t - CROSS_DT;
  if (tt > 0) ribbonGround(p, tt, Object.assign({}, o, { span: 3.5, el: 0, W: +o.WH || +o.W, style: "basic" }), C, ACC, false);   // 横扫这一刀只要投影阴影
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
    case "cross": return gd ? crossGround(p, t, o, C, ACC) : cross(p, t, o, C, ACC);   // S1 十字斩
    case "vslash": return gd ? vslashGround(p, t, o, C, ACC) : vslash(p, t, o, C, ACC);   // S1 竖斩
    case "pool": return gd ? pool(p, t, o, C, ACC) : undefined;
    case "ring": return gd || o.view === "raw" ? ring(p, t, o, C, ACC) : undefined;
  }
}
