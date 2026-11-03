// 铃兰放开版共用：精英分档（组长 B 11-04 硬标准）、E2 专属点缀、狐火团。
// 体量 E0 0.8 / E1 1.0 / E2 1.2（E1 ≈ E0 × 1.25，E2 ≈ E0 × 1.5）；E2 另有主形质变 + 淡紫灵光（只长在火梢上，不另撒点）。
// 用户 11-04：长条 + 弯曲 + 末端收尖读成触手。狐火一律做成短而圆胖的火团：外焰往上跳、分 2–3 个尖、内芯亮，
// 外形每 2–3 帧变一次（闪动）；拖尾短、往上飘散；尾巴意象 = 几团火扇形排开，不画弯曲长条。
import { hex } from "../../core/index.js";
import { pnoise } from "./_lib.js";

export const SCALE = [0.8, 1, 1.2];
export const ACC = ["#f1e6ff", "#cdb4ff", "#9a78e0"].map(hex);   // 淡紫灵光（亮 → 暗）：不撞敌弹青 / 结晶金 / 危险红

const h01 = (n) => { const s = Math.sin(n * 12.9898 + 78.233) * 43758.5453; return s - Math.floor(s); };

/**
 * 一团狐火：圆胖的火身 + 往上跳的 2–3 个火尖，内芯偏下、最亮，外沿暗一档。(x, y) = 火身中心，r = 火身半径（1x 像素）。
 * o: { H 热在前的色阶, t 秒, fps, seed, tips 2|3, up 火尖高（× r，缺省 1）, lean 火尖往旁边偏（× r，正 = 右）,
 *      heat 1 新 → 0 冷（冷了整体降档、火尖变矮）, acc E2 火梢淡紫, flick 几帧换一次外形（缺省 2.5）, sq 火身压扁（缺省 1） }
 */
export function foxClump(p, x, y, r, o) {
  if (r < 0.8) return;
  const H = o.H, S = (o.seed | 0) + 1, heat = o.heat ?? 1, nt = o.tips ?? 3, lean = o.lean ?? 0, sq = o.sq ?? 1;
  const q = Math.floor((o.t ?? 0) * (o.fps ?? 15) / (o.flick ?? 2.5));   // 外形每 2–3 帧跳一次
  const up = (o.up ?? 1) * (0.55 + 0.45 * heat);
  const xs = nt === 2 ? [-0.36, 0.38] : nt === 1 ? [0] : [-0.52, 0.04, 0.55];
  const mid = nt === 3 ? 1 : 0;
  const tips = xs.map((bx, i) => ({
    x: (bx + (h01(S * 7 + q * 13 + i) - 0.5) * 0.22) * r,
    h: r * up * (i === mid ? 1.35 : 0.9) * (0.7 + 0.6 * h01(S * 11 + q * 17 + i * 3)),
    w: r * (nt === 1 ? 0.62 : 0.44) * (0.85 + 0.3 * h01(S * 5 + q * 7 + i * 5)),
  }));
  const top = Math.max(...tips.map((k) => k.h)) + r * 1.1, lx = Math.abs(lean) * r;
  const n0 = S * 3 + q;
  p.shade(x - r * 1.3 - lx, y - top - 1, x + r * 1.3 + lx, y + r * sq + 1, (px, py) => {
    const dx = px - x, dy = py - y, a = Math.atan2(dy, dx) / (2 * Math.PI);
    const bd = Math.hypot(dx / r, dy / (r * (dy > 0 ? 0.88 * sq : 1)));
    const bodyV = 1 - bd + 0.16 * pnoise(a * 6, 6, n0);
    let tipV = -1, tf = 0;
    if (dy < r * 0.1) for (const k of tips) {
      const f = (-dy + r * 0.1) / (k.h + r * 1.1);   // 火尖从火身中部起、高出火身顶 h
      if (f >= 1) continue;
      const cx = k.x + lean * r * f * f, half = k.w * Math.pow(1 - f, 0.8) + 0.4 * pnoise(f * 4 + k.x, 4, n0 + 9);
      if (half <= 0.3) continue;
      const v = (1 - Math.abs(dx - cx) / half) * (1 - f * 0.6);
      if (v > tipV) tipV = v, tf = f;
    }
    const v = Math.max(bodyV, tipV * 0.85);
    if (v <= 0) return;
    const inTip = tipV * 0.85 > bodyV;
    if (o.acc && inTip && tf > 0.6) return ACC[v > 0.32 ? 0 : v > 0.14 ? 1 : 2];   // E2 火梢淡紫
    const cd = Math.hypot(dx / (r * 0.55), (dy - r * 0.18) / (r * 0.62));   // 内芯偏下
    let i = cd < 0.55 ? 0 : cd < 0.95 ? 1 : v > 0.32 ? 2 : v > 0.14 ? 3 : 4;
    if (inTip && tf > 0.55) i = Math.max(i, v > 0.25 ? 3 : 4);
    i = Math.min(H.length - 1, i + Math.round((1 - heat) * 3.2));
    return H[i];
  });
}

/**
 * 短拖尾：火团身后往上飘散的几小团（越远越小越冷、越往上），不连成长条。
 * (x, y) = 火头中心，(bx, by) = 往后的方向（单位向量），n 团数，r 火头半径；o 同 foxClump（每团种子错开）。
 */
export function puffTrail(p, x, y, bx, by, n, r, o) {
  for (let i = n; i >= 1; i--) {
    const k = i / (n + 1), d = r * (1.15 + 1.05 * i), rr = r * (0.78 - 0.5 * k);
    foxClump(p, x + bx * d, y + by * d - r * 0.55 * i, rr, { ...o, seed: (o.seed | 0) + i * 7, tips: 2, heat: (o.heat ?? 1) * (1 - 0.5 * k), up: 0.8, acc: false });
  }
}
