// 铃兰狐火汇聚（原作：三团狐火合而为一再射出；0.25 s @24，@2x，原点 = 汇聚点）：
// 三团大小不一的狐火从不等距的方向打着旋卷向中心，越近越亮，合到一处时一点白芯闪一下，散开几点火星。
import { Particles, P, Rng, fit, clamp, ease, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran foxfire gather",
  desc: "Three uneven foxfires swirl in from different directions, brighten as they close and merge into one white-hot spark.",
  tags: ["holy", "fire", "foxfire", "charge", "one-shot"],
  size: [56, 56],
  origin: [28, 28],
  duration: 0.25,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 2 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  const fx = [];
  let a = Rg.range(0, TAU);
  for (let i = 0; i < 3; i++) { a += Rg.range(1.5, 2.7); fx.push({ a, r: Rg.range(17, 24), s: Rg.range(3, 4.5), tw: Rg.range(1.2, 2) }); }
  let t = 0, popped = false;
  return {
    update(dt) {
      t += dt;
      if (!popped && t > 0.15) {
        popped = true;
        for (let i = 0; i < 5; i++) { const b = Rg.range(0, TAU), sp = Rg.range(60, 140); ps.spawn(P.SPARK, 0, 0, Math.cos(b) * sp, Math.sin(b) * sp, Rg.range(0.05, 0.09)); }
      }
      ps.update(dt);
    },
    draw(p) {
      const u = clamp(t / 0.15);
      if (u < 1)
        for (const f of fx) {
          const k = ease.inQuad(u), r = f.r * (1 - k), an = f.a + f.tw * k, x = Math.cos(an) * r, y = Math.sin(an) * r;
          const s = f.s * (1 - 0.4 * k);
          for (let d = 0; d < s * 2.2; d += 0.5) {
            const v = d / (s * 2.2), w = (1 - v) * s * 0.7;
            for (let q = -w; q <= w; q += 1) p.px(x + q, y - d + s * 0.6, C[clamp(Math.round(3 + 2 * k + (1 - v) - (t < 0.04 ? 0 : 0.5)), 2, 5)]);
          }
        }
      const g = clamp((t - 0.12) / 0.05) * (1 - clamp((t - 0.17) / 0.06));
      if (g > 0) { p.disc(0, 0, 1.5 + 2.5 * g, C[4], 0.95); p.px(0, 0, C[6]); }   // 白只在芯一点
      p.glow(0, 0, 10, C[4], 0.25 * g);
      ps.draw(p);
    },
  };
}
