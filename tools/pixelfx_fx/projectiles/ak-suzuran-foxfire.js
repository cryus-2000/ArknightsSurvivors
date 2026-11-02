// 铃兰狐火弹（docs/231 普攻 / 技能弹体，循环 6 帧 @12，@2x，朝右，原点 = 弹心）。画法见 _ak-flame-proj.js。
import { flameProj } from "./_ak-flame-proj.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran foxfire",
  desc: "Suzuran's foxfire: a small golden flame with two fox-ear points on its head and uneven flickering tails.",
  tags: ["projectile", "loop"],
  size: [36, 28],
  origin: [22, 14],
  duration: 0.5,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 1 },
};

export function draw(p, t, o) {
  flameProj(p, t / meta.duration, { palette: o.palette, seed: o.seed, head: 4.5, len: 14, ears: true, tongues: [[0, 1, 1.8, 0], [-2.5, 0.7, 1, 0.37], [2.5, 0.55, 1, 0.69]] });
}
