// 能天使精一「穿甲连射」叠满后的命中（docs/229 §9 D 组）：@2x 密度，原点 = 命中点，子弹从左边来。替换 Codex fx_exusiai_pierce_gold。
// 和普通命中的区别是「打穿」：一道细长白热芯顺着弹道刺过目标，背面喷出一束金色火星，前方两段断弧，不对称、不等长。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Exusiai pierce",
  desc: "A piercing bullet hit: a thin white-hot lance stabs through along the shot, a cone of gold sparks bursts out the far side and two broken arcs snap open, then cool and scatter.",
  tags: ["impact", "hit", "bullet", "pierce", "one-shot"],
  size: [56, 40],
  origin: [28, 20],
  duration: 0.22,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#2a1a06", "#7a4c0e", "#d89a2a", "#ffd76a", "#fff3cc", "#ffffff"], seed: 8 },
};

export function create(o) {
  const C = fit(o.palette, 6), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  for (let i = 0; i < 9; i++) {
    const a = Rg.range(-0.55, 0.55), sp = Rg.range(90, 200);
    ps.spawn(P.SPARK, 3, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.06, 0.16));
  }
  for (let i = 0; i < 2; i++) ps.spawn(P.SPARK, -1, 0, -Rg.range(60, 110), Rg.range(-40, 40), Rg.range(0.05, 0.09));
  const arcs = [[-1.1, -0.35], [0.2, 0.9]].map(([a0, a1]) => [a0 + Rg.range(-0.12, 0.12), a1 + Rg.range(-0.12, 0.12)]);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const k = 1 - clamp(t / 0.07);
      if (k > 0) {
        // 穿刺芯：后短前长，芯白、两边金
        const L0 = 7 * k, L1 = 20 * ease.outExpo(clamp(t / 0.03 + 0.4)) * (0.5 + 0.5 * k);
        for (let x = -L0; x <= L1; x += 0.5) {
          const u = x < 0 ? -x / L0 : x / L1;
          p.px(x, 0, C[u < 0.35 && k > 0.6 ? 5 : u < 0.7 ? 4 : 3]);
          if (u < 0.5 && k > 0.5) { p.px(x, -1, C[3]); p.px(x, 1, C[2]); }
        }
        p.poly([[0, -2.2], [2.6, 0], [0, 2.2], [-1.6, 0]], C[k > 0.6 ? 5 : 3]);
      }
      const r = 4 + 9 * ease.outQuart(clamp(t / 0.14)), ak = 1 - clamp((t - 0.03) / 0.14);
      if (ak > 0) for (const [a0, a1] of arcs) p.arc(4, 0, r, 1, a0, a1, C[ak > 0.75 ? 4 : 2], ak);
      p.glow(2, 0, 11, C[3], 0.3 * k);
      ps.draw(p);
    },
  };
}
