// 逻各斯 S3 咒域扇边的竖条符文（8 帧 @8 循环，@2x 24×56，原点 = 底边中点；游戏按不同高宽拉、条位已不等距）：
// 一竖列三个字，字高不一，逐帧轮流有一个字亮起；底下一缕墨往上淡。
import { glyph } from "./_ak-logos-script.js";
import { fit, clamp } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos fan ribbon",
  desc: "A vertical strip of three curse glyphs of uneven height on the edge of Logos's curse field, one glyph flaring in turn, ink wisping up from below.",
  tags: ["arcane", "ink", "glyph", "loop"],
  size: [24, 56],
  origin: [12, 56],
  duration: 1,
  loop: true,
  fps: 8,
  bg: "dark",
  options: { palette: OP.logos, seed: 40 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), f = Math.floor(t * 8 + 1e-6);
  const hs = [16, 12, 14];
  let y = -6;
  hs.forEach((h, i) => { glyph(p, o.palette, 0, y - h / 2, 14, h, o.seed + i, 1, f % 3 === i ? 5 : 3); y -= h + 2; });
  for (let yy = -1; yy > -10; yy--) p.blend((yy % 3) * 0.5, yy, C[1], clamp(0.6 + yy * 0.05));
}
