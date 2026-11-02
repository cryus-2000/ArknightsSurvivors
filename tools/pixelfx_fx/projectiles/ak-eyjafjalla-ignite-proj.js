// 艾雅法拉 S2 点燃弹（docs/231 普攻 / 技能弹体，循环 5 帧 @14，@2x，朝右，原点 = 弹心）。画法见 _ak-flame-proj.js。
import { flameProj } from "./_ak-flame-proj.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla ignite shell",
  desc: "Eyjafjalla's igniting shell: a larger white-cored fireball with long ragged flame tongues streaming behind.",
  tags: ["projectile", "loop"],
  size: [92, 48],
  origin: [62, 24],
  duration: 0.3571,
  loop: true,
  fps: 14,
  bg: "dark",
  options: { palette: OP.eyjafjalla, seed: 1 },
};

export function draw(p, t, o) {
  flameProj(p, t / meta.duration, { palette: o.palette, seed: o.seed, head: 10, len: 46, tongues: [[0, 1, 4, 0], [-5, 0.75, 2.5, 0.27], [5, 0.6, 2, 0.61], [-2, 0.45, 1.5, 0.83]] });
}
