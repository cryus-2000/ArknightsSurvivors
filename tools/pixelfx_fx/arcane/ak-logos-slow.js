// 逻各斯 S3 被减速的敌弹标记（4 帧 @12 循环，@2x 48×48，原点 = 中心，中心镂空让敌弹露出来）：
// 一圈断续的紫线（断口位置随机），上面三个大小不一的小字慢慢转。只一圈。
import { glyph } from "./_ak-logos-script.js";
import { fit, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos slow mark",
  desc: "A mark on enemy bullets slowed by Logos's field: one broken violet ring with three small curse glyphs of uneven size turning on it, hollow in the middle.",
  tags: ["arcane", "ink", "mark", "loop"],
  size: [48, 48],
  origin: [24, 24],
  duration: 4 / 12,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.logos, seed: 50 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration, R = 16;
  for (let a = 0; a < TAU; a += 0.06) if (noise(a * 2.3, o.seed) > -0.25) p.px(Math.cos(a) * R, Math.sin(a) * R, C[3]);
  [[0.4, 8], [2.6, 6], [4.4, 7]].forEach(([a0, s], i) => {
    const a = a0 + ph * (TAU / 3);
    glyph(p, o.palette, Math.cos(a) * R, Math.sin(a) * R, s, s + 2, o.seed + i, 1, 4);
  });
}
