// 铃兰狐火弹（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 火头，正右为飞行方向，循环（追踪弹由游戏按速度转向）。
// 原作 lisa_attack_01_trail：亮芯火团 + 一条长拖尾 + 沿途星点。本作暖橙（避开敌弹青 #33ceff），火头是噪声边的泪滴，不画正圆。
// 精英档（组长 B 11-04 分档硬标准）：E0 一条火舌尾；E1 主形 ×1.25、加厚一档、白芯更大，尾巴分出一缕狐尾；
// E2 质变：火头 ×1.5，尾巴变成扇开的三条狐尾（一团 → 三尾），尾梢带 E2 专属的淡紫灵光（不撞敌弹青 / 结晶金 / 危险红）。
import { fit, mix, clamp, hex, WHITE, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameBlade, ember, looped, LAYERS, BACK_LAYERS } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定，样板 843736ef8）

export const meta = {
  name: "Suzuran foxfire unleashed",
  desc: "A homing foxfire: a white-hot teardrop head with a torn warm-orange tongue streaming back, splitting into fox-tail wisps at higher elite.",
  tags: ["fire", "projectile", "foxfire", "loop"],
  size: [72, 32],
  origin: [54, 16],
  duration: 0.4,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, big: 0, seed: 3 },
};

const D = meta.duration, NL = noiseFor(D);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = o.seed, el = +o.elite, ph = t / D;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const R = [3.4, 4.3, 5.1][el], L = [24, 30, 36][el];
  const ACC = ["#f1e6ff", "#cdb4ff", "#9a78e0"].map(hex);   // E2 专属点缀：淡紫灵光（亮 → 暗）
  if (core) {
    // 尾：主火舌一条；E1 加一缕细的狐尾（从主尾上方分出、短一些、末端上卷）；E2 上下各一缕，更长
    if (el < 2) flameBlade(p, -1, 0, -1, 0, L * (0.9 + 0.1 * N(5, S + 10)), R * 0.78, N(2.5, S + 3) * 2, N, S * 7, H, LAYERS, 0.3, 1.2);
    // E1：一缕狐尾；E2：三条狐尾扇开（中间一条最长），各自摆动
    const wisps = el === 0 ? [] : el === 1 ? [[-1, 0.62, 0.3, 0.36]] : [[-1, 0.85, 0.34, 0.5], [0, 1.0, 0, 0.62], [1, 0.8, 0.3, 0.5]];
    wisps.forEach(([side, k, sp, wk], i) => {
      const a = side * sp, len = L * k * (0.9 + 0.1 * N(4, S + 20 + i));
      const x0 = el === 2 ? -R * 1.2 : -R * 2.2, bd = side * (2.5 + el) + N(3, S + 30 + i) * 1.5, LY = el === 2 && side === 0 ? LAYERS : BACK_LAYERS;
      flameBlade(p, x0, side * 1.6, -Math.cos(a), Math.sin(a), len, R * wk, bd, N, S * 11 + i, H, LY, 0.25, 1.4);
      if (el === 2) tipGlow(p, x0, side * 1.6, -Math.cos(a), Math.sin(a), len, R * wk, bd, N, S * 11 + i, LY, 0.25, 1.4, ACC);
    });
    // 火头：泪滴（前圆后尖），边缘噪声抖，白芯偏前
    p.shade(-R * 2.6, -R * 1.6, R * 1.4, R * 1.6, (x, y) => {
      const d = Math.hypot(x * (x > 0 ? 1 : 0.55), y), a = Math.atan2(y, x) / TAU;
      const rim = R + 0.6 * pnoise(a * 7 + ph * 7, 7, S + 1);
      if (d > rim) return;
      const h = 1 - d / rim + 0.15 * pnoise(a * 4 - ph * 8 + d * 0.5, 4, S + 2) + (x > 0 ? 0.1 : 0);
      const w = [0.62, 0.52, 0.48][el];   // E1 / E2 白芯更大（质感强一档）
      return h > w ? H[0] : h > w - 0.17 ? H[1] : h > 0.28 ? H[3] : H[4];
    });
  }
  if (deco) {
    p.glow(0, 0, 8 + el, F[6], 0.32);
    p.glow(-L * 0.45, 0, 10, F[5], 0.14);
    // 沿途甩下的火星：往后、略往上飘，随机步长（循环无缝）
    looped(t, D, [2, 3, 4][el], S + 200, (r) => ({ x: -r.range(3, L * 0.8), y: r.range(-2.5, 2.5), vx: -r.range(20, 45), vy: -r.range(4, 18), life: r.range(0.18, 0.36), s: 1, ph: r.range(0, TAU) }), (q, age) => {
      const k = 1 - age / q.life;
      ember(p, q.x + q.vx * age, q.y + q.vy * age, k, q.s, [H[0], H[2], H[4], H[6]], q.ph + age * 30);
    });
  }
}

// E2 尾梢灵光：按 flameBlade 同一几何把尾巴最后一截（u ≥ u0）重涂成淡紫（外层暗、里层亮），点缀长在主形上、不脱开
function tipGlow(p, x, y, ux, uy, len, w, bend, N, n, layers, jit, wob, ACC, u0 = 0.68) {
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
