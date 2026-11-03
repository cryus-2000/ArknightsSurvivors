// 铃兰的小狐火（pixelfx 放开版，docs/242）：1x，原点 = 火苗根部，循环。
// 用在两处：身边绕转的待发狐火（原 fx_suzuran_wisp），和暖光 / 狐火渺然光域边上一圈贴地的小狐火（代替原来的椭圆边线）。
// 用户 11-04：一团圆胖的狐火（火尖往上跳、内芯亮、外形每 2–3 帧一变），明暗随循环起伏；ground=1 时火身压扁贴地。
// 分档：E0 ×0.8 / E1 ×1 / E2 ×1.2，E2 质变：主火团两侧各多一小团（一团 → 三团扇开），火梢淡紫。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, looped } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran small foxfire unleashed",
  desc: "A small standing foxfire: a plump flickering flame ball with leaping points and a bright heart, an ember dropping now and then.",
  tags: ["fire", "wisp", "foxfire", "loop"],
  size: [32, 36],
  origin: [16, 30],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, ground: 0, seed: 7 },
};

const D = meta.duration;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, gr = +o.ground > 0, el = +o.elite, K = SCALE[el];
  // 明暗闪烁：一个循环里亮起一次再暗下去，各簇错相位（组长 B 11-04）
  const br = 0.5 + 0.5 * Math.cos(TAU * t / D), heat = 0.65 + 0.35 * br;
  const r = (gr ? 3.4 : 3.8) * K, C = { H, t, fps: meta.fps, heat, sq: gr ? 0.7 : 1 };
  if (core) {
    if (el === 2) for (const [dx, rk, i] of [[-r * 1.15, 0.6, 1], [r * 1.2, 0.55, 2]])
      foxClump(p, dx, -r * rk * 0.9, r * rk, { ...C, seed: S + i * 5, tips: 2, up: 1, lean: dx > 0 ? 0.3 : -0.3, acc: true });
    foxClump(p, 0, -r * (gr ? 0.7 : 0.9), r, { ...C, seed: S, tips: 3, up: gr ? 1 : 1.2, acc: el === 2 });
  }
  if (deco) {
    p.glow(0, -4, 6 * K, F[6], 0.08 + 0.14 * br);
    looped(t, D, 2, S + 50, (q) => ({ x: q.range(-2, 2), vy: -q.range(14, 26), vx: q.range(-5, 5), life: q.range(0.25, 0.45), ph: q.range(0, TAU) }), (q, age) => {
      ember(p, q.x + q.vx * age, -10 * K + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 26);
    });
  }
}
