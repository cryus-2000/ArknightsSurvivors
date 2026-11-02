// 逻各斯 S3「咒域」展开段（0.45 s @20，接常驻段第 0 帧）：一道紫线从扇心射出，首帧只有扇心那一点白；
// 随即左右张开到 100°、半径推到满，亮边冷却到常驻段的亮度。画法见 _ak-logos-fan.js。
import { fan, HALF, SIZE, ORIGIN } from "./_ak-logos-fan.js";
import { clamp, ease } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos curse fan open",
  desc: "Logos's curse field opens: a violet line shoots out from the caster and sweeps open into a 100-degree ink fan, its hot rim cooling down.",
  tags: ["arcane", "ink", "field", "fan", "one-shot"],
  size: SIZE,
  origin: ORIGIN,
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.logos, seed: 3 },
};

export function draw(p, t, o) {
  const u = clamp(t / 0.4);
  fan(p, o.palette, o.seed, {
    half: HALF * ease.outCubic(clamp((u - 0.1) / 0.9)) + 0.03,
    reach: 0.35 + 0.65 * ease.outQuart(clamp(u / 0.4)),
    k: 0.5 + 0.5 * u,
    hot: 1 - u,
  });
}
