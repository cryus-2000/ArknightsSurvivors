// 安洁莉娜「失重井」共用画法（ak-angelina-well-open / -well / -well-front / -well-close 共用；下划线开头 = 不是独立特效）。
// 全部 @2x（1 贴图像素 = 1 世界像素），地面件按透视 sy 0.5（同旧件与 ak-angelina-pull），井半径 R = 58（游戏 well_r 60，JSON fit 30）。
// 地面：几条长短、粗细、起点都不一样的螺旋臂绕中心慢慢卷（不等距），中心一团暗紫，外沿一圈不规整的淡边——只有一圈，不画同心圈。
import { clamp, noise, fit, TAU } from "../../core/index.js";

export const R = 58, SY = 0.5;

// 螺旋臂：起角、长度（弧度）、粗细、亮度、半径范围都写死成不规则的一组（不等距）
const ARMS = [
  { a: 0.0, len: 2.4, w: 1.6, b: 1.0, r0: 0.18, r1: 1.0 },
  { a: 1.7, len: 1.6, w: 1.1, b: 0.7, r0: 0.25, r1: 0.85 },
  { a: 2.9, len: 2.1, w: 1.4, b: 0.9, r0: 0.15, r1: 0.95 },
  { a: 4.6, len: 1.3, w: 1.0, b: 0.6, r0: 0.3, r1: 0.8 },
  { a: 5.4, len: 1.8, w: 1.2, b: 0.8, r0: 0.2, r1: 0.9 },
];

// rot = 整体转角；k = 浓度；hot = 首帧亮度（0–1）；reach = 半径倍数
export function vortex(p, palette, seed, { rot = 0, k = 1, hot = 0, reach = 1, rim = 1 }) {
  const C = fit(palette, 7), Rr = R * reach;
  if (k <= 0 || Rr < 2) return;
  // 外沿一圈淡边（噪声起伏）
  if (rim > 0)
    for (let a = 0; a < TAU; a += 0.7 / Rr) {
      const r = Rr * (1 + 0.06 * noise(a * 3.7 + rot * 0.5, seed) + 0.03 * noise(a * 9.1, seed + 2));
      p.blend(Math.cos(a) * r, Math.sin(a) * r * SY, C[clamp(Math.round(3 + hot * 3), 2, 6)], 0.55 * k * rim);
    }
  // 中心暗团
  p.shade(-Rr * 0.4, -Rr * 0.2, Rr * 0.4, Rr * 0.2, (x, y) => {
    const d = Math.hypot(x, y / SY) / (Rr * 0.32 * (1 + 0.2 * noise(Math.atan2(y / SY, x) * 2.3 + rot, seed + 5)));
    if (d > 1) return;
    p.blend(x, y, C[d < 0.5 ? 0 : 1], (0.6 - 0.3 * d) * k);
  });
  // 螺旋臂：越往里越亮（被吸进去）
  for (const m of ARMS) {
    for (let s = 0; s <= 1; s += 0.6 / (Rr * m.len)) {
      const r = Rr * (m.r1 - (m.r1 - m.r0) * s), a = m.a + rot + m.len * s;
      const w = m.w * (0.5 + 0.5 * Math.sin(Math.PI * s));
      const ci = clamp(Math.round(1.5 + 3 * s * m.b + hot * 2), 1, 6);
      for (let q = -w; q <= w; q += 0.8)
        p.blend(Math.cos(a) * (r + q), Math.sin(a) * (r + q) * SY, C[ci], (0.5 + 0.4 * s) * k * m.b);
    }
  }
}
