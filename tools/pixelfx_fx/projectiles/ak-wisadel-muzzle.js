// 维什戴尔炮口（docs/229 §9 D 组）：@2x 密度（1 像素 = 1 世界像素），原点 = 炮口，正右为开炮方向。
// 替换通用 fx_muzzle_flash 染暗紫那一团。按 docs/220 收特效口径：只有一帧小的暖白芯（偏橙，不进敌方品红区），
// 随后几片短焰舌冷却成暗红，一团暗烟往前散；不比原来亮、不比原来大。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Wisadel muzzle",
  desc: "A launcher muzzle: one small warm-white core frame, short ragged tongues that cool to dark crimson, and a puff of dark ash that rolls forward.",
  tags: ["projectile", "muzzle", "smoke", "gun", "one-shot"],
  size: [44, 36],
  origin: [22, 18],
  duration: 0.16,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#140a08", "#3a1410", "#6e1e16", OP.wisadel[2], "#ff6a3a", "#ffd2a8", "#fff6ec"], seed: 6 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[2]] });
  const tongues = [0, -0.4, 0.36, 0.75].map((a, i) => ({ a: a + Rg.range(-0.1, 0.1), L: i ? Rg.range(5, 9) : Rg.range(11, 14) }));
  for (let i = 0; i < 3; i++) ps.spawn(P.SPARK, 3, 0, Rg.range(110, 170), Rg.range(-40, 40), Rg.range(0.05, 0.1));
  for (let i = 0; i < 3; i++) ps.spawn(P.VAPOUR, Rg.range(4, 9), Rg.range(-2, 2), Rg.range(30, 70), Rg.range(-14, 10), Rg.range(0.1, 0.14), C[1 + (i % 2)], Rg.range(3, 4.5));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      ps.draw(p);
      const k = 1 - clamp(t / 0.08), grow = ease.outExpo(clamp(t / 0.03));
      if (k > 0)
        for (const g of tongues) {
          const L = g.L * (0.8 + 0.2 * grow), ca = Math.cos(g.a), sa = Math.sin(g.a), main = g === tongues[0];
          for (let d = 0; d <= L; d += 0.5) {
            const u = d / L, w = (1 - u) * (main ? 3 : 1.6) * k;
            for (let s = -w; s <= w; s += 0.5) {
              const q = Math.abs(s) / Math.max(w, 0.5), ci = clamp(Math.round(6 - u * 3.5 - q * 2.5 - (1 - k) * 3.5), 1, 6);
              p.px(d * ca - s * sa, d * sa + s * ca, C[ci]);
            }
          }
        }
      if (t < 0.035) p.circle(1, 0, 1.6, C[6]);
      p.glow(3, 0, 8, C[4], 0.25 * k);
    },
  };
}
