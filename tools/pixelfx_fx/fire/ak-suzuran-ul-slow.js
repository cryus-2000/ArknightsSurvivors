// 铃兰光域减速标识（注册表 status.slow，docs/242 §14.18，附件在敌人脚下）：1x，原点 = 敌人脚底，循环。
// 不画环：脚下两三团暗橙的小狐火贴地慢慢往后飘、往上散、变暗变小（像被光域拖住），几点余烬往下沉；亮度压在暖橙的暗半段，
// 不和精一灼印（焦痕 + 余烬明暗）抢，也不和队友印记（亮火团）混。用户 11-04：短胖火团，不拖烟带。
// 分档：E0 ×0.8 / E1 ×1 三团；E2 ×1.2 质变：四团，火梢淡紫。
import { fit } from "../../core/index.js";
import { hotFirst } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxlight slow marker unleashed",
  desc: "A slow marker under an enemy: two or three small dim foxfire balls drifting back along the ground, rising and thinning as they go, with a few embers sinking.",
  tags: ["fire", "status", "slow", "foxfire", "loop"],
  size: [44, 28],
  origin: [22, 18],
  duration: 1.2,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 4 },
};

const D = meta.duration;

export function draw(p, t, o) {
  const core = o.layer !== "deco";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D, el = +o.elite, K = SCALE[el];
  if (!core) return;
  const NW = el === 2 ? 4 : 3;
  for (let i = 0; i < NW; i++) {
    const u = (ph + i / NW) % 1, y0 = [-1, 1.5, 0, 2.5][i] * K;
    const x = (5 - 18 * u) * K, y = y0 - 5 * u * K, r = 2.4 * K * Math.sin(Math.PI * u) ** 0.6;
    if (r > 0.9) foxClump(p, x, y - r * 0.6, r, { H, t, fps: meta.fps, seed: S + i * 5, tips: 2, heat: 0.55 - 0.35 * u, up: 0.9, lean: -0.4, sq: 0.8, acc: el === 2 && u < 0.6 });
  }
  for (let i = 0; i < 3; i++) {   // 下沉的余烬
    const u = (ph * 2 + i * 0.37) % 1;
    p.px((-6 + i * 6) * K, -6 * K + 6 * u * K, u < 0.5 ? H[3] : H[6]);
  }
}
