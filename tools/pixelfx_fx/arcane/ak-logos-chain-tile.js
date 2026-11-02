// 逻各斯精二「锁链」平铺段（6 帧 @12 循环，@2x 32×16，原点 = 左端中点；沿两敌之间平铺、滚动）：一横环一竖环交替的墨链，两环大小略不同；高光沿链缓缓走过。
import { glyph, link } from "./_ak-logos-script.js";
import { Rng, fit, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos chain tile",
  desc: "A tile of Logos's ink chain for linking enemies: alternating face-on and edge-on ink links of slightly different size, a glint sliding along.",
  tags: ["arcane", "ink", "chain", "loop"],
  size: [32, 16],
  origin: [0, 8],
  duration: 6 / 12,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.logos, seed: 70 },
};

export function draw(p, t, o) {
  const f = Math.floor(t * 12 + 1e-6);
  link(p, o.palette, 8, 0, 13, 8, false, f < 3 ? 4 : 3);
  link(p, o.palette, 21, 0, 0, 7, true, 3);
  link(p, o.palette, 27, 0, 9, 6, false, f >= 3 ? 4 : 3);
}
