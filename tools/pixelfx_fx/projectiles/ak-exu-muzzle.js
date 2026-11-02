// 能天使技能枪口焰（docs/228 §7 试点）：@2x 密度（1 像素 = 1 世界像素），原点 = 枪口，正右为射击方向。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Exusiai muzzle",
  desc: "A tiny rifle muzzle flash: a white-cored spiky cone snaps out in one frame with two side prongs, a few sparks lead it and a wisp of gas trails off.",
  tags: ["projectile", "muzzle", "flash", "gun", "one-shot"],
  size: [40, 32],
  origin: [6, 16],
  duration: 0.2,
  loop: false,
  fps: 30,
  bg: "dark",
  options: { palette: ["#0a2240", "#12528a", "#48ccff", "#b8f2ff", "#f0fdff", "#ffffff"], seed: 2 },
};

export function create(o) {
  const C = fit(o.palette, 6), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  // 每片焰舌长短、角度都不一样
  const tongues = [0, -0.32, 0.3, -0.62, 0.66].map((a, i) => ({ a: a + Rg.range(-0.08, 0.08), L: (i ? Rg.range(7, 13) : Rg.range(20, 25)) * (i > 2 ? 0.7 : 1) }));
  for (let i = 0; i < 5; i++) {
    const a = Rg.range(-0.35, 0.35), sp = Rg.range(220, 420);
    ps.spawn(P.SPARK, 3, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.05, 0.12));
  }
  ps.spawn(P.VAPOUR, 6, 0, 60, Rg.range(-10, 10), 0.13, C[3], 2.5);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const k = 1 - clamp(t / 0.1), grow = ease.outExpo(clamp(t / 0.03));
      if (k > 0)
        for (const g of tongues) {
          const L = g.L * (0.55 + 0.45 * grow) * (0.6 + 0.4 * k), ca = Math.cos(g.a), sa = Math.sin(g.a);
          for (let d = 0; d <= L; d += 0.5) {
            const u = d / L, w = (1 - u) * (g.a === tongues[0].a ? 3.2 : 1.6) * k;
            for (let s = -w; s <= w; s += 0.5) {
              const q = Math.abs(s) / Math.max(w, 0.5), ci = clamp(Math.round(5 - u * 3.6 - q * 2.8 - (1 - k) * 2), 1, 5);
              p.dot(d * ca - s * sa, d * sa + s * ca, C[ci], u > 0.8 ? 1.4 - u : 1);
            }
          }
        }
      if (t < 0.05) p.circle(1, 0, 2 * (1 - t / 0.05) + 0.8, C[5]);
      p.glow(4, 0, 12, C[2], 0.45 * k);
      ps.draw(p);
    },
  };
}
