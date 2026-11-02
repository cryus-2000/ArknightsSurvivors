// 安洁莉娜「失重井」地面常驻段（循环 1.2 s @10，转一整圈无缝）：不等距的螺旋臂绕中心卷入，中心暗紫，外沿一圈淡边。画法见 _ak-angelina-well.js。
import { vortex, R, SY } from "./_ak-angelina-well.js";
import { TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina gravity well",
  desc: "Angelina's gravity well on the floor: uneven spiral arms wind slowly into a dark violet core inside one ragged faint rim.",
  tags: ["arcane", "gravity", "well", "floor", "loop"],
  size: [136, 72],
  origin: [68, 36],
  duration: 1.2,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.angelina, seed: 7 },
};

export function draw(p, t, o) {
  vortex(p, o.palette, o.seed, { rot: -TAU * t / meta.duration });
}
