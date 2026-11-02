// B 组弹体共用画法（ak-eyjafjalla-lavaball / ak-eyjafjalla-ignite-proj / ak-lumen-bolt / ak-suzuran-foxfire / ak-suzuran-bigfox 共用；下划线开头 = 不是独立特效）。
// 朝右飞、原点 = 弹心、循环无缝（相位 ph 0–1）。头部一团：芯 1 像素最亮，往外按色阶降；尾巴是几条长短不一、相位不同的火舌 / 光舌往后拖，
// 尾端断成几粒；不画等距重复。白只在芯一点（docs/229 §2.4、docs/231 §2）。
import { clamp, noise, fit, TAU } from "../../core/index.js";

// o: { palette, head: 头半径, len: 尾长, tongues: [[纵向偏移, 长度比, 粗细, 相位]], ears: 是否画两只狐耳尖, crust: 熔岩壳 }
export function flameProj(p, ph, o) {
  const C = fit(o.palette, 7), H = o.head, L = o.len, S = o.seed || 1;
  // 尾舌
  for (const [dy, lk, w0, p0] of o.tongues) {
    const l = L * lk * (0.85 + 0.15 * Math.sin((ph + p0) * TAU));
    for (let s = 0; s <= l; s += 0.5) {
      const v = s / l, x = -H * 0.4 - s, y = dy * (1 + v * 0.8) + Math.sin(v * 5 + (ph + p0) * TAU) * (0.6 + v * 1.4);
      const w = w0 * (1 - v);
      if (v > 0.7 && noise(s * 0.6 + ph * 9, S + p0 * 10) > 0.2) continue;   // 尾端断成几粒
      for (let q = -w; q <= w; q += 1) p.px(x, y + q, C[clamp(Math.round(4 - v * 3), 1, 4)]);
    }
  }
  // 头
  p.shade(-H - 1, -H - 1, H + 1, H + 1, (x, y) => {
    const a = Math.atan2(y, x), d = Math.hypot(x * 0.9, y) / (H * (1 + 0.15 * noise(a * 2.3 + ph * TAU, S)));
    if (d > 1) return;
    if (o.crust && noise(x * 0.5 + Math.cos(ph * TAU) * 2, y * 0.5 + Math.sin(ph * TAU) * 2, S + 3) > 0.35 && d > 0.35) return p.px(x, y, C[1]);   // 熔岩壳暗块，跟着翻
    p.px(x, y, C[clamp(Math.round(5 - d * 2.6), 2, 5)]);
  });
  if (o.ears) for (const s of [-1, 1]) for (let k = 0; k < H * 0.9; k += 0.5) p.px(H * 0.15 + k * 0.35, s * (H * 0.55 + k * 0.6), C[clamp(Math.round(4.5 - k / H * 2), 2, 5)]);
  p.px(Math.round(H * 0.3), 0, C[6]);
  p.glow(0, 0, H * 2, C[4], 0.25);
}
