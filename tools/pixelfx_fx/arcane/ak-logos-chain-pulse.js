// 逻各斯精二锁链传递伤害时沿链走的脉冲（4 帧 @20，@2x 32×16，原点 = 左端中点；平铺叠在链上）：一段紫亮的光沿链从左往右推、拖一截暗尾。
import { glyph, link } from "./_ak-logos-script.js";
import { Rng, fit, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos chain pulse",
  desc: "A violet pulse running along Logos's ink chain when damage is passed on, trailing a short dim tail.",
  tags: ["arcane", "ink", "chain", "loop"],
  size: [32, 16],
  origin: [0, 8],
  duration: 4 / 20,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.logos, seed: 70 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), x0 = (t / meta.duration) * 32;
  for (let x = 0; x < 32; x++) {
    const d = x0 - x;
    if (d < 0 || d > 10) continue;
    const ci = d < 2 ? 5 : d < 5 ? 4 : 3;
    p.blend(x, 0, C[ci], 1 - d / 12); p.blend(x, -1, C[ci - 1], 0.7 - d / 14); p.blend(x, 1, C[ci - 1], 0.6 - d / 14);
  }
}
