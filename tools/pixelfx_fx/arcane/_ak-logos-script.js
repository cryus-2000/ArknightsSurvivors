// 逻各斯「咒文」共用画法（ak-logos-glyph / -glyphs / -script / -rune / -ribbon / -slow / -aura / -chain 等共用；下划线开头 = 不是独立特效）。
// 一个「字」= 2–4 笔：竖、横、斜、钩、点、短弧里随机挑，笔长和位置随机——像咒文、不是任何可读文字。
// 笔画亮紫（本人色阶第 4–5 阶）、右下一像素墨影（第 0 阶）；k < 1 时按笔序只画前一部分（写出来的过程）。
import { Rng, fit, clamp } from "../../core/index.js";

export function strokes(seed, n0 = 2, n1 = 4) {
  const R = new Rng(seed * 13 + 7), out = [];
  for (let i = 0, n = R.int(n0, n1); i < n; i++) {
    const kind = R.pick(["v", "h", "d", "hook", "dot", "arc"]);
    out.push({ kind, x: R.range(-0.35, 0.35), y: R.range(-0.4, 0.4), l: R.range(0.35, 0.8), s: R.sign(), a: R.range(0.4, 1.2) });
  }
  return out;
}

// 在 (cx, cy) 画一个 w × h 的字；k = 写到第几成（0–1）；hi = 亮度阶（缺省 4）；keep(x, y) 返回 false 的像素不画
export function glyph(p, palette, cx, cy, w, h, seed, k = 1, hi = 4, keep = null) {
  const C = fit(palette, 7), st = strokes(seed);
  const put = (x, y, c) => { if (keep && !keep(cx + x, cy + y)) return; p.px(cx + x + 1, cy + y + 1, C[0]); p.px(cx + x, cy + y, c); };   // keep：溶解时按位置挖掉
  const line = (x0, y0, x1, y1, c) => {
    const n = Math.max(1, Math.ceil(Math.hypot(x1 - x0, y1 - y0) * 1.5));
    for (let i = 0; i <= n; i++) put(x0 + ((x1 - x0) * i) / n, y0 + ((y1 - y0) * i) / n, c);
  };
  st.forEach((s, i) => {
    const u = clamp(k * st.length - i);
    if (u <= 0) return;
    const c = C[clamp(hi, 1, 4)], x = s.x * w, y = s.y * h, L = s.l * u;   // 最亮只到第 5 阶（下标 4）：逻各斯第 6 阶 #dce0ff 按近白算
    switch (s.kind) {
      case "v": line(x, y - (L * h) / 2, x, y + (L * h) / 2, c); break;
      case "h": line(x - (L * w) / 2, y, x + (L * w) / 2, y, c); break;
      case "d": line(x - (L * w) / 2, y - (s.s * L * h) / 2, x + (L * w) / 2, y + (s.s * L * h) / 2, c); break;
      case "hook": line(x, y - (L * h) / 2, x, y + (L * h) / 3, c); line(x, y + (L * h) / 3, x + (s.s * L * w) / 3, y + (L * h) / 2, c); break;
      case "dot": put(Math.round(x), Math.round(y), c); break;
      case "arc": for (let a = 0; a < s.a * 3 * u; a += 0.25) put(x + Math.cos(a * s.s) * w * 0.18, y + Math.sin(a * s.s) * h * 0.18, c); break;
    }
  });
}

// 墨链一节：横环（椭圆圈）或竖环（侧看成一道短竖），w / h 为环外径；hi 亮度阶。环身墨色、上沿一线紫光
export function link(p, palette, cx, cy, w, h, side, hi = 3) {
  const C = fit(palette, 7);
  if (side) {
    for (let y = -h / 2; y <= h / 2; y += 0.5) { p.px(cx, cy + y, C[1]); p.px(cx + 1, cy + y, C[0]); }
    p.px(cx, cy - h / 2, C[hi]);
    return;
  }
  for (let a = 0; a < 6.283; a += 0.12) {
    const x = cx + Math.cos(a) * w / 2, y = cy + Math.sin(a) * h / 2;
    p.px(x, y, Math.sin(a) < -0.3 ? C[hi] : C[1]);
    p.px(x + 0.5, y + 1, C[0]);
  }
}
