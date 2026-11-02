// 塞雷娅晶柱站立循环（D 组）：@2x 密度，4 帧 @6 循环，原点 = 底边中点。替换 fx_saria_pillar_idle。
// 同 ak-saria-pillar 拔起后的那根柱子，一道高光沿柱身慢慢往上扫，扫到顶再从底部重来；不加光圈。
import { Rng, fit, crystal } from "../../core/index.js";
import { OP } from "../house.js";
import { prism } from "./ak-saria-lib.js";   // 块状钙晶棱柱（11-03 用户嫌细针晶体怪）

export const meta = {
  name: "Saria pillar idle",
  desc: "The standing amber calcite pillar as a four-frame loop: a glint climbs the shaft and starts again from the base.",
  tags: ["earth", "crystal", "loop"],
  size: [72, 72],
  origin: [36, 64],
  duration: 0.6667,
  loop: true,
  fps: 6,
  bg: "ground",
  options: { palette: ["#3a2a1c", OP.saria[0], OP.saria[1], OP.saria[2], "#ecd2a6", "#f8e4c0", "#fff0d4", "#ffffff"], seed: 4 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed), f = Math.floor(t * 6 + 1e-6) % 4;
  const side = [{ x: R.range(-8, -6), h: R.range(10, 14), w: 6, lean: -3 }, { x: R.range(5, 8), h: R.range(7, 11), w: 5, lean: 3 }];
  for (const s of side) prism(p, s.x, 0, s.h, s.w * 1.3, s.lean, C, { skew: s.lean > 0 ? -0.4 : 0.4 });
  prism(p, 0, 0, 50, 16, R.range(-1, 1), C, { skew: 0.3, glint: [0.2, 0.42, 0.64, 0.86][f] });
}
