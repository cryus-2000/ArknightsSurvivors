// 流明成长「光雨」（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底，无缝循环（沐雨后 rain_dur 秒）。
// 判定：半径 r = rain_r（1x = rain_r / 2），雨中敌人被照亮、每 tick 受伤。照原作 lumen_skill_02_buff_02（雨水 yushui + 水泡 + 速度线）。
// 8 颗粗雨滴斜着落进判定圈，落地溅起实心小水冠（组长 B 11-04：读得出雨）；地面一片无硬边的淡光；不画边线圈（范围靠雨读）。
// 和 S3 光圈的区别：没有转动的边弧，雨更密、更斜。只用钢蓝 7 阶。分层：core = 雨丝、落点；deco = 地面淡光、水雾点。
import { Rng, fit, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 第 12 条）

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
  options: { palette: OP.lumen, layer: "all", r: 70, seed: 6 },
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
  // 组长 B 11-04：8 颗粗雨滴（3 像素宽的水滴形：亮头 + 2 像素尾），各自在循环里落一次，落地溅起一个实心的小水冠（3 根短刺往上翘）
  for (let i = 0; i < 10; i++) {
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R * 0.9, x = Math.cos(a) * r, y = Math.sin(a) * r * SY, t0 = Rg.next(), H = Rg.range(70, 100);
    const u = ((ph - t0 + 1) % 1) / 0.4;   // 同屏约 6–8 颗在落 / 溅
    if (u < 1) {
      const yh = y - H * (1 - u * u), xh = x - WIND * H * (1 - u * u);
      for (let s2 = 0; s2 <= 7; s2 += 0.5) {
        const w = s2 < 2 ? 1.5 : 1.5 * (1 - (s2 - 2) / 6);
        for (let q = -w; q <= w; q += 0.5) p.px(xh - WIND * s2 + q, yh - s2, s2 < 2 ? (Math.abs(q) < 0.6 ? C[6] : C[5]) : C[4]);
      }
    } else if (u < 1.6) {
      const k = (u - 1) / 0.6, hh = 4 * Math.sin(Math.min(1, k * 2) * Math.PI * 0.5) * (1 - k);
      for (const dx of [-2.5, 0, 2.5]) for (let s2 = 0; s2 <= hh + (dx === 0 ? 1.5 : 0); s2 += 0.5) p.px(x + dx * (1 + k), y - s2, s2 > hh * 0.6 ? C[6] : C[5]);
      for (let an = 0.3; an < Math.PI - 0.3; an += 0.3) p.px(x + Math.cos(an) * (3 + 3 * k), y + Math.sin(an) * (1.5 + 1.5 * k), C[4]);
    }
  }
}
