// 铃兰身边绕行的小狐火（循环 0.5 s @8，@2x 16×24，原点 = 火苗底）：火苗左右摆、顶端分成长短不一的两尖，芯亮边暗。
import { fit, clamp, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran wisp",
  desc: "A small foxfire flame that orbits Suzuran: it sways, its tip splits into two uneven points, bright core and darker rim.",
  tags: ["holy", "fire", "foxfire", "loop"],
  size: [16, 24],
  origin: [8, 20],
  duration: 0.5,
  loop: true,
  fps: 8,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 1 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration, H = 14 + 2 * Math.sin(ph * TAU);
  for (let y = 0; y < H; y++) {
    const v = y / H, sway = 1.6 * Math.sin(ph * TAU + v * 2.4) * v;
    const w = 3.6 * Math.sin(Math.PI * Math.min(1, (v + 0.15) / 1.0)) * (1 - 0.3 * v);
    for (let x = -Math.ceil(w); x <= Math.ceil(w); x++) {
      const q = Math.abs(x) / Math.max(0.5, w);
      if (q > 1) continue;
      if (v > 0.75 && Math.abs(x - sway - (x > 0 ? 1.2 : -0.6)) < 0.8 && noise(y * 0.7 + ph * 6, 2) > -0.2) continue;   // 顶端劈成两尖
      p.px(x + sway, -y, C[clamp(Math.round(5.2 - q * 2.2 - v * 1.4), 2, 6)]);
    }
  }
}
