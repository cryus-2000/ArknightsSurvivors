// 拉普兰德剑气弹体（docs/229 §7，替 proj_lappland_sword）：@2x，朝右飞。游戏的用法（seg_skadi shape.wave proj_hold 1）：
// 第 0 帧出鞘、飞行中停在第 1 帧，走满后从第 2 帧播完消散。所以 4 帧各司其职：成形 → 满刃 → 断开 → 碎片。
// 两道一长一短的细新月叠在一起（双剑），刃口冷白、刃背钢灰，背后拖几根不等长的灰线。
import { fit, clamp, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lappland sword wave",
  desc: "Flying twin-sword qi: two thin crescents of unequal length, cold white edge and steel-grey back, uneven grey trails; frames form, hold, break, scatter.",
  tags: ["projectile", "slash", "sword", "one-shot"],
  size: [112, 48],
  origin: [68, 24],
  duration: 0.25,
  loop: false,
  fps: 16,
  bg: "dark",
  options: {
    palette: OP.lappland,
    seed: 3,
  },
};

const TRAILS = [[-12, 16, 0.6], [-6, 34, 0.9], [-4, 24, 0.7], [1, 46, 1], [7, 30, 0.85], [9, 14, 0.6]];   // [行, 长, 亮]，行距与长短都不等

function crescent(p, C, cx, H, front, thick, sd, life, brk) {
  for (let y = -H - 0.5; y <= H + 0.5; y++) {
    const v = y / H;
    if (Math.abs(v) > 1) continue;
    const fx = cx + front * (1 - v * v * 1.15) + 0.8 * noise(y * 0.7, sd), th = thick * Math.pow(1 - v * v, 0.9) + 0.6;
    for (let x = fx - th - 0.5; x <= fx + 0.5; x++) {
      const q = (fx - x) / th;
      if (q < 0 || q > 1) continue;
      if (brk > 0 && 0.5 + 0.5 * noise(y * 0.45 + x * 0.3, sd + 5) < brk) continue;   // 断开：沿刃噪声挖口
      const ci = clamp(Math.round(6 - q * 4 - Math.abs(v) * 2 - (1 - life) * 3), 1, 6);
      if (q < 0.55) p.px(x, y, C[ci]);
      else p.blend(x, y, C[ci], (1.3 - q) * life);
    }
  }
}

export function draw(p, t, o) {
  if (t >= meta.duration - 1e-6) return;
  const C = fit(o.palette, 7), f = Math.min(3, Math.floor(t * meta.fps + 1e-6));
  const life = [1, 1, 0.75, 0.4][f], grow = [0.65, 1, 1.05, 1.1][f], brk = [0, 0, 0.35, 0.7][f];
  if (f <= 2)
    for (const [y, L, b] of TRAILS) {
      const len = L * grow * (f === 2 ? 0.6 : 1);
      for (let d = 0; d < len; d++) {
        const u = d / len;
        if (f === 2 && noise(d * 0.5 + y, o.seed + 9) > 0.2) continue;
        p.blend(-4 - d, y, C[clamp(Math.round(4 - u * 3), 1, 4)], 0.55 * b * (1 - u) * life);
      }
    }
  crescent(p, C, -6, 19 * grow, 14, 5.5, o.seed, life, brk);
  crescent(p, C, -13, 13 * grow, 10, 3.5, o.seed + 21, life * 0.9, brk);
  if (f >= 2)   // 碎片：沿刃散开的冷白小块
    for (let i = 0; i < 9; i++) {
      const y = noise(i * 1.7, o.seed + 30) * 18, x = 4 + noise(i * 2.3, o.seed + 31) * 8 + (f - 1) * (3 + i % 3);
      p.blend(x, y, C[5 + (i % 2)], f === 2 ? 0.9 : 0.55);
    }
  if (f === 0) p.glow(4, 0, 14, C[5], 0.25);
}
