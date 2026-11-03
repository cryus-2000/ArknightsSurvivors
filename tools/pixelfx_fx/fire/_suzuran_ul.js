// 铃兰放开版共用：精英分档（组长 B 11-04 硬标准）与 E2 专属点缀。
// 体量 E0 0.8 / E1 1.0 / E2 1.2（E1 ≈ E0 × 1.25，E2 ≈ E0 × 1.5）；E2 另有主形质变 + 淡紫灵光（只长在主形的尾梢 / 火梢上，不另撒点）。
import { hex } from "../../core/index.js";

export const SCALE = [0.8, 1, 1.2];
export const ACC = ["#f1e6ff", "#cdb4ff", "#9a78e0"].map(hex);   // 淡紫灵光（亮 → 暗）：不撞敌弹青 / 结晶金 / 危险红

/** flameTongue 同一几何，把火舌最上面一截（u ≥ u0）重涂成淡紫：外层暗、里层亮。参数与 flameTongue 一致。 */
export function tongueTip(p, x, y, h, w, sx, N, n, layers, jit = 0.5, wob = 1.1, u0 = 0.66) {
  if (h < 1) return;
  layers.slice(0, 3).forEach(([lw, lh], li) => {
    const L = h * lh, c = ACC[2 - li];
    for (let r = Math.ceil(L * u0); r <= L; r++) {
      const u = r / Math.max(1, L);
      const half = w * lw * Math.pow(1 - u, 0.85) * Math.min(1, (r + 1.5) / 3.5) + N(9, n, r * 0.45) * jit;
      if (half < 0.3) continue;
      const cx = x + sx * u * u * lh + N(4, n + 7, r * 0.2) * u * wob, Y = Math.round(y - r);
      for (let px = Math.round(cx - half), x1 = Math.round(cx + half); px <= x1; px++) p.px(px, Y, c);
    }
  });
}

/** flameBlade 同一几何的尾梢淡紫。参数与 flameBlade 一致。 */
export function bladeTip(p, x, y, ux, uy, len, w, bend, N, n, layers, jit = 0.5, wob = 1.1, u0 = 0.68) {
  const nx = -uy, ny = ux;
  layers.slice(0, 3).forEach(([lw, lh], li) => {
    const L = len * lh, c = ACC[2 - li];
    for (let r = L * u0; r <= L; r += 0.5) {
      const u = r / Math.max(1, L);
      const half = w * lw * Math.pow(1 - u, 0.85) * Math.min(1, (r + 1.5) / 3.5) + N(9, n, r * 0.45) * jit;
      if (half < 0.3) continue;
      const off = bend * u * u * lh + N(4, n + 7, r * 0.2) * u * wob, cx = x + ux * r + nx * off, cy = y + uy * r + ny * off;
      for (let q = -half; q <= half; q += 0.5) p.px(cx + nx * q, cy + ny * q, c);
    }
  });
}
