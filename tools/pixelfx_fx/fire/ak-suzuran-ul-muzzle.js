// 铃兰杖头起火（pixelfx 放开版，docs/242）：1x，原点 = 杖头，狐火朝右射出。
// 原作 lisa_attack_01_start：杖头火团 + 一道朝前的光芒 + 星点。本作：首帧白热的偏心火苗（往前最长）→ 两三条小火舌往前上方舔出就塌 → 一两颗有重量的碎火往下落（11-04 §0：不撒点）；
// 全是噪声边，不画圆盘。big = 三火归一（E2 每次普攻）：三团小火从三个方向收进杖头再爆亮一次。
// 分档（非 big）：E0 ×0.8 两条火舌；E1 ×1、爆点两连亮；E2 ×1.2、三条火舌、舌梢淡紫。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameBlade, ember, sparkAt, LAYERS, BACK_LAYERS } from "./_lib.js";
import { SCALE, ACC, tongueTip, bladeTip } from "./_suzuran_ul.js";   // 分档体量 + E2 淡紫灵光（组长 B 11-04）
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定，样板 843736ef8）

export const meta = {
  name: "Suzuran staff ignition unleashed",
  desc: "Foxfire kindling at the staff tip: a lopsided white-hot flare leaning forward, a few small tongues licking ahead and collapsing, sparks.",
  tags: ["fire", "muzzle", "cast", "foxfire", "one-shot"],
  size: [56, 48],
  origin: [20, 26],
  duration: 0.32,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, big: 0, quick: 0, seed: 2 },
};

const NL = noiseFor(0);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, big = +o.big > 0, LQ = +o.quick > 0 ? 0.5 : 1, el = big ? 2 : +o.elite, K = big ? 1 : SCALE[el];
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const T0 = big ? 0.12 : 0;   // big：前 0.12 s 三团收进来
  const u = clamp((t - T0) / (meta.duration - T0)), pop1 = t - T0 < 0.045 ? 1 : 1 - clamp((t - T0 - 0.045) / 0.06);   // 定帧：头一两帧满白热
  const pop2 = !big && el >= 1 && t - T0 > 0.11 && t - T0 < 0.17 ? 0.7 * (1 - clamp((t - T0 - 0.11) / 0.06)) : 0, pop = Math.max(pop1, pop2);   // E1 / E2 第二下
  if (core) {
    if (big && t < T0 + 0.02) {
      const k = ease.inQuad(clamp(t / T0));
      for (const [a, i] of [[2.2, 0], [-2.4, 1], [0.9, 2]]) {
        const r = 16 * (1 - k), x = Math.cos(a) * r, y = Math.sin(a) * r * 0.7;
        flameBlade(p, x, y, -Math.cos(a) * 0.3, -1, 6 + 3 * k, 2.2, 0, N, S * 3 + i, H, LAYERS, 0.4, 0.8);
      }
    }
    if (t >= T0 && pop > 0) {
      const R = (big ? 5.5 : 4 * K) * (0.65 + 0.35 * pop) * (pop2 > pop1 ? 0.75 : 1);
      p.shade(-R * 1.3, -R * 1.3, R * 2.6, R * 1.3, (x, y) => {
        const d = Math.hypot(x * (x > 0 ? 0.45 : 1.1), y * 1.1), a = Math.atan2(y, x) / TAU, rim = R * (0.3 + 0.95 * Math.max(0, pnoise(a * 9, 9, S + 5)) ** 1.4);
        if (d > rim) return;
        const h = 1 - d / rim;
        return pop > 0.5 ? (h > 0.45 ? H[0] : H[2]) : h > 0.4 ? H[1] : H[3];
      });
    }
    // 小火舌：往前上方舔出就塌
    const licks = big ? [[-0.35, 13], [0.05, 17], [0.45, 11]] : el === 2 ? [[-0.45, 10 * K], [0.05, 13 * K], [0.5, 9 * K]] : [[-0.4, 10 * K], [0.1, 13 * K]];
    licks.forEach(([a, len], i) => {
      const v = clamp((t - T0 - 0.01 * i) / (meta.duration - T0)), g = ease.outCubic(clamp(v / 0.3)) * (1 - ease.inQuad(clamp((v - 0.3) / 0.7)));
      const bw = 2 * K * (0.5 + 0.5 * g), bd = -2 + N(3, S + i) * 2, LY = v < 0.45 ? LAYERS : BACK_LAYERS;
      if (g > 0.06) flameBlade(p, 1, 0, Math.cos(a), Math.sin(a) - 0.25, len * g, bw, bd, N, S * 9 + i, H, LY, 0.35, 1.0);
      if (g > 0.3 && el === 2 && !big) bladeTip(p, 1, 0, Math.cos(a), Math.sin(a) - 0.25, len * g, bw, bd, N, S * 9 + i, LY, 0.35, 1.0);
    });
  }
  if (deco && t >= T0) {
    p.glow(3, 0, big ? 10 : 7, F[6], (big ? 0.3 : 0.2) * (1 - u) * (1 - u));
    const n = LQ < 1 ? 0 : big ? 2 : 1;
    for (let i = 0; i < n; i++) {
      const a = [-0.5, 0.2][i], sp = 60 + 20 * i, age = t - T0 - 0.03;
      if (age < 0) continue;
      const [x, y] = sparkAt(3, 0, Math.cos(a) * sp, Math.sin(a) * sp, age, 20, 360, 2.2);
      ember(p, x, y, 1 - u, 1, [H[0], H[2], H[4], H[6]], i * 2.1 + age * 30);
    }
  }
}
