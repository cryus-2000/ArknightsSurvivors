// 铃兰治疗（暖光 / 狐火渺然期间每秒回复队长，注册表 heal，docs/242 §11.2 #4；halo_ok：不外扩）：1x，原点 = 队长脚底，一次性。
// 不画环、不画十字：脚边两三缕很小的暖橙火苗往上舔一下就收，几颗余烬沿身侧慢慢往上飘、渐暗；一秒内合并播一次，画面要轻。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, ember, floorLight, LAYERS } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire warmth unleashed",
  desc: "A light heal on the leader: two or three tiny warm flames licking up beside the feet and folding away, a few embers drifting slowly up the sides and fading.",
  tags: ["fire", "heal", "buff", "foxfire", "one-shot"],
  size: [40, 52],
  origin: [20, 44],
  duration: 0.9,
  loop: false,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", seed: 6 },
};

const NL = noiseFor(0);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, u = clamp(t / meta.duration);
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  if (core) {
    for (const [x, h, d0, i] of [[-8, 7, 0, 0], [7, 9, 0.06, 1], [-1, 5, 0.12, 2]]) {
      const v = clamp((t - d0) / 0.5), g = ease.outCubic(clamp(v / 0.3)) * (1 - ease.inQuad(clamp((v - 0.35) / 0.65)));
      if (g > 0.06) flameTongue(p, x, 0, h * g, 1.5 * (0.5 + 0.5 * g), 0, N, S * 5 + i, H, LAYERS, 0.3, 0.7);
    }
  }
  if (deco) {
    for (let i = 0; i < 3; i++) {
      const x = [-10, 9, -5][i], d0 = 0.05 * i, age = t - d0, life = 0.6 + 0.05 * i;
      if (age < 0 || age > life) continue;
      ember(p, x + 2 * Math.sin(age * 6 + i), -4 - 30 * age, 1 - age / life, 1, [H[0], H[2], H[4], H[6]], i * 1.7 + age * 20);
    }
    floorLight(p, 0, 0, 16, 5, F[5], 0.3 * (1 - u));   // 光铺在队长脚下，不画圆光团（11-04 §0）
  }
}
