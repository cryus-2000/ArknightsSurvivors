// 能天使普攻枪口焰（docs/231 普攻试点）：@2x 密度，画布 32×32 与旧枪口相同（游戏按帧中心放、保留原画布），正右为射击方向。
// 普攻射速高（0.35 秒一轮、可多发）：主体 0.1 秒（一帧爆开、两帧收尾）+ 一缕 alpha ≤ 0.4 的枪烟，总长 ≤ 0.15 秒（docs/229 §2.5）。
// 白只在枪口核心那一点（近白 ≤ 12%）；柔光走 light 层（p.glow），导出成 _glow 条。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";
import { OP, FPS, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Exusiai rapid muzzle",
  desc: "A rapid-fire muzzle flash: an uneven three-tongue flame snaps out with a white core, two sparks lead it and it is gone in three frames.",
  tags: ["projectile", "muzzle", "flash", "gun", "one-shot"],
  size: [32, 32],
  origin: [6, 16],
  duration: 0.15,
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: { palette: OP.exusiai, seed: 3 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  // 一长两短的焰舌，长短、角度都错开
  const tongues = [[0, Rg.range(22, 25), 4.2], [-0.5 + Rg.range(-0.06, 0.06), Rg.range(10, 12), 2], [0.56 + Rg.range(-0.06, 0.06), Rg.range(7, 9), 1.7]];
  for (let i = 0; i < 2; i++) {
    const a = Rg.range(-0.25, 0.25), sp = Rg.range(260, 380);
    ps.spawn(P.SPARK, 3, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.04, 0.07));
  }
  const smoke = [[5, Rg.range(-1.5, 1.5), 1.6], [9, Rg.range(-2, 2), 1.2], [13, Rg.range(-2, 2), 0.9]];
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const k = 1 - clamp(t / 0.085), grow = ease.outExpo(clamp(t / 0.02));
      if (k > 0)
        for (const [a, L0, W0] of tongues) {
          const L = L0 * (0.6 + 0.4 * grow) * (0.55 + 0.45 * k), ca = Math.cos(a), sa = Math.sin(a);
          for (let d = 0; d <= L; d += 0.5) {
            const u = d / L, w = (1 - u) * W0 * (0.5 + 0.5 * k);
            for (let s = -w; s <= w; s += 0.5) {
              const q = Math.abs(s) / Math.max(w, 0.5), ci = clamp(Math.round(5 - u * 3.2 - q * 2.4 - (1 - k) * 2.2), 1, 5);   // 最亮到第 5 阶（粉白），纯白只给核心
              p.dot(d * ca - s * sa, d * sa + s * ca, C[ci]);
            }
          }
        }
      if (t < 0.035) p.circle(1, 0, 1.6 * (1 - t / 0.035) + 0.6, C[6]);
      p.glow(4, 0, 10, C[3], 0.3 * k);
      // 枪烟：两三团淡红往前飘、稀疏，alpha ≤ TAIL_ALPHA
      const sm = clamp((t - 0.03) / 0.12);
      if (sm > 0 && sm < 1)
        for (const [dx, dy, r] of smoke) p.disc(dx + 12 * sm, dy - 3 * sm, r * (0.6 + 0.6 * sm), C[2], TAIL_ALPHA * (1 - sm));
      ps.draw(p);
    },
  };
}
