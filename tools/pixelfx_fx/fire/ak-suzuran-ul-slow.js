// 铃兰光域减速标识（注册表 status.slow，docs/242 §14.18，附件在敌人脚下）：1x，原点 = 敌人脚底，循环。
// 不画环：脚下两三缕贴地的暗橙狐火烟，像被光域拖住一样慢慢往后飘、拉长再散，几点余烬往下沉；亮度压在暖橙的暗半段，
// 不和精一灼印（焦痕 + 余烬明暗）抢，也不和队友印记（亮火苗）混。
import { fit, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxlight slow marker unleashed",
  desc: "A slow marker under an enemy: two or three low wisps of dark-orange foxfire smoke dragging back along the ground, stretching and thinning, with a few embers sinking.",
  tags: ["fire", "status", "slow", "foxfire", "loop"],
  size: [40, 20],
  origin: [20, 12],
  duration: 1.2,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", seed: 4 },
};

const D = meta.duration, NL = noiseFor(D);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D;
  if (core) {
    // 三缕烟：各自错相位，从脚下往后（左）拖、拉长、变细变暗
    for (let i = 0; i < 3; i++) {
      const u = (ph + i / 3) % 1, y0 = [-1, 1.5, 0][i], x0 = 4 - 16 * u, len = 5 + 9 * u, w = 1.4 * (1 - u * 0.7);
      for (let s = 0; s <= 1; s += 0.03) {
        const x = x0 - s * len, y = y0 + 1.2 * pnoise(s * 3 + ph * 3 + i, 3, S + i), half = w * Math.sin(Math.PI * s) + 0.2;
        if (half < 0.35) continue;
        const c = u < 0.3 ? (s < 0.4 ? H[4] : H[6]) : u < 0.65 ? H[6] : H[7];
        for (let q = -half; q <= half; q += 0.5) p.px(x, y + q * 0.6, c);
      }
    }
    // 下沉的余烬
    for (let i = 0; i < 3; i++) {
      const u = (ph * 2 + i * 0.37) % 1;
      p.px(-6 + i * 6, -6 + 6 * u, u < 0.5 ? H[3] : H[6]);
    }
  }
  if (deco) p.glow(0, 0, 7, F[4], 0.08 + 0.04 * Math.sin(TAU * ph));
}
