// 流明 S3「灯火不灭」灯塔光圈（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 光圈中心（队长脚底），无缝循环。
// 判定：光圈半径 r = s3_r（世界像素；1x = s3_r / 2），区内回复 + 免疫。照原作 lumen_skill_03_buff_02（地面流光 + 上飘光点 + 细雨）。
// 地面：一片没有硬边的淡光（装饰层）；边：判定半径上 5 段断开的涟漪弧，绕圈慢慢转、亮度沿圈起伏（核心层，§11.2 #4 范围回复画在判定半径上）；
// 区内零星落几丝细雨、落点亮一下（核心层），光点慢慢往上飘（装饰层）。不画整圈线、不外扩。只有 E2。只用钢蓝 7 阶。
import { Rng, fit, clamp, smooth, noise, TAU } from "../../core/index.js";

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
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", r: 110, seed: 4 },
};

const SY = 0.5;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, D = meta.duration, ph = (t % D) / D, Rg = new Rng(o.seed);
  // 5 段弧：一圈转 1/5 正好循环（段间距相同的地方用 noise 改长短和亮度，看不出等距）
  const segs = [];
  for (let i = 0; i < 5; i++) segs.push({ c: (i + Rg.range(-0.32, 0.32)) * TAU / 5, half: Rg.range(0.18, 0.4), s: Rg.next() * 10 });
  if (deco) {
    for (let y = -R * SY; y <= R * SY; y += 1)
      for (let x = -R; x <= R; x += 1) {
        const q = Math.hypot(x / R, y / (R * SY)) * (0.9 + 0.2 * noise(Math.atan2(y, x) * 1.5, o.seed));
        if (q < 1) p.blend(x, y, C[3], 0.09 * (1 - q) * (1 - q));
      }
    // 上飘光点：每颗有自己的相位，循环无缝
    for (let i = 0; i < 14; i++) {
      const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R * 0.9, u = (ph + Rg.next()) % 1;
      p.dot(Math.cos(a) * r, Math.sin(a) * r * SY - u * 40, u < 0.7 ? C[5] : C[4], Math.sin(u * Math.PI) * 0.9);
    }
  }
  if (!core) return;
  const rot = 0;   // 不转（循环接缝不跳）；亮度沿圈随相位流动
  for (const sg of segs)
    for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.4 / R) {
      const e = 1 - Math.abs(an - sg.c) / sg.half, a = an + rot, n = 0.6 * noise(a * 2.6 + sg.s, o.seed + 3) + 0.4 * Math.max(0, Math.cos(an * 2 - ph * TAU));
      p.dot(Math.cos(a) * R, Math.sin(a) * R * SY, n > 0.65 ? C[6] : n > 0.35 ? C[5] : C[4], smooth(0, 0.35, e) * (n > 0.2 ? 0.95 : 0.55));
    }
  // 细雨：8 丝，各自在循环里落一次，落点亮一个扁小弧
  for (let i = 0; i < 8; i++) {
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * R * 0.85, x = Math.cos(a) * r, y = Math.sin(a) * r * SY, t0 = Rg.next(), L = Rg.range(8, 14);
    const u = ((ph - t0 + 1) % 1) / 0.09;
    if (u < 1) {
      const yh = y - 70 * (1 - u), xh = x - 0.22 * 70 * (1 - u);
      for (let s = 0; s <= L; s += 0.5) p.dot(xh - 0.22 * s, yh - s, s < 1.5 ? C[6] : C[5], s < L * 0.5 ? 0.9 : 1.2 - s / L);
    } else if (u < 2.2) {
      const k = 1 - (u - 1) / 1.2;
      for (let an = 0.3; an < Math.PI - 0.3; an += 0.35) p.dot(x + Math.cos(an) * 3, y + Math.sin(an) * 1.5, C[5], k);
    }
  }
}
