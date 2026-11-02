// 逻各斯精一「魂咒」敌人头顶的小咒文（按层数 1–3 三张，4 帧 @8 循环，@2x 16×20，原点 = 中心）：一个小字，旁边 layers 个亮点，亮度逐帧起伏。
import { glyph } from "./_ak-logos-script.js";
import { fit, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos soul rune",
  desc: "A small curse rune over an enemy marked by Logos, with one to three bright stacks beside it, gently pulsing.",
  tags: ["arcane", "ink", "glyph", "mark", "loop"],
  size: [16, 20],
  origin: [8, 10],
  duration: 0.5,
  loop: true,
  fps: 8,
  bg: "dark",
  options: { palette: OP.logos, layers: 1, seed: 30 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), k = 0.5 + 0.5 * Math.sin((t / meta.duration) * TAU);
  glyph(p, o.palette, -1, -1, 10, 13, o.seed, 1, k > 0.5 ? 4 : 3);
  for (let i = 0; i < o.layers; i++) p.px(5, -6 + i * 4, C[k > 0.4 ? 5 : 4]);
}
