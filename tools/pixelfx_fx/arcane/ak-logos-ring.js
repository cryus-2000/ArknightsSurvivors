// 逻各斯 S1 落点墨环（docs/229 技能档）：@2x，1 贴图像素 = 1 世界像素，原点 = 落点，地面透视 sy 0.55，外沿半径 radius。
// 墨从落点洇开成一圈不规整的墨环，外沿一道紫亮的边先冷，墨面上几处墨点按噪声鼓起又塌下；
// 只有一圈，最后墨按噪声干涸溶解。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos ink ring",
  desc: "Ink bleeds out from the mark into one ragged ring on the floor, its violet rim flares then cools, blobs bulge and sink, and the ink dries away.",
  tags: ["arcane", "ink", "ring", "floor", "one-shot"],
  size: [140, 84],
  origin: [70, 42],
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.logos, radius: 56, seed: 5 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), R = o.radius, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[4], C[2], C[1]] });
  for (let a = Rg.range(0, 0.5); a < TAU; a += Rg.range(0.6, 1.5))
    ps.spawn(P.SPARK, Math.cos(a) * R * 0.5, Math.sin(a) * R * 0.5 * SY, Math.cos(a) * Rg.range(40, 90), Math.sin(a) * Rg.range(20, 45) - 20, Rg.range(0.1, 0.2), 0, 1, 0.03);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const k = 1 - smooth(0.22, 0.44, t), r = R * (0.4 + 0.6 * ease.outQuart(clamp(t / 0.14)));
      if (k > 0)
        p.shade(-r * 1.3, -r * SY * 1.3, r * 1.3, r * SY * 1.3, (x, y) => {
          const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (r * (1 + 0.12 * noise(a * 3.7, S) + 0.06 * noise(a * 9.1, S + 2)));
          if (d > 1) return;
          if (noise2(x * 0.22, y * 0.4, S + 4) * 0.5 + 0.5 > k + 0.25) return;
          const rim = d > 0.88 - 0.05 * noise(a * 6.3, S + 3);
          // 墨面：只在外沿一带有墨（内圈留空，像墨洇开），墨点按噪声鼓起
          const blob = noise2(x * 0.15, y * 0.28, S + 7);
          if (!rim && d < 0.45 + 0.25 * blob) return;
          const ci = t < 0.04 ? (rim ? 5 : 4) : rim ? clamp(Math.round(5 - t / 0.05 * 0.7), 1, 5) : clamp(Math.round(1 + Math.max(0, blob) * 1.5 - t / 0.2), 0, 2);
          p.blend(x, y, C[ci], rim ? 1 : 0.8);
        });
      ps.draw(p);
    },
  };
}
