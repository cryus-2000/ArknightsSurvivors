// 逻各斯 S1 咒文链（4 帧 @12 循环，@2x 128×24，原点 = 左端中点；沿线平铺，弯曲时代码加起伏）：墨链里每隔不等的几节嵌一个小字，字逐帧轮流亮。
import { glyph, link } from "./_ak-logos-script.js";
import { Rng, fit, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos S1 script chain",
  desc: "Logos's S1 script chain: an ink chain with small curse glyphs set in at uneven intervals, lighting up in turn.",
  tags: ["arcane", "ink", "chain", "loop"],
  size: [128, 24],
  origin: [0, 12],
  duration: 4 / 12,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.logos, seed: 70 },
};

export function draw(p, t, o) {
  const f = Math.floor(t * 12 + 1e-6), Rg = new Rng(o.seed);
  let x = 4, i = 0;
  while (x < 124) {
    if (Rg.chance(0.35)) { glyph(p, o.palette, x + 4, 0, 8, 10, o.seed * 5 + i, 1, (i + f) % 4 === 0 ? 5 : 3); x += 10; }
    else { link(p, o.palette, x + 4, 0, Rg.range(8, 11), 6, false, 3); link(p, o.palette, x + 10, 0, 0, 5, true, 2); x += 12; }
    i++;
  }
}
