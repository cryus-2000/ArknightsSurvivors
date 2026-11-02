// 能天使普攻命中（docs/231 普攻试点）：@2x 密度，原点 = 命中点。游戏里命中贴图不旋转，所以不画方向，只做不对称。
// 旧版是一个规整的红圈（同心圈被否的那类）；这里是一颗白芯、长短不一的四芒、两截断弧和几粒火星，0.16 秒内收完。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Exusiai rapid hit",
  desc: "A small rapid-fire hit: a white pip pops into a lopsided four-point star, two broken arc chips flick out and a few red sparks scatter, all gone in a sixth of a second.",
  tags: ["impact", "hit", "bullet", "spark", "one-shot"],
  size: [32, 32],
  origin: [16, 16],
  duration: 0.16,
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: { palette: OP.exusiai, seed: 6 },
};

export function create(o) {
  const C = fit(o.palette, 6), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  for (let i = 0; i < 5; i++) {
    const a = Rg.range(0, Math.PI * 2), sp = Rg.range(80, 170);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.06, 0.13));
  }
  // 四芒长短不一、略歪
  const rot = Rg.range(-0.25, 0.25), arms = [1, 0.55, 0.8, 0.45].map((k, i) => [rot + i * Math.PI / 2 + Rg.range(-0.08, 0.08), 9 * k]);
  const chips = [[Rg.range(-2.4, -1.8), 0.7], [Rg.range(0.2, 0.8), 0.55]];
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const pop = 1 - clamp(t / 0.08);
      if (pop > 0) {
        const g = ease.outBack(Math.min(1, t / 0.025 + 0.35)) * pop;
        for (const [a, l] of arms) {
          const L = l * g, ca = Math.cos(a), sa = Math.sin(a);
          for (let d = 0; d <= L; d += 0.5) p.dot(ca * d, sa * d, d < L * 0.3 ? C[5] : d < L * 0.65 ? C[4] : C[2], d > L * 0.75 ? 0.6 : 1);
        }
        p.poly([[0, -2.2], [2.2, 0], [0, 2.2], [-2.2, 0]], C[5]);
      }
      const r = 3 + 6 * ease.outQuart(clamp(t / 0.12)), ak = 1 - clamp((t - 0.03) / 0.11);
      if (ak > 0) for (const [a, s] of chips) p.arc(0, 0, r, 1, a, a + s, C[ak > 0.5 ? 3 : 2], ak);
      p.glow(0, 0, 8, C[2], 0.3 * pop);
      ps.draw(p);
    },
  };
}
