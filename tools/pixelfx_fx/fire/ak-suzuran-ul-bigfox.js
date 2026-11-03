// 铃兰大狐火（三火归一 / 精二九尾祈愿，pixelfx 放开版，docs/242）：原点 = 火头，正右为飞行方向，循环，直线贯穿。
// 原作 S2 lisa_skill_02_start：三团狐火聚拢合一爆闪再射出。本作把合成后的大狐火画成狐首形的火：尖吻朝前、两只火耳往后上掠，
// 头后鬃毛是几条长短不一的火舌，最长的一条是狐尾；白热只在吻部芯里。外形用噪声边，不画正圆。
import { fit, clamp, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameBlade, ember, looped, LAYERS, BACK_LAYERS, BIG_LAYERS } from "./_lib.js";

export const meta = {
  name: "Suzuran great foxfire unleashed",
  desc: "A merged great foxfire flying right, shaped like a fox head of flame: a pointed muzzle, two flame ears swept back, a mane of tongues and one long tail.",
  tags: ["fire", "projectile", "foxfire", "loop"],
  size: [104, 52],
  origin: [78, 28],
  duration: 0.5,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: ["#3a1a10", "#7a3414", "#c2561a", "#ff8426", "#ffb257", "#ffdca6", "#ffffff"], layer: "all", seed: 9 },
};

const D = meta.duration, NL = noiseFor(D);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = o.seed, ph = t / D;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  if (core) {
    // 鬃毛与尾：从头后往后甩，[起点 x, 起点 y, 方向角（0 = 正后）, 长, 半宽, 弯]；最长的一条是狐尾，末端上卷
    const mane = [[-6, 1, 0.05, 50, 4.2, -5, BIG_LAYERS], [-7, -3, -0.24, 30, 2.6, -4, LAYERS], [-7, 4, 0.22, 26, 2.4, 4, BACK_LAYERS], [-9, -1, -0.08, 38, 2.2, 3, BACK_LAYERS]];
    mane.forEach(([x, y, a, len, w, bend, lay], i) => {
      flameBlade(p, x, y, -Math.cos(a), Math.sin(a), len * (0.9 + 0.1 * N(4, S + i)), w, bend + N(2, S + 10 + i) * 2.2, N, S * 13 + i, H, lay, 0.35, 1.3);
    });
    // 火耳：两片往后上掠的短火舌
    for (const [x, y, a, len] of [[0, -4, -1.05, 15], [-5, -4, -0.8, 12]])
      flameBlade(p, x, y, -Math.cos(a), Math.sin(a), len * (0.92 + 0.08 * N(6, S + 40 + x)), 2.6, -2.5, N, S * 17 + x, H, LAYERS, 0.25, 0.6);
    // 头：吻部尖、后脑圆，噪声边；白热芯偏前
    p.shade(-14, -9, 14, 9, (x, y) => {
      const k = x > 0 ? Math.max(0.15, 1 - x * 0.085) : 1;   // 越往前越窄 = 尖吻
      const d = Math.hypot(x * (x > 0 ? 0.5 : 0.85), (y + (x > 0 ? x * 0.12 : 0)) / k), a = Math.atan2(y, x) / TAU;
      const rim = 6.2 + 0.7 * pnoise(a * 9 + ph * 9, 9, S + 1);
      if (d > rim) return;
      const h = 1 - d / rim + 0.12 * pnoise(a * 5 - ph * 10 + d * 0.4, 5, S + 2);
      return h > 0.78 ? H[0] : h > 0.6 ? H[1] : h > 0.42 ? H[2] : h > 0.22 ? H[3] : H[5];
    });
  }
  if (deco) {
    p.glow(2, 0, 18, F[6], 0.3);
    p.glow(-22, 0, 20, F[5], 0.18);
    looped(t, D, 16, S + 300, (r) => ({ x: -r.range(6, 44), y: r.range(-7, 7), vx: -r.range(25, 60), vy: -r.range(6, 26), life: r.range(0.2, 0.45), s: r.chance(0.3) ? 2 : 1, ph: r.range(0, TAU) }), (q, age) => {
      ember(p, q.x + q.vx * age, q.y + q.vy * age, 1 - age / q.life, q.s, [H[0], H[2], H[4], H[6]], q.ph + age * 28);
    });
  }
}
