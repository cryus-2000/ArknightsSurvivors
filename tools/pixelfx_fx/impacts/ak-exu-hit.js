// 能天使技能命中（docs/228 §7 试点）：@2x 密度，原点 = 命中点。子弹从左边来。
import { Particles, P, Rng, fit, sparkle, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Exusiai hit",
  desc: "A small bullet hit: a white diamond pops, a lopsided cross flares along the shot, a broken arc snaps out ahead and sparks spray onward and fade.",
  tags: ["impact", "hit", "bullet", "spark", "one-shot"],
  size: [40, 40],
  origin: [16, 20],
  duration: 0.3,
  loop: false,
  fps: 25,
  bg: "dark",
  options: { palette: ["#0a2240", "#12528a", "#48ccff", "#b8f2ff", "#f0fdff", "#ffffff"], seed: 4 },
};

export function create(o) {
  const C = fit(o.palette, 6), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  for (let i = 0; i < 7; i++) {
    const a = Rg.range(-0.9, 0.9), sp = Rg.range(90, 230);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.08, 0.18));
  }
  // 前方一段断弧：不等长、不对称
  const arcs = [[-1.0, -0.45], [-0.25, 0.35], [0.55, 0.95]].map(([a0, a1]) => [a0 + Rg.range(-0.1, 0.1), a1 + Rg.range(-0.1, 0.1)]);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const pop = 1 - clamp(t / 0.07);
      if (pop > 0) {
        // 偏心十字闪：顺着射击方向的那条最长
        const L = 9 * ease.outBack(Math.min(1, t / 0.02 + 0.3)) * pop;
        for (const [dx, dy, l] of [[1, 0, L], [-1, 0, L * 0.45], [0, -1, L * 0.5], [0, 1, L * 0.4]])
          for (let d = 0; d <= l; d += 0.5) p.dot(dx * d, dy * d, d < l * 0.25 ? C[5] : d < l * 0.6 ? C[4] : C[2], d > l * 0.7 ? 0.6 : 1);
        p.poly([[0, -1.6], [1.6, 0], [0, 1.6], [-1.6, 0]], C[5]);
      }
      const r = 3 + 8 * ease.outQuart(clamp(t / 0.14)), ak = 1 - clamp((t - 0.04) / 0.14);
      if (ak > 0) for (const [a0, a1] of arcs) p.arc(0, 0, r, 1, a0, a1, C[ak > 0.5 ? 4 : 2], ak);
      p.glow(0, 0, 10, C[2], 0.45 * pop);
      ps.draw(p);
    },
  };
}
