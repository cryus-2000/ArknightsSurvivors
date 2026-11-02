// 安洁莉娜「失重井」收束段（0.25 s @20，从常驻段接上）：螺旋臂往中心塌缩、越收越亮，最后中心一点紫光散掉，末帧为空。画法见 _ak-angelina-well.js。
import { vortex } from "./_ak-angelina-well.js";
import { clamp, ease, fit, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina gravity well close",
  desc: "Angelina's gravity well collapses: the spiral arms are sucked into the core, brightening, and wink out in a small violet spark.",
  tags: ["arcane", "gravity", "well", "floor", "one-shot"],
  size: [136, 72],
  origin: [68, 36],
  duration: 0.25,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.angelina, seed: 7 },
};

export function draw(p, t, o) {
  const u = clamp(t / 0.2), C = fit(o.palette, 7);
  if (u >= 1) return;
  vortex(p, o.palette, o.seed, { rot: -TAU * t / 0.5, reach: 1 - 0.8 * ease.inCubic(u), k: 1 - 0.5 * u, hot: 0.4 * u, rim: 1 - u });
  if (u > 0.6) p.ellipse(0, 0, 3 * (1 - u) + 1, 1.5 * (1 - u) + 0.5, C[5]);
}
