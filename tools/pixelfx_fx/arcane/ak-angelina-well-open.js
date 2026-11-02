// 安洁莉娜「失重井」张开段（0.3 s @20，接常驻段第 0 帧）：首帧中心一点白、外沿一圈紫亮，螺旋臂从小往外撑开到满半径后冷却。画法见 _ak-angelina-well.js。
import { vortex } from "./_ak-angelina-well.js";
import { clamp, ease, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina gravity well open",
  desc: "Angelina's gravity well opens: a violet rim snaps out on the floor and the spiral arms spread to full size while cooling.",
  tags: ["arcane", "gravity", "well", "floor", "one-shot"],
  size: [136, 72],
  origin: [68, 36],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.angelina, seed: 7 },
};

export function draw(p, t, o) {
  const u = clamp(t / 0.28);
  vortex(p, o.palette, o.seed, { rot: -TAU * (t - 0.3) / 1.2, reach: 0.45 + 0.55 * ease.outCubic(u), hot: 1 - u, k: 0.6 + 0.4 * u });
  if (t < 0.05) p.px(0, 0, 0xffffffff);
}
