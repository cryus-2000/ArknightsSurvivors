// 水月 pixelfx 放开版公用画法（claude/pixelfx-ul-mizuki-claude）：色阶、触手、伞沿膜冠。只给 ak-mizuki-ul-*.js 用，不是独立特效。
// 色阶依据：PRTS 立绘主色宝蓝 / 藏青 + 伞的淡紫白（build/prts_ref/mizuki）。触手按用户 11-04 改成和立绘一致的宝蓝 → 淡紫（不照原作青绿身紫红尖）。
// 敌弹 #33ceff 色相 0.55：亮部一律偏紫（宝蓝 0.63–0.68、淡紫 0.70–0.74）；暗部是藏青，不带红，和危险色 #ff2667（0.95）拉开。
import { clamp, noise, hex, smooth } from "../../core/index.js";
import { OP } from "../house.js";

export const MZ = {
  blue: OP.mizuki,       // 色阶唯一来源 house.js OP.mizuki（§11.1 #12，组长 11-04 批：藏青 → 宝蓝 → 长春花蓝 → 白）
  lav: "#c4a6ff",        // 淡紫重点（精二）
  ink: "#080a18",        // 触手描边
  tent: ["#161c52", "#24348a", "#3854c2", "#5a76e6"],   // 触手身（藏青 → 宝蓝，暗 → 亮）
  tip: ["#5a52c4", "#8a7cee", "#bcaaff"],               // 触手尖（淡紫）
  suck: "#e2dcff",       // 吸盘
  bio: "#d2bcff",        // 精二荧光斑（淡紫）
};

// 二次贝塞尔
export function bez(a, c, b, u, c2) {
  const v = 1 - u;
  if (c2) return [v * v * v * a[0] + 3 * v * v * u * c[0] + 3 * v * u * u * c2[0] + u * u * u * b[0], v * v * v * a[1] + 3 * v * v * u * c[1] + 3 * v * u * u * c2[1] + u * u * u * b[1]];   // 三次：S 形
  return [v * v * a[0] + 2 * v * u * c[0] + u * u * b[0], v * v * a[1] + 2 * v * u * c[1] + u * u * b[1]];
}

/**
 * 触手：base → tip 的二次贝塞尔，ctrl 控制弯。from / to（0..1）= 画出的那一段（钻出 / 缩回）。
 * s = { w0 根部半宽, seed, el 精英档, hot 白热（0..1+）, dis 溶解（0..1，噪声阈值往上吃掉）, curl 尖端卷钩（0..1，精一拖拽）, glowK }
 * core：描边 + 身体 + 吸盘 + 尖；deco：精二荧光斑的光晕。
 */
export function tentacle(p, a, c, b, from, to, s, core, deco) {
  if (to - from < 0.02) return;
  let N = 0;
  { let L = 0, q = bez(a, c, b, from, s.c2); for (let i = 1; i <= 16; i++) { const r = bez(a, c, b, from + (to - from) * i / 16, s.c2); L += Math.hypot(r[0] - q[0], r[1] - q[1]); q = r; } N = Math.max(60, Math.ceil(L * 3)); }   // 采样按弧长：每格 3 个，拉长段不漏行（漏行会透出底下的暗洞成横纹）
  const tc = s.tent ? s.tent.map(hex) : MZ.tent.map(hex), tp = MZ.tip.map(hex), ink = hex(MZ.ink), suck = hex(MZ.suck), bio = hex(MZ.bio), white = hex("#ffffff");
  const pts = [];
  for (let i = 0; i <= N; i++) {
    const u = from + (to - from) * i / N;
    let [x, y] = bez(a, c, b, u, s.c2);
    if (s.curl > 0 && u > 0.78) {   // 尖端卷钩：最后一段绕一圈往回勾
      const k = (u - 0.78) / 0.22, [x0, y0] = bez(a, c, b, 0.78, s.c2), [x1, y1] = bez(a, c, b, 0.8, s.c2);
      const dx = x1 - x0, dy = y1 - y0, L = Math.hypot(dx, dy) || 1, tx = dx / L, ty = dy / L, sg = s.cs || 1;
      const R = 5 * s.curl, ang = k * Math.PI * 1.5 * s.curl;
      x = x0 + tx * Math.sin(ang) * R * 1.3 + -ty * sg * (1 - Math.cos(ang)) * R;
      y = y0 + ty * Math.sin(ang) * R * 1.3 + tx * sg * (1 - Math.cos(ang)) * R;
    }
    pts.push([x, y, u]);
  }
  const geo = pts.map(([x, y, u], i) => {
    const q = pts[Math.min(pts.length - 1, i + 1)], r = pts[Math.max(0, i - 1)];
    let nx = -(q[1] - r[1]), ny = q[0] - r[0];
    const L = Math.hypot(nx, ny) || 1;
    return [x, y, u, nx / L, ny / L, Math.max(0.6, s.w0 * Math.pow(1 - u, 1.15) * (1 + 0.12 * noise(u * 9, s.seed)))];
  });
  if (core && s.pass !== "body") for (const [x, y, u, nx, ny, w] of geo)   // 第一遍：描边（整条先画，身体再盖上去，交界不出竖纹）；pass = ink / body 时只画一遍（多根触手先全描边再全画身，互相压不出条纹）
    for (let d = -w - 1; d <= w + 1; d += 0.5) p.px(x + nx * d, y + ny * d, ink);
  if (s.pass === "ink") return;
  for (let i = 0; i < geo.length; i++) {
    const [x, y, u, nx, ny, w] = geo[i];
    if (s.dis > 0 && noise(u * 14, s.seed + 5) * 0.5 + 0.5 < s.dis * 1.1 - 0.05) continue;   // 溶解：一节节断开散掉
    for (let d = -w; d <= w; d += 0.5) {
      const px = x + nx * d, py = y + ny * d;
      if (!core) continue;
      const top = -d / w;   // 朝上一侧受光
      let ci = clamp(Math.round(1.5 + 1.5 * top + 0.5 * noise(u * 5, s.seed + 3)), 0, 3);   // 只按受光面分阶（高频噪声会在根部出横纹）
      let col = u > 0.62 ? tp[clamp(ci - 1, 0, 2)] : tc[ci];
      if (s.hot > 0.9 && top > 0.45) col = white;   // 白热只在受光一侧的一道边
      else if (s.hot > 0.3 && top > 0.55) col = hex(MZ.blue[6]);
      p.px(px, py, col);
    }
    // 吸盘：下侧不等距的小亮点
    if (core && w > 1.4 && u < 0.85 && noise(u * 31, s.seed + 11) > 0.1 && i % 6 === 0) { p.px(x - nx * (w - 0.6), y - ny * (w - 0.6), suck); if (w > 3) p.px(x - nx * (w - 1.6), y - ny * (w - 1.6), tc[3]); }
    // 精二荧光斑（核心一格亮点 + 装饰光晕）
    if (s.el >= 2 && u > 0.15 && u < 0.8 && noise(u * 11, s.seed + 23) > 0.45 && i % 9 === 0) {
      if (core) p.px(x + nx * w * 0.3, y + ny * w * 0.3, bio);
      if (deco) p.glow(x, y, 6, bio, 0.22 * (s.glowK ?? 1));
    }
  }
}

/**
 * 伞沿膜冠：一道新月，外缘是一圈不规整的小褶（像水母伞缘），内侧半透明膜。
 * s = { R, W, seed, ramp(数字色), hot, edgeHot, age } ；ang0..ang0+span（span 可负）
 */
export function membrane(p, s, ang0, span, age, hot, core, deco, ox = 0, oy = 0) {
  if (Math.abs(span) < 0.02 || s.W < 0.5) return;
  const R = s.ramp, n = R.length, dir = Math.sign(span), L = Math.abs(span), B = s.R + 5;
  if (core) p.shade(ox - B, oy - B, ox + B, oy + B, (x, y, out) => {
    const r = Math.hypot(x - ox, y - oy), ang = Math.atan2(y - oy, x - ox);
    let u = (dir * (ang - ang0)) % (Math.PI * 2);
    if (u < 0) u += Math.PI * 2;
    if (u > L) return;
    const v = u / L;
    const scal = (s.scal ?? 2.0) * Math.abs(noise(ang * s.R / 3.2, s.seed)) + 0.9 * noise(ang * 13, s.seed + 9);   // 伞缘小褶：全用 noise（外缘不用周期正弦，docs/242 §1）
    const Rr = s.R + scal * (0.6 + age);
    const w = s.W * Math.pow(Math.sin(Math.PI * Math.pow(v, 1.8)), 0.55);
    if (w < 0.4 || r > Rr + 0.5 || r < Rr - w) return;
    const q = (Rr - r) / w;
    if (Rr - r < 1.1 && age < 0.75) {   // 外缘 1 格亮线（精二：断续几段淡紫）
      out.c = s.lav && noise(ang * 6, s.seed + 31) > 0.15 && hot < 1 ? s.lav : R[hot > 0.5 ? n - 1 : n - 2];
      return;
    }
    const ci = Math.round(q * (n - 2) * 0.8 + age * 3 - hot * 2 + 0.5);
    out.c = R[n - 2 - clamp(ci, 0, n - 2)];
    out.a = q > 0.55 ? 0.55 : 0.9;   // 膜往里越来越透
  });
  if (deco) for (let u = 0; u <= L; u += 0.2) {
    const a = ang0 + dir * u;
    p.glow(ox + Math.cos(a) * (s.R - s.W * 0.4), oy + Math.sin(a) * (s.R - s.W * 0.4), 9 + s.W, R[n - 3], (0.26 * (1 - age) * (u / L) + 0.05 * hot) * (s.GK ?? 1));
  }
}

/**
 * 伞缘垂下的丝须：从膜冠外缘几处垂下 / 拖在后面的细线（1 格），慢慢飘。
 */
export function threads(p, pts, t, col, a = 1) {
  for (const th of pts) {
    const k = clamp((t - th.t0) / 0.08) * (1 - smooth(th.t1 - 0.12, th.t1, t));
    if (k <= 0) continue;
    let x = th.x, y = th.y;
    const len = th.len * k;
    for (let d = 0; d < len; d += 0.6) {
      const w = Math.sin(d * 0.35 + t * 9 + th.ph) * (d / th.len) * 2.2;
      x = th.x + th.dx * d + -th.dy * w;
      y = th.y + th.dy * d + th.dx * w;
      if (a >= 1) p.px(x, y, col); else p.dot(x, y, col, a * (1 - d / len * 0.6));
    }
  }
}
