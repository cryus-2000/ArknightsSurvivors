// 流明 S3「灯火不灭」灯塔光圈（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 光圈中心（队长脚底），无缝循环。
// 判定：光圈半径 r = s3_r（世界像素；1x = s3_r / 2），区内回复 + 免疫。照原作 lumen_skill_03_buff_02（地面流光 + 上飘光点 + 细雨）。
// 地面：一片没有硬边的淡光（装饰层）；边：判定半径上 5 段断开的涟漪弧，绕圈慢慢转、亮度沿圈起伏（核心层，§11.2 #4 范围回复画在判定半径上）；
// 区内零星落几丝细雨、落点亮一下（核心层），光点慢慢往上飘（装饰层）。不画整圈线、不外扩。只有 E2。只用钢蓝 7 阶。
import { Rng, fit, clamp, smooth, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 第 12 条）

// 用户 11-04 否「绕身 / 脚下的匀称圆环」：不沿同一圆周均匀摆弧——身前 nF 段长短、半径都不等（最远一段贴判定半径），身后 nB 段短小的；
// 正右 = 朝向，朝左时游戏里翻转
const dirArcs = (Rg, R, nF, nB) => {
  const out = [];
  for (let i = 0; i < nF; i++) out.push({ c: Rg.range(-0.25, 0.25) + (i - (nF - 1) / 2) * Rg.range(0.5, 0.7), half: Rg.range(0.22, 0.5), r: R * (i === 0 ? 1 : Rg.range(0.62, 0.86)), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) });
  for (let i = 0; i < nB; i++) out.push({ c: Math.PI + Rg.range(-0.8, 0.8), half: Rg.range(0.12, 0.24), r: R * Rg.range(0.35, 0.55), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) });
  return out;
};

export const meta = {
  name: "Lumen lighthouse zone unleashed",
  desc: "A soft ground light with five broken ripple arcs turning slowly on its edge, a few threads of rain and rising motes inside.",
  tags: ["water", "zone", "loop"],
  size: [240, 180],
  origin: [120, 120],
  duration: 1.0,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", r: 110, seed: 4 },
};

const SY = 0.5;
// §0（组长 B 11-04）：弧是有厚度的水幕 / 光片——4 美术像素厚，外缘亮、往里一层层变暗
const SHEET = [6, 5, 4, 3];


export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, D = meta.duration, ph = (t % D) / D, Rg = new Rng(o.seed);
  // 5 段弧：一圈转 1/5 正好循环（段间距相同的地方用 noise 改长短和亮度，看不出等距）
  const segs = dirArcs(Rg, R, 1, 1);   // 每招 1–2 道（组长 B 11-04）
  if (deco) {
    for (let y = -R * SY; y <= R * SY; y += 1)
      for (let x = -R; x <= R; x += 1) {
        const q = Math.hypot(x / R, y / (R * SY)) * (0.9 + 0.2 * noise(Math.atan2(y, x) * 1.5, o.seed));
        if (q < 1) p.blend(x, y, C[3], 0.13 * (1 - q) * (1 - q));   // 灯塔照亮地面（§0）
      }
    // 上飘光点：每颗有自己的相位，循环无缝
    for (let i = 0; i < 7; i++) {
      const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R * 0.9, u = (ph + Rg.next()) % 1;
      p.dot(Math.cos(a) * r, Math.sin(a) * r * SY - u * 40, u < 0.7 ? C[5] : C[4], Math.sin(u * Math.PI) * 0.9);
    }
  }
  if (!core) return;
  const rot = 0;   // 不转（循环接缝不跳）；亮度沿圈随相位流动
  for (const sg of segs)
    for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.4 / sg.r) {
      const e = 1 - Math.abs(an - sg.c) / sg.half, a = an + rot, n = 0.6 * noise(a * 2.6 + sg.s, o.seed + 3) + 0.4 * Math.max(0, Math.cos(an * 2 - ph * TAU));
      for (let k = 0; k < 4; k++) p.px(Math.cos(a) * (sg.r - k * 1.6), Math.sin(a) * (sg.r - k * 1.6) * SY, C[Math.max(2, SHEET[k] - (n > 0.5 ? 0 : 1))]);   // §0：4 像素厚的光片，外亮内暗
    }
  // §0 不碎（用户 11-04）：圈里不再落细雨丝，只留地面光 + 弧 + 少量慢升的光点
}
