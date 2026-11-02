// 艾雅法拉普攻熔岩弹（docs/231 普攻 / 技能弹体，循环 4 帧 @12，@2x，朝右，原点 = 弹心）。画法见 _ak-flame-proj.js。
import { flameProj } from "./_ak-flame-proj.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla lava shell",
  desc: "A small lava shell: a glowing molten head with dark crust tumbling on it and short uneven flame tongues trailing behind.",
  tags: ["projectile", "loop"],
  size: [36, 24],
  origin: [24, 12],
  duration: 0.3333,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.eyjafjalla, seed: 1 },
};

export function draw(p, t, o) {
  flameProj(p, t / meta.duration, { palette: o.palette, seed: o.seed, head: 5, len: 14, crust: true, tongues: [[0, 1, 2, 0], [-2.5, 0.7, 1.2, 0.33], [2.5, 0.55, 1, 0.71]] });
}
