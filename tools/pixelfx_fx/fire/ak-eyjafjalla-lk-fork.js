// 艾雅法拉连携砸地的熔缝（静帧，@2x 112×32，原点 = 左端中点；游戏按长度横向拉、纵向压 0.55 / 0.85，从左往右逐段长出、由热色冷到暗色）。
// 一条参差折线主缝（宽窄随噪声），中途分一两个短叉；芯亮、边暗。seed 出四种。
import { Rng, fit, clamp, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla link fork crack",
  desc: "A molten fissure for Eyjafjalla's link slam: a jagged glowing main crack of uneven width with one or two short forks.",
  tags: ["fire", "lava", "crack", "floor", "still"],
  size: [112, 32],
  origin: [0, 16],
  duration: 0.05,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.eyjafjalla, seed: 1 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed * 7 + 3), S = o.seed;
  const seg = (x0, y0, x1, y1, w0, w1) => {
    const n = Math.ceil(Math.hypot(x1 - x0, y1 - y0) * 2);
    for (let i = 0; i <= n; i++) {
      const u = i / n, x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u, w = (w0 + (w1 - w0) * u) * (0.75 + 0.35 * (0.5 + 0.5 * noise(x * 0.3, S + 5)));
      for (let q = -w - 1; q <= w + 1; q += 0.5) {
        const k = Math.abs(q) / (w + 1);
        p.px(x, y + q, C[k < 0.35 ? 5 : k < 0.7 ? 3 : 1]);
      }
    }
  };
  let x = 0, y = 0, w = 3.2;
  const pts = [[0, 0]];
  while (x < 108) { x += Rg.range(9, 18); y = clamp(y + Rg.range(-5, 5), -11, 11); pts.push([Math.min(x, 108), y]); }
  for (let i = 1; i < pts.length; i++) { const w1 = w * (1 - (i / pts.length) * 0.75); seg(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], w, w1); w = w1; }
  for (let f = 0, n = Rg.int(1, 2); f < n; f++) {
    const i = Rg.int(1, pts.length - 2), fx = pts[i][0], fy = pts[i][1], d = Rg.sign();
    seg(fx, fy, fx + Rg.range(10, 20), clamp(fy + d * Rg.range(6, 10), -14, 14), 1.2, 0.3);
  }
}
