// 能天使命中（pixelfx 放开版，docs/242）：1x，原点 = 命中点，子弹从左边来。
// 白热爆点 + 顺射击方向最长的偏心十字闪 → 前方几段长短不一的断弧 → 火星朝前喷、碎屑落下；光晕放开（k 0.6）。
import { Particles, Lights, P, Rng, fit, sparkle, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Exusiai hit unleashed",
  desc: "A punchy bullet hit: a white-hot pop with a lopsided cross flaring along the shot, broken arcs snapping out ahead and sparks spraying onward.",
  tags: ["impact", "hit", "bullet", "spark", "one-shot"],
  size: [64, 56],
  origin: [24, 28],
  duration: 0.35,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#3a0a10", "#7c1622", "#c4283a", "#f24d4d", "#ff9a8a", "#ffd8cc", "#ffffff"], layer: "all", seed: 4 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";   // 分层（docs/242 §8）
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  lights.add(0, 0, 22, C[5], 0.9, 0.18);
  for (let i = 0; i < 12; i++) {
    const a = Rg.range(-1.0, 1.0) * (i % 3 ? 0.7 : 1.3), sp = Rg.range(110, 300);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.08, 0.24));
  }
  const arcs = [];
  for (let a = -1.2 + Rg.range(0, 0.2); a < 1.1; a += Rg.range(0.45, 0.8)) arcs.push([a, a + Rg.range(0.15, 0.4), Rg.range(0.85, 1.15)]);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      const pop = 1 - clamp(t / 0.09);
      if (core && pop > 0) {
        const L = 16 * ease.outBack(Math.min(1, t / 0.02 + 0.3)) * pop;
        for (const [dx, dy, l] of [[1, 0, L], [-1, 0, L * 0.4], [0, -1, L * 0.5], [0, 1, L * 0.45]])
          for (let d = 0; d <= l; d += 0.5) {
            const c = d < l * 0.3 ? C[6] : d < l * 0.65 ? C[5] : C[3];
            p.px(dx * d, dy * d, c);
            if (d < l * 0.35) (p.px(dx * d - dy, dy * d + dx, C[5]), p.px(dx * d + dy, dy * d - dx, C[5]));
          }
        p.disc(0, 0, 4 * pop + 1.5, C[6], 1);
      }
      const r = 4 + 14 * ease.outQuart(clamp(t / 0.16)), ak = 1 - clamp((t - 0.05) / 0.18);
      if (core && ak > 0) for (const [a0, a1, k] of arcs) p.arc(0, 0, r * k, 1.4, a0, a1, C[ak > 0.5 ? 5 : 3], ak);
      if (deco) {
        p.glow(0, 0, 18, C[4], 0.6 * pop);
        ps.draw(p);
        lights.draw(p);
      }
    },
  };
}
