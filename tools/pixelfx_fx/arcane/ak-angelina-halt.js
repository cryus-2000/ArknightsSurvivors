// 安洁莉娜普攻「定身」落点（docs/229 §3 普攻档，地面层）：@2x，原点 = 敌人脚下，透视 sy 0.5。
// 首帧一小圈不规整的紫亮边，随即两三段长短不一的弧往里合拢、冷却，按噪声溶解；只一圈。
import { Rng, fit, clamp, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina halt",
  desc: "Angelina's halt mark under an enemy: a ragged violet ring flares, breaks into uneven arcs that close in and cool away.",
  tags: ["arcane", "gravity", "stun", "floor", "one-shot"],
  size: [48, 28],
  origin: [24, 14],
  duration: 0.2,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.angelina, seed: 4 },
};

const SY = 0.5;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), S = o.seed;
  const arcs = [];
  for (let a = Rg.range(0, 0.6); a < TAU - 0.5; a += Rg.range(1.4, 2.4)) arcs.push([a, a + Rg.range(0.8, 1.5)]);
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const u = clamp(t / 0.17), r = 15 * (1 - 0.45 * ease.inQuad(u));
      if (u >= 1) return;
      for (const [a0, a1] of arcs)
        for (let a = a0; a < a1; a += 0.9 / r) {
          const rr = r * (1 + 0.08 * noise(a * 3.1, S)), v = (a - a0) / (a1 - a0);
          if (u > 0.5 && noise(a * 7 + t * 40, S + 3) > 1.6 - 1.6 * u) continue;   // 按噪声断开溶解
          p.px(Math.cos(a) * rr, Math.sin(a) * rr * SY, C[clamp(Math.round((t < 0.04 ? 4.4 : 3.8 - u * 2.5) - v), 1, 4)]);
        }
      if (t < 0.04) p.px(0, 0, C[6]);
    },
  };
}
