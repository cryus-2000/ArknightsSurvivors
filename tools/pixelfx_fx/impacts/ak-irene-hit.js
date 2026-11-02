// 艾丽妮刺击命中 / 剑尖星芒（docs/229 §3 普攻档，D 组）：@2x 密度，原点 = 命中点，刺击从左边来（游戏按刺击方向旋转）。
// 命中：偏心十字闪顺着刺击方向最长，前方一段断弧，火星集中往前喷。star: 1 时是剑尖星芒：只有一个长短不一的四芒闪，不带断弧。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Irene hit",
  desc: "A rapier hit: a lopsided cross flare longest along the thrust, a broken arc ahead and sparks sprayed forward; star mode is just an uneven four-point glint.",
  tags: ["impact", "hit", "rapier", "one-shot"],
  size: [44, 40],
  origin: [20, 20],
  duration: 0.2,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#06142a", ...OP.irene], star: 0, seed: 4 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), star = +o.star > 0;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[3]] });
  if (!star) for (let i = 0; i < 6; i++) {
    const a = Rg.range(-0.8, 0.8), sp = Rg.range(80, 200);
    ps.spawn(P.SPARK, 1, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.06, 0.14));
  }
  const arcs = [[-1.0, -0.4], [-0.1, 0.5]].map(([a0, a1]) => [a0 + Rg.range(-0.15, 0.15), a1 + Rg.range(-0.15, 0.15)]);
  const arms = star ? [[1, 0, 9], [-1, 0, 5], [0, -1, 7], [0, 1, 4]] : [[1, 0, 11], [-1, 0, 4], [0, -1, 5], [0, 1, 3.5]];
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const pop = 1 - clamp(t / (star ? 0.12 : 0.08));
      if (pop > 0) {
        const s = ease.outBack(Math.min(1, t / 0.02 + 0.4)) * pop;
        for (const [dx, dy, l] of arms)
          for (let d = 0; d <= l * s; d += 0.5) {
            const u = d / (l * s);
            p.px(dx * d, dy * d, C[t < 0.04 ? (u < 0.5 ? 7 : 6) : u < 0.3 ? 6 : u < 0.65 ? 5 : 3]);
          }
        p.poly([[0, -1.6], [1.8, 0], [0, 1.6], [-1.6, 0]], C[t < 0.05 ? 7 : 5]);
      }
      if (!star) {
        const r = 3 + 8 * ease.outQuart(clamp(t / 0.12)), ak = 1 - clamp((t - 0.03) / 0.12);
        if (ak > 0) for (const [a0, a1] of arcs) p.arc(2, 0, r, 1, a0, a1, C[ak > 0.6 ? 5 : 3], ak);
      }
      p.glow(0, 0, 9, C[4], 0.3 * pop);
      ps.draw(p);
    },
  };
}
