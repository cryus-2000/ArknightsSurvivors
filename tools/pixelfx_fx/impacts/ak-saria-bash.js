// 塞雷娅普攻盾击（docs/229 §3 普攻档，D 组）：@2x 密度，原点 = 帧中心，正右为出拳方向。替换 Codex fx_saria_shield_bash。
// 盾面往前一顶：一道短而厚的琥珀冲击弧（不对称、外缘噪声起伏），首帧白，前方两三道长短不一的气浪线，碎晶屑往前蹦；不画同心圈。
import { Particles, P, Rng, fit, clamp, ease, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria shield bash",
  desc: "A shield bash: a short thick amber shock arc pushes forward with a ragged rim, a white first frame, a few uneven pressure lines ahead and crystal grit kicked forward.",
  tags: ["impact", "melee", "shield", "one-shot"],
  size: [80, 64],
  origin: [40, 32],
  duration: 0.2,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#06142a", ...OP.saria], seed: 5 },
};

export function create(o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed);
  const ps = new Particles({ rng: R, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[3]] });
  for (let i = 0; i < 6; i++) { const a = R.range(-0.7, 0.7); ps.spawn(P.SPARK, 10, 0, Math.cos(a) * R.range(80, 170), Math.sin(a) * R.range(60, 130), R.range(0.05, 0.1)); }
  const lines = [0, 1, 2].map(() => ({ y: R.range(-14, 14), L: R.range(8, 16), d: R.range(0, 0.03) }));
  let t = 0.015;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const k = 1 - clamp(t / 0.16), x0 = -6 + 22 * ease.outQuart(clamp(t / 0.1));
      if (k > 0)
        for (let y = -22; y <= 22; y++) {
          const v = y / 22, rim = x0 + 8 * (1 - v * v) + 1.5 * noise(y * 0.35, o.seed), w = (5 + 4 * (1 - Math.abs(v))) * k;
          for (let x = rim - w; x <= rim; x++) {
            const q = (rim - x) / Math.max(w, 1), ci = t < 0.04 ? (q < 0.5 ? 7 : 6) : clamp(Math.round(7 - q * 3 - (1 - k) * 4), 1, 7);
            if (q < 0.85 || noise(x * 0.5, y * 0.5) > 0) p.px(x, y, C[ci]);
          }
        }
      for (const l of lines) {
        const u = clamp((t - l.d) / 0.12);
        if (u <= 0 || u >= 1) continue;
        const x = x0 + 10 + u * 14;
        p.line(x, l.y, x + l.L * (1 - u), l.y, C[u < 0.5 ? 5 : 3]);
      }
      p.glow(x0 + 6, 0, 16, C[5], 0.3 * k);
      ps.draw(p);
    },
  };
}
