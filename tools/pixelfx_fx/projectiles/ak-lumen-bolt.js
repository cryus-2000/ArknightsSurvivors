// 流明普攻光弹（docs/231 普攻 / 技能弹体，循环 6 帧 @12，@2x，朝右，原点 = 弹心）。画法见 _ak-flame-proj.js。
import { flameProj } from "./_ak-flame-proj.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lumen bolt",
  desc: "Lumen's lantern bolt: a bright small head of light with a few thin light streaks of uneven length behind.",
  tags: ["projectile", "loop"],
  size: [36, 28],
  origin: [24, 14],
  duration: 0.5,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.lumen, seed: 1 },
};

export function draw(p, t, o) {
  flameProj(p, t / meta.duration, { palette: o.palette, seed: o.seed, head: 4, len: 16, tongues: [[0, 1, 1.5, 0], [-2, 0.6, 0.8, 0.4], [2, 0.45, 0.8, 0.77]] });
}
