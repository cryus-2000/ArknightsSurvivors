// 铃兰杖头起火（pixelfx 放开版，docs/242）：1x，原点 = 杖头，狐火朝右射出。
// 首帧白热的偏心火苗（往前最长、噪声边、定帧一两帧）→ 一团圆胖的狐火在杖头跳起、闪动、往上飘着缩小 → 一两颗碎火往下落。
// 用户 11-04：不画长弯火舌，一律短胖火团。big = 三火归一（E2 每次普攻）：三团小狐火从三个方向收进杖头再爆亮一次。
// 分档（非 big）：E0 ×0.8 一团；E1 ×1、爆点两连亮；E2 ×1.2、三团扇开、火梢淡紫。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { pnoise, hotFirst, ember, sparkAt } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran staff ignition unleashed",
  desc: "Foxfire kindling at the staff tip: a lopsided white-hot flare leaning forward, then a plump flickering foxfire ball leaping up and shrinking, an ember falling.",
  tags: ["fire", "muzzle", "cast", "foxfire", "one-shot"],
  size: [56, 48],
  origin: [20, 26],
  duration: 0.32,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, big: 0, quick: 0, seed: 2 },
};

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, big = +o.big > 0, LQ = +o.quick > 0 ? 0.5 : 1, el = big ? 2 : +o.elite, K = big ? 1 : SCALE[el];
  const T0 = big ? 0.12 : 0;   // big：前 0.12 s 三团收进来
  const u = clamp((t - T0) / (meta.duration - T0)), pop1 = t - T0 < 0.045 ? 1 : 1 - clamp((t - T0 - 0.045) / 0.06);   // 定帧：头一两帧满白热
  const pop2 = !big && el >= 1 && t - T0 > 0.11 && t - T0 < 0.17 ? 0.7 * (1 - clamp((t - T0 - 0.11) / 0.06)) : 0, pop = Math.max(pop1, pop2);   // E1 / E2 第二下
  const C = { H, t, fps: meta.fps };
  if (core) {
    if (big && t < T0 + 0.02) {
      const k = ease.inQuad(clamp(t / T0));
      for (const [a, i] of [[2.2, 0], [-2.4, 1], [0.9, 2]]) {
        const r = 16 * (1 - k);
        foxClump(p, Math.cos(a) * r, Math.sin(a) * r * 0.7, 3 + 1.2 * k, { ...C, seed: S * 3 + i, tips: 2, up: 1 });
      }
    }
    // 火团：杖头跳起、往前上方飘、缩小冷却（E2 / big 三团扇开）
    const balls = big ? [[-0.9, 9, 5.2], [-0.35, 12, 4.4], [0.25, 9, 3.8]] : el === 2 ? [[-1.0, 8 * K, 3.6 * K], [-0.4, 10 * K, 4.2 * K], [0.2, 8 * K, 3.2 * K]] : [[-0.45, 9 * K, 4.2 * K]];
    balls.forEach(([a, d, r0], i) => {
      const v = clamp((t - T0 - 0.02 - 0.012 * i) / (meta.duration - T0)), g = ease.outCubic(clamp(v / 0.4));
      if (v <= 0 || v >= 1) return;
      const rr = r0 * (0.6 + 0.4 * ease.outCubic(clamp(v / 0.2))) * (1 - 0.6 * ease.inQuad(clamp((v - 0.4) / 0.6)));
      foxClump(p, 2 + Math.cos(a) * d * g, Math.sin(a) * d * g - 3 * v, rr, { ...C, seed: S * 9 + i, tips: rr > 3 ? 3 : 2, heat: 1 - 0.7 * v, up: 1.1, lean: 0.25, acc: el === 2 && !big });
    });
    if (t >= T0 && pop > 0) {
      const R = (big ? 5.5 : 4 * K) * (0.65 + 0.35 * pop) * (pop2 > pop1 ? 0.75 : 1);
      p.shade(-R * 1.3, -R * 1.3, R * 2.6, R * 1.3, (x, y) => {
        const d = Math.hypot(x * (x > 0 ? 0.45 : 1.1), y * 1.1), a = Math.atan2(y, x) / TAU, rim = R * (0.3 + 0.95 * Math.max(0, pnoise(a * 9, 9, S + 5)) ** 1.4);
        if (d > rim) return;
        const h = 1 - d / rim;
        return pop > 0.5 ? (h > 0.45 ? H[0] : H[2]) : h > 0.4 ? H[1] : H[3];
      });
    }
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
