// 铃兰精二大狐火走过的灼地（5 帧，游戏按该点寿命 1 s 播完；@2x，原点 = 地面点，透视 sy 0.5）：
// 一小片不规整的狐火贴地烧，两三条火舌高矮不一，逐帧变矮变暗、按噪声碎成几点余烬。
import { Rng, fit, clamp, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran fox trail",
  desc: "A patch of foxfire left on the ground by Suzuran's great fox: a few uneven flames burn low, then shrink, darken and crumble to embers.",
  tags: ["holy", "fire", "foxfire", "floor", "one-shot"],
  size: [36, 36],
  origin: [18, 24],
  duration: 1.0,
  loop: false,
  fps: 5,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 3 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), S = o.seed;
  const fl = [];
  for (let i = 0, n = Rg.int(2, 3); i < n; i++) fl.push({ x: Rg.range(-6, 6), h: Rg.range(7, 13), w: Rg.range(1.8, 3) });
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const u = clamp(t / 0.9);
      if (u >= 1) return;
      p.shade(-12, -6, 12, 6, (x, y) => {
        const d = Math.hypot(x / 10, y / 5) * (1 + 0.25 * noise(Math.atan2(y, x) * 2.7, S));
        if (d > 1 - 0.3 * u) return;
        if (noise2(x * 0.4, y * 0.6, S + 3) * 0.5 + 0.5 < u * 0.8) return;
        p.blend(x, y, C[clamp(Math.round(3.6 - d * 2 - u * 2), 0, 4)], 0.7);
      });
      for (const f of fl) {
        const h = f.h * (1 - 0.8 * u);
        for (let d = 0; d < h; d += 0.5) {
          const v = d / h, w = (1 - v) * f.w * (1 - 0.4 * u);
          for (let q = -w; q <= w; q += 1) p.px(f.x + q + Math.sin(v * 3 + t * 9) * 0.7, -d, C[clamp(Math.round((t < 0.2 ? 5.6 : 4.8) - v * 2 - u * 2.5), 1, 6)]);
        }
      }
    },
  };
}
