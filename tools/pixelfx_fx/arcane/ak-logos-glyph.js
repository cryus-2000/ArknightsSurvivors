// 逻各斯普攻处决 / 命中浮起的咒文（6 帧 @18，@2x 48×48，原点 = 中心）：0–2 帧一笔笔写出（第 0 帧芯一点白），3 帧停住，4–5 帧按噪声碎散。画法见 _ak-logos-script.js。
import { glyph } from "./_ak-logos-script.js";
import { fit, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos glyph",
  desc: "A floating curse glyph for Logos: its strokes write themselves out, hold a moment, then crumble away.",
  tags: ["arcane", "ink", "glyph", "one-shot"],
  size: [48, 48],
  origin: [24, 24],
  duration: 6 / 18,
  loop: false,
  fps: 18,
  bg: "dark",
  options: { palette: OP.logos, seed: 4 },
};

export function draw(p, t, o) {
  const f = Math.floor(t * 18 + 1e-6);
  if (f > 5) return;
  const C = fit(o.palette, 7);
  if (f >= 4) {
    // 碎散：先画完整字，再按噪声挖掉
    glyph(p, o.palette, 0, 0, 30, 34, o.seed, 1, 3, (x, y) => noise(x * 0.5 + y * 0.31, o.seed + f) * 0.5 + 0.5 >= (f - 3) * 0.42);
    return;
  }
  glyph(p, o.palette, 0, 0, 30, 34, o.seed, Math.min(1, (f + 1) / 3), f === 0 ? 5 : 4);
  if (f === 0) p.px(0, 0, C[6]);
  p.glow(0, 0, 14, C[3], 0.25);
}
