// 敌弹 / 投石命中（怪物风格试点 11-04）：原点 = 落点（地面）。
// mode 0 = 碎石：6–10 块棱角碎块（2–4 px）蹦起、落地弹一下、躺平变暗；贴地一摊压扁的不规则尘（边缘不是正圆）。
// mode 1 = 神经液：一簇液滴溅开后下坠拉成短竖条、落地留一小摊暗色残液。液滴用比敌弹青暗两阶的色，不用 #33ceff 本色（活弹才用）。
// 元素 2 种（碎块 / 液滴、地面尘 / 残液），不画环、不放光。
import { Rng, fit, clamp, smooth, noise, noise2 } from "../../core/index.js";

export const meta = {
  name: "Monster projectile impact",
  desc: "Angular rock chunks hop and settle over a flattened ragged dust patch, or nerve fluid splashes, drips and leaves a dark stain.",
  tags: ["monster", "impact", "debris", "one-shot"],
  size: [72, 48],
  origin: [36, 34],
  duration: 0.7,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#1d2027", "#383d48", "#626a79", "#959dab", "#cdd2da"],
    mode: 0,
    seed: 5,
  },
};

export function create(o) {
  const C = fit(o.palette, 5), Rg = new Rng(o.seed), rock = +o.mode === 0, G = 320, SY = 0.32;
  const bits = [];
  for (let i = 0, n = rock ? Rg.int(6, 10) : Rg.int(8, 12); i < n; i++) {
    const a = Rg.range(-Math.PI * 0.95, -Math.PI * 0.05), sp = Rg.range(40, rock ? 95 : 110);
    bits.push({ vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, s: rock ? Rg.int(2, 4) : 1, c: Rg.int(2, 4), sh: Rg.int(0, 2), t0: Rg.range(0, 0.03) });
  }
  let t = 0;
  function pos(b, u) {   // 抛物线 + 落地弹一下（只弹一次，衰减 0.3）
    const vy = b.vy, tl = -2 * vy / G;
    if (u < tl) return [b.vx * u, vy * u + 0.5 * G * u * u, false];
    const x1 = b.vx * tl, u2 = u - tl, vy2 = -vy * 0.3, tl2 = -2 * vy2 / G;
    if (u2 < tl2) return [x1 + b.vx * 0.5 * u2, vy2 * u2 + 0.5 * G * u2 * u2, false];
    return [x1 + b.vx * 0.5 * tl2, 0, true];
  }
  return {
    update(dt) { t += dt; },
    drawBack(p) {   // 地面：压扁的不规则尘 / 残液
      const k = smooth(0, 0.06, t) * (1 - smooth(0.35, 0.7, t));
      if (k <= 0) return;
      const RX = rock ? 14 : 9;
      p.shade(-RX * 1.6, -RX, RX * 1.6, RX, (x, y, out) => {
        const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY), Rr = RX * (1 + 0.35 * noise(a * 2.3, o.seed) + 0.15 * noise(a * 7, o.seed + 3));
        if (r >= Rr) return;
        if (noise2(x * 0.9, y * 0.9, o.seed) * 0.5 + 0.5 > k * (1.1 - r / Rr * 0.6)) return;   // 实色像素、靠噪声镂空淡出（不用半透明抖网格）
        out.c = r < Rr * 0.5 ? C[rock ? 2 : 1] : C[rock ? 1 : 0];
      });
    },
    draw(p) {
      for (const b of bits) {
        const u = t - b.t0;
        if (u < 0) continue;
        const [x, y, rest] = pos(b, u), dark = rest ? smooth(0.2, 0.6, t) : 0;
        if (dark >= 1) continue;
        const col = C[clamp(b.c - Math.round(dark * 2) - (rest ? 1 : 0), 0, 4)];
        if (rock) {   // 棱角块：缺一个角
          for (let dx = 0; dx < b.s; dx++) for (let dy = 0; dy < b.s; dy++) if (!(dx === b.s - 1 && dy === 0 && b.sh)) p.px(x + dx, y - dy, col);
        } else {      // 液滴：下坠时拉成竖条
          const len = rest ? 1 : clamp(Math.round(Math.abs(b.vy + G * u) / 60), 1, 3);
          for (let dy = 0; dy < len; dy++) p.px(x, y - dy, col);
        }
      }
    },
  };
}
