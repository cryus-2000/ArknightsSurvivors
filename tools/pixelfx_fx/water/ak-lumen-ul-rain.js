// 流明成长「光雨」（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底，无缝循环（沐雨后 rain_dur 秒）。
// 判定：半径 r = rain_r（1x = rain_r / 2），雨中敌人被照亮、每 tick 受伤。照原作 lumen_skill_02_buff_02（雨水 yushui + 水泡 + 速度线）。
// 一片斜细雨持续落在判定圈里，落点亮一个扁的小涟漪（不长大）；地面一片无硬边的淡光；不画边线圈（范围靠雨读）。
// 和 S3 光圈的区别：没有转动的边弧，雨更密、更斜。只用钢蓝 7 阶。分层：core = 雨丝、落点；deco = 地面淡光、水雾点。
import { Rng, fit, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Lumen light rain unleashed",
  desc: "A slanted drizzle falls steadily inside the area, each drop leaving a small flat ripple on a soft ground light.",
  tags: ["water", "rain", "zone", "loop"],
  size: [176, 170],
  origin: [88, 130],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", r: 70, seed: 6 },
};

const SY = 0.5, WIND = 0.3;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, D = meta.duration, ph = (t % D) / D, Rg = new Rng(o.seed);
  if (deco) {
    for (let y = -R * SY; y <= R * SY; y += 1)
      for (let x = -R; x <= R; x += 1) {
        const q = Math.hypot(x / R, y / (R * SY)) * (0.9 + 0.2 * noise(Math.atan2(y, x) * 1.6, o.seed));
        if (q < 1) p.blend(x, y, C[3], 0.08 * (1 - q) * (1 - q));
      }
    for (let i = 0; i < 8; i++) {
      const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R, u = (ph + Rg.next()) % 1;
      p.dot(Math.cos(a) * r, Math.sin(a) * r * SY - 4 - u * 10, C[4], Math.sin(u * Math.PI) * 0.6);
    }
  }
  if (!core) return;
  for (let i = 0; i < 30; i++) {
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R * 0.95, x = Math.cos(a) * r, y = Math.sin(a) * r * SY, t0 = Rg.next(), L = Rg.range(9, 15), H = Rg.range(70, 100);
    const u = ((ph - t0 + 1) % 1) / 0.16;
    if (u < 1) {
      const yh = y - H * (1 - u), xh = x - WIND * H * (1 - u);
      for (let s = 0; s <= L; s += 0.5) p.dot(xh - WIND * s, yh - s, s < 1.5 ? C[6] : s < L * 0.5 ? C[5] : C[4], s < L * 0.5 ? 1 : 1.3 - s / L);
    } else if (u < 2.5) {
      const k = 1 - (u - 1) / 1.5;
      for (let an = 0.3; an < Math.PI - 0.3; an += 0.35) p.dot(x + Math.cos(an) * 3.5, y + Math.sin(an) * 1.5, u < 1.3 ? C[6] : C[5], k);
    }
  }
}
