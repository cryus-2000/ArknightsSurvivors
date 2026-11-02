// 逻各斯书写带（沿线平铺、滚动，4 帧 @12，@2x 128×24，原点 = 左端中点）：一行宽窄不一的咒文，字距随机；逐帧有一两个字亮一下。
// 一格 128 像素里字距随机，平铺后的重复周期 = 整格宽（游戏里 × 0.8 ≈ 102 世界像素）。画法见 _ak-logos-script.js。
import { glyph } from "./_ak-logos-script.js";
import { Rng } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos script band",
  desc: "A band of Logos's curse script for tiling along a line: glyphs of uneven width and spacing, one or two flaring each frame.",
  tags: ["arcane", "ink", "script", "loop"],
  size: [128, 24],
  origin: [0, 12],
  duration: 4 / 12,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.logos, seed: 8 },
};

export function draw(p, t, o) {
  const f = Math.floor(t * 12 + 1e-6), Rg = new Rng(o.seed);
  let x = 4, i = 0;
  while (x < 120) {
    const w = Rg.range(9, 15), hot = Rg.int(0, 3) === f;
    glyph(p, o.palette, x + w / 2, 0, w, 16, o.seed * 3 + i, 1, hot ? 5 : 3);
    x += w + Rg.range(2, 6); i++;
  }
}
