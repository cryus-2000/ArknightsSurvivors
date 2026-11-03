// 能天使枪口焰（pixelfx 放开版，docs/242）：1x，原点 = 枪口，正右为射击方向。
// 一帧白热的尖锐焰舌（主舌长、侧舌长短不一）+ 两侧小叉 → 火星前冲、一缕烟往前飘；光晕放开。
import { Particles, Lights, P, Rng, fit, clamp, ease } from "../../core/index.js";

export const meta = {
  name: "Exusiai muzzle unleashed",
  desc: "A bright rifle muzzle flash: a white-hot spiky cone with uneven side tongues snaps out, sparks race ahead and a wisp of gas drifts off.",
  tags: ["projectile", "muzzle", "flash", "gun", "one-shot"],
  size: [64, 44],
  origin: [8, 22],
  duration: 0.22,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#3a0a10", "#7c1622", "#c4283a", "#f24d4d", "#ff9a8a", "#ffd8cc", "#ffffff"], layer: "all", seed: 2 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";   // 分层（docs/242 §8）
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  lights.add(6, 0, 26, C[5], 0.9, 0.15);
  const tongues = [0, -0.3, 0.34, -0.66, 0.6, -1.1, 1.05].map((a, i) => ({ a: a + Rg.range(-0.08, 0.08), L: (i === 0 ? Rg.range(30, 36) : i < 3 ? Rg.range(14, 20) : Rg.range(6, 11)), w: i === 0 ? 4.5 : i < 3 ? 2.6 : 1.6 }));
  for (let i = 0; i < 8; i++) {
    const a = Rg.range(-0.35, 0.35), sp = Rg.range(260, 460);
    ps.spawn(P.SPARK, 4, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.05, 0.14));
  }
  ps.spawn(P.VAPOUR, 10, 0, 70, Rg.range(-10, 10), 0.16, C[4], 3.5);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      const k = 1 - clamp(t / 0.11), grow = ease.outExpo(clamp(t / 0.03));
      if (core && k > 0)
        for (const g of tongues) {
          const L = g.L * (0.6 + 0.4 * grow) * (0.55 + 0.45 * k), ca = Math.cos(g.a), sa = Math.sin(g.a);
          for (let d = 0; d <= L; d += 0.5) {
            const u = d / L, w = (1 - u) * g.w * (0.6 + 0.4 * k);
            for (let s = -w; s <= w; s += 0.5) {
              const q = Math.abs(s) / Math.max(w, 0.5), ci = clamp(Math.round(6 - u * 3.6 - q * 2.4 - (1 - k) * 2.4), 1, 6);
              p.px(d * ca - s * sa, d * sa + s * ca, C[ci]);
            }
          }
        }
      if (core && t < 0.05) p.disc(2, 0, 4 * (1 - t / 0.05) + 1.5, C[6], 1);
      if (deco) {
        p.glow(8, 0, 20, C[4], 0.6 * k);
        ps.draw(p);
        lights.draw(p);
      }
    },
  };
}
