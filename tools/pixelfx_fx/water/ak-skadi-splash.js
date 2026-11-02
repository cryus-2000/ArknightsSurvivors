// 斯卡蒂专属小水花（docs/229，替共用的 fx_splash_blue）：1x 52×42，@18，底部锚（bottom）。
// 水从脚下溅起：首帧白点，几股高矮不一、往两侧斜的水柱，顶端甩出水珠落回，根部一圈不齐的浅水，深海色阶。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Skadi splash",
  desc: "Small deep-sea splash from the ground: a white pinpoint, a few uneven jets leaning outward, droplets thrown and falling back, a ragged ring of shallow water at the root.",
  tags: ["water", "splash", "one-shot"],
  size: [52, 44],
  origin: [26, 40],
  duration: 0.6,
  loop: false,
  fps: 18,
  bg: "dark",
  options: { palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"], seed: 4 },
};

const JETS = [[-6, -0.5, 13, 1.4], [-1, -0.12, 20, 1.8], [4, 0.28, 16, 1.5], [9, 0.62, 9, 1.1]];   // [x, 斜度, 高, 宽]
export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const W = C[C.length - 1]; for (let i = 6; i < C.length; i++) C[i] = C[5];   // 近白 ≤ 12%（docs/229 §2.4）：本体只到第 5 阶，白只留核心（W）
  for (const [x, lean, h] of JETS)
    for (let i = 0; i < 2; i++) ps.spawn(P.SPARK, x + lean * h, -h, lean * 60 + Rg.range(-25, 25), -Rg.range(40, 100), Rg.range(0.2, 0.3), 0, 1, 0.08 + Rg.range(0, 0.06));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      if (t < 0.06) p.disc(0, -2, 2.5, C[7], 0.9);
      for (const [x, lean, h, w] of JETS) {
        const rise = ease.outQuart(clamp(t / 0.12)) * (1 - clamp((t - 0.16) / 0.2)), H = h * rise;
        if (H < 0.5) continue;
        for (let d = 0; d <= H; d += 0.5) {
          const v = d / Math.max(H, 1), hw = w * (1 - v * 0.7);
          for (let e = -hw; e <= hw; e += 0.7) p.blend(x + lean * d + e, -d, C[clamp(Math.round(3 + v * 4 - Math.abs(e)), 2, 7)], v > 0.8 ? 0.95 : 0.75);
        }
      }
      const pr = 1 - clamp((t - 0.25) / 0.2);   // 根部浅水：半径按角度起伏（非等距波）
      if (pr > 0) for (let a = 0; a < Math.PI * 2; a += 0.12) {
        const r = (7 + 4 * ease.outQuart(clamp(t / 0.2))) * (1 + 0.2 * Math.sin(a * 3.7 + 1)), x = Math.cos(a) * r, y = Math.sin(a) * r * 0.35;
        p.blend(x, y - 1, C[Math.sin(a) > 0 ? 5 : 3], 0.7 * pr);
      }
      ps.draw(p);
    },
  };
}
