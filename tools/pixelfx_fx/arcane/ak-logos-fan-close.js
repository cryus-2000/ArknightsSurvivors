// 逻各斯 S3「咒域」收起段（0.4 s @20，从常驻段第 0 帧接上）：弧边先暗，墨从弧边往里按噪声干涸溶解，最后一帧为空。画法见 _ak-logos-fan.js。
import { fan, SIZE, ORIGIN } from "./_ak-logos-fan.js";
import { clamp } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos curse fan close",
  desc: "Logos's curse field fades: the rim dims and the ink dries away from the arc inward in ragged patches.",
  tags: ["arcane", "ink", "field", "fan", "one-shot"],
  size: SIZE,
  origin: ORIGIN,
  duration: 0.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.logos, seed: 3 },
};

export function draw(p, t, o) {
  const u = clamp(t / 0.35);
  if (u >= 1) return;
  fan(p, o.palette, o.seed, { k: 1 - 0.4 * u, dis: u * 1.25 });
}
