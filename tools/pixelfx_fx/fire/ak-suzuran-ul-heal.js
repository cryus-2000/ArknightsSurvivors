// 铃兰治疗（暖光 / 狐火渺然期间每秒回复队长，注册表 heal，docs/242 §11.2 #4；halo_ok：不外扩）：1x，原点 = 队长脚底，一次性。
// 不画环、不画十字：脚边两三团很小的暖橙狐火跳起来、往上飘着变小就灭，几颗余烬沿身侧慢慢往上飘、渐暗；光铺在脚下；画面要轻。
// 用户 11-04：一律短胖火团，不画细长火舌。分档：E0 ×0.8 / E1 ×1 / E2 ×1.2，E2 质变：中间多一团更大的、火梢淡紫。
import { fit, clamp, ease } from "../../core/index.js";
import { hotFirst, ember, floorLight } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire warmth unleashed",
  desc: "A light heal on the leader: two or three tiny warm foxfire balls hopping up beside the feet and fading as they rise, a few embers drifting up the sides.",
  tags: ["fire", "heal", "buff", "foxfire", "one-shot"],
  size: [44, 56],
  origin: [22, 46],
  duration: 0.9,
  loop: false,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 6 },
};

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, u = clamp(t / meta.duration), el = +o.elite, K = SCALE[el];
  if (core) {
    const T = [[-8, 2.4, 0, 0], [7, 2.8, 0.06, 1], [-1, 2.0, 0.12, 2]];
    if (el === 2) T.push([1.5, 3.6, 0.03, 3]);
    for (const [x, r0, d0, i] of T) {
      const v = clamp((t - d0) / 0.6);
      if (v <= 0 || v >= 1) continue;
      const rr = r0 * K * (0.5 + 0.5 * ease.outCubic(clamp(v / 0.25))) * (1 - 0.7 * ease.inQuad(clamp((v - 0.35) / 0.65)));
      foxClump(p, x * K, -rr - 9 * K * ease.outQuad(v), rr, { H, t, fps: meta.fps, seed: S * 5 + i, tips: rr > 2.6 ? 3 : 2, heat: 1 - 0.6 * v, up: 1.1, acc: el === 2 });
    }
  }
  if (deco) {
    for (let i = 0; i < 3; i++) {
      const x = [-10, 9, -5][i], d0 = 0.05 * i, age = t - d0, life = 0.6 + 0.05 * i;
      if (age < 0 || age > life) continue;
      ember(p, x + 2 * Math.sin(age * 6 + i), -4 - 30 * age, 1 - age / life, 1, [H[0], H[2], H[4], H[6]], i * 1.7 + age * 20);
    }
    floorLight(p, 0, 0, 16 * K, 5 * K, F[5], 0.3 * (1 - u));   // 光铺在队长脚下，不画圆光团
  }
}
