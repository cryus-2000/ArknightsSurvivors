// 逻各斯咒文弹 / 浮空咒文用的字表（16 格，每格 26×26 @2x，一帧一个字，游戏按格挑；代码按 13 / 格高缩放 → 26 格高正好 1 世界像素 / 贴图像素）。画法见 _ak-logos-script.js。
import { glyph } from "./_ak-logos-script.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos glyph sheet",
  desc: "Sixteen different curse glyphs for Logos, one per frame, each made of a few random strokes.",
  tags: ["arcane", "ink", "glyph", "sheet"],
  size: [26, 26],
  origin: [13, 13],
  duration: 1,
  loop: true,
  fps: 16,
  bg: "dark",
  options: { palette: OP.logos, seed: 20 },
};

export function draw(p, t, o) {
  glyph(p, o.palette, -1, -1, 18, 20, o.seed + Math.floor(t * 16 + 1e-6), 1, 4);
}
