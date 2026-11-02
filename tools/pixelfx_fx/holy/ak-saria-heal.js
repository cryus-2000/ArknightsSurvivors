// 塞雷娅治疗（docs/229 §9 D 组）：原点 = 队长脚底。替换旧 fx_heal_aura_amber（1x 放大 2.8 倍）。
// 脚下一片不规整的琥珀暖光（透视椭圆，边缘按噪声起伏），首帧爆亮后冷却；几粒长短不一的光屑往上飘，间距随机。
import { Particles, Rng, P, fit, clamp, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria heal",
  desc: "A ragged pool of warm amber light swells under the ally's feet, flashes and cools, while uneven motes drift up and fade.",
  tags: ["holy", "heal", "ground", "buff", "one-shot"],
  size: [64, 72],
  origin: [32, 52],
  duration: 0.55,
  loop: false,
  fps: 20,
  bg: "ground",
  options: { palette: ["#06142a", ...OP.saria], radius: 20, seed: 4 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R0 = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  const motes = [];
  for (let i = 0; i < 9; i++) {
    const a = Rg.range(0, TAU), r = R0 * Rg.range(0.2, 0.9);
    motes.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, d: Rg.range(0, 0.2), v: Rg.range(40, 85), L: Rg.int(2, 5), life: Rg.range(0.22, 0.34), c: Rg.int(5, 7) });
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {
      const k = clamp(t / 0.45);
      if (k >= 1) return;
      const rr = R0 * (0.7 + 0.3 * Math.sqrt(k));
      for (let y = Math.floor(-R0 * SY - 3); y <= R0 * SY + 3; y++)
        for (let x = -R0 - 3; x <= R0 + 3; x++) {
          const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY), edge = rr * (0.9 + 0.14 * noise(a * 3 + 1, o.seed)) + 1.2 * noise(a * 13, o.seed + 5);
          if (d > edge) continue;
          const q = d / edge, ci = clamp(Math.round(7 - k * 5 - q * 2 + (t < 0.05 ? 2 : 0)), 3, 7);
          p.blend(x, y, C[ci], (q > 0.82 ? 0.85 : 0.3 * (1 - q * 0.5)) * (1 - k));
        }
    },
    draw(p) {
      for (const m of motes) {
        const u = t - m.d;
        if (u < 0 || u > m.life) continue;
        const f = u / m.life, y = m.y - m.v * u;
        for (let j = 0; j < m.L; j++) p.blend(m.x, y + j, C[Math.max(2, m.c - j - Math.floor(f * 3))], (1 - f) * (1 - j / m.L));
        if (u < 0.06) p.glow(m.x, y, 4, C[5], 0.25);
      }
      if (t < 0.1) p.glow(0, -6, 18, C[6], 0.3 * (1 - t / 0.1));
      ps.draw(p);
    },
  };
}
