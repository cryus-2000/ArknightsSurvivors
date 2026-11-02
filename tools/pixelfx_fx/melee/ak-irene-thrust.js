// 艾丽妮普攻直线刺击（docs/229 §3 普攻档，D 组）：@2x 密度（1 像素 = 1 世界像素），原点 = 帧中心，正右为刺出方向。
// 替换 Codex fx_irene_thrust。细剑一刺：白热的细芯从后往前窜出，两侧是长短不一的玫瑰色风痕，剑尖一点亮，随后从尾往头冷却、碎成光屑。
import { Particles, P, Rng, fit, clamp, ease, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Irene thrust",
  desc: "A rapier thrust: a white-hot hairline core shoots forward, uneven rose wind streaks run beside it, the tip flares, then it cools from the tail and breaks into motes.",
  tags: ["melee", "thrust", "rapier", "one-shot"],
  size: [136, 28],
  origin: [68, 14],
  duration: 0.2,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#06142a", ...OP.irene], len: 128, seed: 3 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), L = o.len, x0 = -L / 2;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[3]] });
  // 风痕：条数、偏移、长短、起点都随机
  const streaks = [];
  for (let i = 0; i < 5; i++) streaks.push({ y: Rg.sign() * Rg.range(2, 6), a: Rg.range(0.1, 0.5), b: Rg.range(0.55, 0.95), d: Rg.range(0, 0.03) });
  let t = 0.03, spawned = false;   // 从刺到一半开始：第 0 帧就有整条白芯
  return {
    update(dt) {
      t += dt;
      if (!spawned && t > 0.04) {
        spawned = true;
        for (let i = 0; i < 5; i++) ps.spawn(P.SPARK, L / 2 - 4, 0, Rg.range(30, 90), Rg.range(-50, 50), Rg.range(0.04, 0.09));
      }
      ps.update(dt);
    },
    draw(p) {
      const head = x0 + L * ease.outExpo(clamp(t / 0.04)), tail = x0 + L * clamp((t - 0.05) / 0.12);
      const k = 1 - clamp(t / 0.16);
      if (head > tail) {
        for (let x = tail; x <= head; x += 0.5) {
          const u = (x - x0) / L, hot = t < 0.045;
          const w = (0.6 + 1.6 * u) * (0.5 + 0.5 * k);   // 往前变粗
          const ci = hot ? 7 : clamp(Math.round(7 - (1 - u) * 3 - (1 - k) * 3), 2, 7);
          p.px(x, 0, C[ci]);
          if (w > 1) { p.px(x, -1, C[Math.max(2, ci - 2)]); p.px(x, 1, C[Math.max(1, ci - 3)]); }
          if (w > 1.8 && u > 0.6) { p.px(x, -2, C[Math.max(1, ci - 4)]); p.px(x, 2, C[Math.max(1, ci - 4)]); }
        }
        for (const s of streaks) {
          const u0 = x0 + L * s.a, u1 = x0 + L * s.b, sk = clamp((t - s.d) / 0.04) * k;
          for (let x = Math.max(u0, tail); x < Math.min(u1, head); x++) if (noise(x * 0.3, s.y * 7 + o.seed) > -0.3) p.blend(x, s.y, C[4 + (Math.abs(s.y) < 4 ? 1 : 0)], 0.75 * sk);
        }
      }
      if (t < 0.08) {
        const g = 1 - t / 0.08;
        p.glow(head, 0, 9, C[5], 0.3 * g);
        p.line(head - 1, -3 * g - 1, head + 1, 3 * g + 1, C[6]);
        p.px(head + 1, 0, C[7]);
      }
      ps.draw(p);
    },
  };
}
