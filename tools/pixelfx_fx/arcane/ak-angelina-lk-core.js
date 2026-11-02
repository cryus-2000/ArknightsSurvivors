// 安洁莉娜连携的小重力核心（静帧，@2x 40×40，原点 = 中心，目标半径 20 世界像素；代码转着画、胀缩）：
// 暗紫奇点外一圈紫亮边，边上一段高光，四周三片长短不一的引力弧。
import { fit, clamp, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina link core",
  desc: "A small gravity core for Angelina's link: a dark violet singularity with a bright rim and three uneven gravity arcs around it.",
  tags: ["arcane", "gravity", "orb", "still"],
  size: [40, 40],
  origin: [20, 20],
  duration: 0.05,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.angelina, seed: 3 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7);
  p.disc(0, 0, 8, (d) => C[d < 0.55 ? 0 : 1], () => 0.95);
  for (let a = 0; a < TAU; a += 0.09) p.px(Math.cos(a) * 8, Math.sin(a) * 8, C[Math.cos(a + 2.2) > 0.6 ? 5 : 3]);
  for (const [a0, len, r] of [[0.3, 1.5, 13], [2.5, 0.9, 15.5], [4.2, 1.2, 12]])
    for (let a = a0; a < a0 + len; a += 0.06) {
      const v = (a - a0) / len;
      p.px(Math.cos(a) * (r - v * 3), Math.sin(a) * (r - v * 3), C[clamp(Math.round(2 + v * 2.5), 2, 4)]);
    }
  p.glow(0, 0, 14, C[3], 0.25);
}
