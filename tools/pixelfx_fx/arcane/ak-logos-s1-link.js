// 逻各斯 S1 湮灭余伤传递的黑色咒文链（4 帧 @12 循环，@2x 128×32，原点 = 左端中点；沿线平铺 × 0.8）：粗一点的暗墨链，链上一串字从暗到亮再暗地闪过。
import { glyph, link } from "./_ak-logos-script.js";
import { Rng, fit, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos S1 annihilation link",
  desc: "The black script chain that carries Logos's S1 leftover damage: a heavier dark ink chain with a run of glyphs flashing dark to bright to dark.",
  tags: ["arcane", "ink", "chain", "loop"],
  size: [128, 32],
  origin: [0, 16],
  duration: 4 / 12,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.logos, seed: 70 },
};

export function draw(p, t, o) {
  const f = Math.floor(t * 12 + 1e-6), Rg = new Rng(o.seed);
  let x = 4, i = 0;
  while (x < 122) {
    const w = Rg.range(11, 15);
    link(p, o.palette, x + w / 2, 0, w, 9, false, 2);
    if (Rg.chance(0.5)) glyph(p, o.palette, x + w / 2, -9, 8, 9, o.seed * 7 + i, 1, (i + f) % 3 === 0 ? 5 : 2);
    link(p, o.palette, x + w + 2, 0, 0, 7, true, 1);
    x += w + 5; i++;
  }
}
