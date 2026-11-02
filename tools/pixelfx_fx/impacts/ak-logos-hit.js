// 逻各斯普攻墨迹命中（docs/229 §3 普攻档）：@2x，1 贴图像素 = 1 世界像素，原点 = 命中点。
// 一点白紫光芯爆开，墨团按噪声溅成不规整的一摊，亮边很快冷成深墨；几滴墨珠甩出去拖出细尾，最后按噪声溶解。
import { Particles, P, Rng, fit, clamp, ease, noise, noise2 } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos hit",
  desc: "An ink bolt hits: a pale violet core pops, ink splatters into a ragged blot whose bright rim cools to deep ink, drops fling off and it dissolves.",
  tags: ["impact", "hit", "ink", "arcane", "one-shot"],
  size: [44, 44],
  origin: [22, 22],
  duration: 0.2,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.logos, seed: 2 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[4], C[2], C[1]] });
  for (let i = 0; i < 6; i++) {
    const a = Rg.range(-Math.PI, Math.PI), sp = Rg.range(70, 170);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp * 0.8, Rg.range(0.08, 0.16));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const g = ease.outQuart(clamp(t / 0.05)), r0 = 5 + 8 * g, fade = 1 - clamp((t - 0.08) / 0.11);
      if (fade > 0)
        p.shade(-r0 - 5, -r0 - 5, r0 + 5, r0 + 5, (x, y) => {
          const a = Math.atan2(y, x), d = Math.hypot(x, y);
          // 墨团：外缘起伏大，带几根短的墨刺（噪声尖峰，不等距）
          const R = r0 * (0.8 + 0.3 * noise(a * 2.7, S) + 0.35 * Math.max(0, noise(a * 7.9, S + 5)) ** 2);
          if (d > R) return;
          const u = d / R;
          if (noise2(x * 0.5, y * 0.5, S + 9) * 0.5 + 0.5 > fade + 0.2) return;
          // 亮边：外缘一圈紫亮先冷，里面是深墨（芯在首帧是白）
          const ci = t < 0.04 ? clamp(Math.round(6.5 - u * 2), 4, 6) : u > 0.7 ? clamp(Math.round(5 - t / 0.05), 2, 5) : clamp(Math.round(2.5 - t / 0.05 * 0.5), 0, 2);
          p.blend(x, y, C[ci], u > 0.7 ? 1 : 0.85);
        });
      p.glow(0, 0, 9, C[4], 0.25 * (1 - clamp(t / 0.1)));
      ps.draw(p);
    },
  };
}
