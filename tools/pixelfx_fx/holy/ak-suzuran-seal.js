// 铃兰「灼印」敌人脚下（循环 0.6 s @10，@2x，原点 = 脚下中心，透视 sy 0.5；游戏缩放 r / 14 限 0.8–1.1）：
// 一圈不规整的金色细边，边上两三朵小狐火在不等距的位置一明一暗地跳，中间几粒光点；只一圈。
import { fit, clamp, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran brand",
  desc: "Suzuran's foxfire brand under an enemy: one ragged thin golden ring with a few small foxfire flames flickering at uneven spots.",
  tags: ["holy", "fire", "foxfire", "mark", "floor", "loop"],
  size: [40, 28],
  origin: [20, 16],
  duration: 0.6,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 6 },
};

const R = 14, SY = 0.5;
const FL = [{ a: 0.5, h: 6, ph: 0 }, { a: 2.6, h: 4, ph: 0.35 }, { a: 4.3, h: 5, ph: 0.7 }];

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration, S = o.seed;
  for (let a = 0; a < TAU; a += 0.9 / R) {
    const r = R * (1 + 0.08 * noise(a * 3.1, S) + 0.04 * noise(a * 7.7 + ph * TAU, S + 1));
    const lit = 0.5 + 0.5 * Math.sin(a * 2 - ph * TAU);
    p.blend(Math.cos(a) * r, Math.sin(a) * r * SY, C[lit > 0.6 ? 4 : 3], 0.6 + 0.35 * lit);
  }
  for (const f of FL) {
    const x = Math.cos(f.a) * R, y = Math.sin(f.a) * R * SY, k = 0.5 + 0.5 * Math.sin((ph + f.ph) * TAU), h = f.h * (0.6 + 0.4 * k);
    for (let d = 0; d < h; d += 0.5) {
      const v = d / h, w = (1 - v) * 1.4;
      for (let q = -w; q <= w; q += 1) p.px(x + q + Math.sin(v * 3 + ph * TAU) * 0.6, y - d, C[clamp(Math.round(5 - v * 2.5), 2, 5)]);
    }
  }
}
