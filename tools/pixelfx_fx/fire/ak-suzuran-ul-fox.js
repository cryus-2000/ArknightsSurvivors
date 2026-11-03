// 铃兰狐火弹（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 火头，正右为飞行方向，循环（追踪弹由游戏按速度转向）。
// 原作 lisa_attack_01_trail：亮芯火团 + 一条长拖尾 + 沿途星点。本作暖橙（避开敌弹青 #33ceff），火头是噪声边的泪滴，不画正圆。
// 精英档（docs/242 §10）：E0 一条火舌尾；E1 尾巴分成两缕（狐尾）；E2 两缕更长、尾端卷起，甩出的火星更多。
import { fit, mix, clamp, WHITE, TAU } from "../../core/index.js";
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
  const R = [3.4, 3.8, 4.2][el], L = [24, 30, 36][el];
  if (core) {
    // 尾：主火舌一条；E1 加一缕细的狐尾（从主尾上方分出、短一些、末端上卷）；E2 上下各一缕，更长
    flameBlade(p, -1, 0, -1, 0, L * (0.9 + 0.1 * N(5, S + 10)), R * 0.78, N(2.5, S + 3) * 2, N, S * 7, H, LAYERS, 0.3, 1.2);
    const wisps = el === 0 ? [] : el === 1 ? [[-1, 0.62]] : [[-1, 0.7], [1, 0.55]];
    wisps.forEach(([side, k], i) => {
      const a = side * 0.3, len = L * k * (0.9 + 0.1 * N(4, S + 20 + i));
      flameBlade(p, -R * 2.2, side * 1.6, -Math.cos(a), Math.sin(a), len, R * 0.36, side * (2.5 + el) + N(3, S + 30 + i) * 1.5, N, S * 11 + i, H, BACK_LAYERS, 0.25, 1.4);
    });
    // 火头：泪滴（前圆后尖），边缘噪声抖，白芯偏前
    p.shade(-R * 2.6, -R * 1.6, R * 1.4, R * 1.6, (x, y) => {
      const d = Math.hypot(x * (x > 0 ? 1 : 0.55), y), a = Math.atan2(y, x) / TAU;
      const rim = R + 0.6 * pnoise(a * 7 + ph * 7, 7, S + 1);
      if (d > rim) return;
      const h = 1 - d / rim + 0.15 * pnoise(a * 4 - ph * 8 + d * 0.5, 4, S + 2) + (x > 0 ? 0.1 : 0);
      return h > 0.62 ? H[0] : h > 0.45 ? H[1] : h > 0.28 ? H[3] : H[4];
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
