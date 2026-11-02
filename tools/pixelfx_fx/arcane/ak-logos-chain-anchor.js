// 逻各斯精二锁链拴在敌人身上的锁扣（6 帧 @12 循环，@2x 32×32，原点 = 中心）：一道不规整的墨环扣、环上一个小字，紫光在环上绕。只一圈。
import { glyph, link } from "./_ak-logos-script.js";
import { Rng, fit, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos chain anchor",
  desc: "The clasp where Logos's ink chain binds an enemy: one ragged ink ring with a small curse glyph, a violet glint circling it.",
  tags: ["arcane", "ink", "chain", "loop"],
  size: [32, 32],
  origin: [16, 16],
  duration: 6 / 12,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.logos, seed: 70 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration;
  for (let a = 0; a < 6.283; a += 0.08) {
    const r = 10 * (1 + 0.08 * noise(a * 2.7, o.seed)), x = Math.cos(a) * r, y = Math.sin(a) * r * 0.8;
    const hot = Math.cos(a - ph * 6.283) > 0.75;
    p.px(x, y, C[hot ? 5 : 1]); p.px(x * 0.92, y * 0.92, C[0]);
  }
  glyph(p, o.palette, 0, 0, 9, 11, o.seed, 1, 4);
}
