// 铃兰精二大狐火（docs/231 普攻 / 技能弹体，循环 4 帧 @10，@2x，朝右，原点 = 弹心）。画法见 _ak-flame-proj.js。
import { flameProj } from "./_ak-flame-proj.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran great fox",
  desc: "Suzuran's great foxfire: a larger fox-head flame with ear points and three uneven flowing tails.",
  tags: ["projectile", "loop"],
  size: [48, 32],
  origin: [30, 16],
  duration: 0.4,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 1 },
};

export function draw(p, t, o) {
  flameProj(p, t / meta.duration, { palette: o.palette, seed: o.seed, head: 7, len: 18, ears: true, tongues: [[0, 1, 2.5, 0], [-4, 0.8, 1.6, 0.31], [4, 0.65, 1.4, 0.66]] });
}
