// 斯卡蒂精二「涌潮」潮刃弹体（docs/229 §7 第 2 批，替 proj_skadi_surge_blade）：@2x，朝右飞，4 帧循环。
// 一弯不规整的水刃：前缘白、往后逐级变深，刃背拖出断续的水尾，尾上甩落零碎水珠；循环用 loopNoise 无缝。
import { fit, clamp, loopNoise, TAU } from "../../core/index.js";

export const meta = {
  name: "Skadi tide blade",
  desc: "A flying crescent of deep-sea water, white leading edge cooling to abyss blue, with a broken wake and stray droplets; seamless 4-frame loop.",
  tags: ["water", "projectile", "crescent", "loop"],
  size: [96, 48],
  origin: [56, 24],
  duration: 0.2,
  loop: true,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    half: 22,
    seed: 6,
  },
};

const TRAIL = new Set([7, 11, 12, 17, 22, 24, 29, 34, 36]);   // 拖尾所在行（相对上端），间距 1–5 不等

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ph = t / meta.duration, H = o.half, sd = o.seed;
  // 刃：细长新月，两端大幅后掠；前缘 x = f(y)，厚度中间最厚
  const front = (v) => 8 - 22 * v * v + 1.2 * loopNoise(ph, 0.6, sd + Math.round((v + 1) * 4));
  for (let y = -H - 0.5; y <= H + 0.5; y += 1) {
    const v = y / H, row = Math.round(y + H);
    if (Math.abs(v) > 1) continue;
    const fx = front(v), th = (6 + 1.5 * loopNoise(ph, 0.7, sd + 3 + row)) * Math.pow(1 - v * v, 0.8) + 0.6;
    for (let x = fx - th - 0.5; x <= fx + 0.5; x += 1) {
      const q = (fx - x) / th;
      if (q < -0.05 || q > 1) continue;
      const ci = clamp(Math.round(7 - q * 6 - Math.abs(v) * 1.8 - (y > 0 ? 0.5 : 0)), 1, 7);
      if (q < 0.5) p.px(x, y, C[ci]);
      else p.blend(x, y, C[ci], 1.3 - q);
    }
    // 水尾：刃背往后拖的几根断续水线（行距不等、长短和断口随噪声）
    if (TRAIL.has(row)) {
      const len = (8 + 22 * (0.5 + 0.5 * loopNoise(ph, 0.9, sd + 40 + row))) * (1 - v * v);
      const gap = 4 + 6 * (0.5 + 0.5 * loopNoise(ph, 0.5, sd + 70 + row));
      for (let d = 0; d < len; d += 1) {
        const u = d / len;
        if (d > gap && d < gap + 2) continue;
        p.blend(fx - th - d, y, C[clamp(Math.round(5 - u * 4), 1, 5)], 0.6 * (1 - u));
      }
    }
  }
  // 零碎水珠：位置按相位循环
  for (let i = 0; i < 7; i++) {
    const u = (ph + i * 0.37 + 0.13 * i * i) % 1;
    const y = (((i * 0.618 + 0.21) % 1) * 2 - 1) * H * 0.85, x = front(y / H) - 12 - u * 34;
    p.blend(x, y + u * 3 * Math.sign(y), C[5 + (i % 3)], 0.9 * (1 - u));
  }
  p.glow(front(0) - 2, 0, 18, C[5], 0.18);
}
