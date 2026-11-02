// 逻各斯 S3「咒域」扇形的共用画法（ak-logos-fan-open / ak-logos-fan / ak-logos-fan-close 三段共用；下划线开头 = 不是独立特效）。
// 1x 帧条（1 贴图像素 = 2 世界像素），画布 180×272、原点 (4, 136) = 扇心；朝右、半角 50°、半径 170（= 游戏里 FAN_REF_R 340 世界像素）。
// 扇面是一层薄墨：墨云按噪声从扇心往外流（循环无缝），浓处透出紫；两条侧边是细的紫线、随噪声轻微抖；
// 弧边是一道不规整的亮边（噪声起伏），不画内部同心圈、不用点阵 / 棋盘格（旧 Codex 版的底纹是点阵）。
import { clamp, noise, noise2, fit } from "../../core/index.js";

export const R = 170, HALF = (50 * Math.PI) / 180;
export const SIZE = [180, 272], ORIGIN = [4, 136];

// 循环无缝的「往外流」噪声：两份相位差一个周期的样本按 φ 交叉淡化
function flow(r, a, ph, seed) {
  const L = 60;   // 一个循环墨云往外走 60 像素
  const n0 = noise2((r - ph * L) * 0.045, a * 2.6, seed), n1 = noise2((r - (ph - 1) * L) * 0.045, a * 2.6, seed);
  return n0 * (1 - ph) + n1 * ph;
}

// 画扇形：half = 当前半角，reach = 当前半径倍数（0–1），ph = 循环相位（0–1），k = 整体浓度（0–1），dis = 溶解进度（0–1，从弧边往里）
export function fan(p, palette, seed, { half = HALF, reach = 1, ph = 0, k = 1, dis = 0, hot = 0 }) {
  const C = fit(palette, 7), Rr = R * reach;
  if (k <= 0 || half <= 0.01 || Rr < 2) return;
  const H = Math.sin(Math.min(half, 1.5)) * Rr + 4;
  p.shade(0, -H, Rr * 1.1 + 2, H, (x, y) => {
    const a = Math.atan2(y, x), r = Math.hypot(x, y);
    if (Math.abs(a) > half + 0.02) return;
    const rim = Rr * (1 + 0.035 * noise(a * 3.3, seed) + 0.015 * noise(a * 8.1, seed + 4));
    if (r > rim) return;
    const u = r / rim;
    // 溶解：从弧边往里，按噪声
    if (dis > 0 && (noise2(x * 0.06, y * 0.06, seed + 9) * 0.5 + 0.5) * 0.6 + (1 - u) * 0.6 < dis) return;
    const edgeA = (half - Math.abs(a)) * r;   // 离侧边的像素距离
    const side = edgeA < 1.4 + 0.6 * noise(r * 0.08, seed + 2);
    const arc = rim - r < 2.2 + 1.2 * (0.5 + 0.5 * noise(a * 11, seed + 3));
    if (arc) return p.blend(x, y, C[clamp(Math.round(4 + hot * 2 + 0.6 * noise(a * 9 + ph * 6.28, seed + 5)), 3, 6)], 0.95 * k);
    if (side) return p.blend(x, y, C[clamp(Math.round(3 + hot * 2), 2, 6)], 0.8 * k);
    // 扇面薄墨：浓处透紫，淡处几乎透明（真半透明）
    const n = flow(r, a, ph, seed + 7) + 0.4 * noise2(x * 0.11, y * 0.11, seed + 8);
    if (n < -0.15) return;
    const ci = n > 0.45 ? 2 : n > 0.15 ? 1 : 0;
    p.blend(x, y, C[ci], [0.2, 0.32, 0.45][ci] * k);   // 透明度只取三档（连续渐变压不动包体）
  });
  if (hot > 0) p.glow(4, 0, 10, C[5], 0.3 * hot);
}
