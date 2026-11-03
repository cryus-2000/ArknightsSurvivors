// 流明终结技光圈（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 光圈中心，无缝循环（光柱持续的 2 秒里一直画）。
// 判定：半径 R = ult/lu_r（balance，502 世界像素；1x = R / 2）。用户 11-04 否外扩光环：不画往外推的环，光圈「原地亮起」，
// 判定半径上 6 段断开的涟漪弧、亮度沿圈起伏（单帧，游戏里随时间调透明度呼吸）；圈里的细雨用光雨帧条铺；不铺实心光盘。
// 只用钢蓝 7 阶。分层：core = 边弧、雨丝、落点；deco = 往上飘的光点（没有地面淡光，省显存）。
import { Rng, fit, noise, smooth, TAU } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 第 12 条）

export const meta = {
  name: "Lumen ultimate zone unleashed",
  desc: "Six broken ripple arcs turn slowly on the zone's edge while a sparse slanted drizzle falls inside.",
  tags: ["water", "zone", "ultimate", "loop"],
  size: [520, 300],
  origin: [260, 150],
  duration: 0.1,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", r: 251, seed: 9 },
};

const SY = 0.5;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, ph = (t % meta.duration) / meta.duration, Rg = new Rng(o.seed);
  const segs = [];
  for (let i = 0; i < 6; i++) segs.push({ c: (i + Rg.range(-0.15, 0.15)) * TAU / 6, half: Rg.range(0.18, 0.3), s: Rg.next() * 9 });
  if (deco)
    for (let i = 0; i < 24; i++) {
      const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R * 0.9, u = (ph + Rg.next()) % 1;
      p.dot(Math.cos(a) * r, Math.sin(a) * r * SY - u * 30, C[5], Math.sin(u * Math.PI) * 0.8);
    }
  if (!core) return;
  for (const sg of segs)
    for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.4 / R) {
      const e = 1 - Math.abs(an - sg.c) / sg.half, a = an, n = noise(an * 2.4 + sg.s, o.seed + 3);
      p.dot(Math.cos(a) * R, Math.sin(a) * R * SY, n > 0.65 ? C[6] : n > 0.35 ? C[5] : C[4], smooth(0, 0.3, e) * (n > 0.2 ? 0.95 : 0.55));
      if (n > 0.5) p.dot(Math.cos(a) * (R - 1), Math.sin(a) * (R - 1) * SY, C[4], smooth(0, 0.3, e) * 0.6);
    }
  // 圈里的细雨不烤进这张（省显存）：游戏里用光雨帧条 fx_lumen_ul_rain 在圈内错开铺几块
}
