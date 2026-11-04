// 流明成长「灯塔守望·回光」光脉冲（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底（圆形判定圆心）。
// 判定：半径 r = watch2_r（1x = watch2_r / 2），沐雨时和灯火不灭期间每秒一圈，命中减速。原作无（本作成长）。
// 用户 11-04 否外扩光环：不做「一圈往外推的环」，改成判定半径上 4–5 段弧原地亮一下再熄，弧上各挂一颗被照亮的小十字；中心一下竖直细光。
// 每秒都会放，要克制：0.35 s 收完。只用钢蓝 7 阶。分层：core = 边弧、十字、竖光；deco = 弧上的淡光。
import { Rng, fit, clamp, smooth, noise, TAU } from "../../core/index.js";
import { OP, jitterAngles } from "../house.js";

// 用户 11-04 否「绕身 / 脚下的匀称圆环」：不沿同一圆周均匀摆弧——身前 nF 段长短、半径都不等（最远一段贴判定半径），身后 nB 段短小的；
// 正右 = 朝向，朝左时游戏里翻转
const dirArcs = (Rg, R, nF, nB) => {
  const out = [];
  for (let i = 0; i < nF; i++) out.push({ c: Rg.range(-0.25, 0.25) + (i - (nF - 1) / 2) * Rg.range(0.5, 0.7), half: Rg.range(0.22, 0.5), r: R * (i === 0 ? 1 : Rg.range(0.62, 0.86)), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) });
  for (let i = 0; i < nB; i++) out.push({ c: Math.PI + Rg.range(-0.8, 0.8), half: Rg.range(0.12, 0.24), r: R * Rg.range(0.35, 0.55), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) });
  return out;
};

export const meta = {
  name: "Lumen lighthouse pulse unleashed",
  desc: "Four or five broken arcs flash in place on the pulse radius with small glints on them, then go out.",
  tags: ["light", "pulse", "one-shot"],
  size: [136, 110],
  origin: [68, 70],
  duration: 0.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", r: 60, seed: 3 },
};

const SY = 0.5;
// §0（组长 B 11-04）：弧是有厚度的水幕 / 光片——4 美术像素厚，外缘亮、往里一层层变暗
const SHEET = [6, 5, 4, 3];


export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, Rg = new Rng(o.seed);
  const segs = dirArcs(Rg, R, 2, 0);   // 每招 1–2 道（组长 B 11-04）
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const ea = 1 - smooth(0.08, 0.35, t);
      if (ea <= 0) return;
      for (const sg of segs) {
        if (deco) p.glow(Math.cos(sg.c) * sg.r, Math.sin(sg.c) * sg.r * SY, 6, C[4], 0.18 * ea);
        if (!core) continue;
        for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.45 / sg.r) {
          const e = 1 - Math.abs(an - sg.c) / sg.half, n = noise(an * 3 + sg.s, o.seed);
          for (let k = 0; k < 4; k++) p.dot(Math.cos(an) * (sg.r - k * 1.6), Math.sin(an) * (sg.r - k * 1.6) * SY, t < 0.05 && k < 2 ? C[6] : C[SHEET[k] - (n > 0.6 ? 0 : 1) < 2 ? 2 : SHEET[k] - (n > 0.6 ? 0 : 1)], ea * smooth(0, 0.3, e) > 0.35 ? 1 : 0);   // §0：4 像素厚的光片
        }
        // §0 不碎：弧上的小十字去掉
      }
      if (core && t < 0.2) for (let y = 0; y <= 22; y += 1) p.blend(0, -y, C[5], (1 - t / 0.2) * (1 - y / 26));
    },
  };
}
