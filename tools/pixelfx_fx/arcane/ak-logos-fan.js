// 逻各斯 S3「咒域」扇形常驻段（循环，0.6 s @10）：墨云按噪声从扇心往外流，弧边一道不规整亮边缓缓明暗。画法见 _ak-logos-fan.js。
import { fan, SIZE, ORIGIN } from "./_ak-logos-fan.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos curse fan",
  desc: "Logos's curse field: a thin ink wash fills a 100-degree fan, ink clouds drift outward, a ragged violet rim breathes along the arc.",
  tags: ["arcane", "ink", "field", "fan", "loop"],
  size: SIZE,
  origin: ORIGIN,
  duration: 0.6,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.logos, seed: 3 },
};

export function draw(p, t, o) {
  fan(p, o.palette, o.seed, { ph: t / meta.duration });
}
