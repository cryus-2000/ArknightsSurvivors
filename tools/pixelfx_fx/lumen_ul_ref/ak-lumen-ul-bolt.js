// 流明普攻「荧光」光弹（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 弹头，正右为飞行方向，循环 4 帧。
// 照原作 lumen_attack_01_trail（水蓝彗星：亮头 + 往后变细的水流尾 + 沿途甩下的小水泡）：
// 白芯雨滴形弹头（前圆后尖）+ 一条 1–2 像素的钢蓝细尾，尾上一处亮斑往后跑；不画圆形光球。
// 分档见 draw 里的注释（组长 B 11-04 硬标准）。
// 分层（docs/242 §8）：core = 弹头、细尾、四芒星、水珠；deco = 弹头光晕、尾部淡雾。颜色只用钢蓝 7 阶。
import { fit, clamp, TAU } from "../../core/index.js";
import { OP, LAMP } from "../house.js";   // 色阶唯一来源（§11.1 第 12 条）

export const meta = {
  name: "Lumen bolt unleashed",
  desc: "A raindrop-shaped bolt: a white-hot head and a thin steel-blue tail with a bright spot running down it.",
  tags: ["projectile", "water", "loop"],
  size: [44, 16],
  origin: [36, 8],
  duration: 0.2,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", elite: 2 },
};

export function draw(p, t, o) {
  // 分档（组长 B 11-04 硬标准，加码只加在主形上）：E0 一颗雨滴弹 + 细尾；E1 体量 ×1.25、尾加厚一档；
  // E2 质变——一颗变三颗（主弹 + 两颗小弹贴着前后错开飞，像一串水珠），主弹 ×1.5、芯一点灯火橙（E2 专属点缀），尾更长
  const C = fit(o.palette, 7), E = o.elite, ph = (t / meta.duration) % 1, AC = fit([LAMP], 1)[0];
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const S = [1, 1.25, 1.5][E], L = [16, 20, 26][E];
  if (deco) {
    p.glow(0, 0, 6 * S, C[4], 0.32);
    p.glowLine(-2, 0, -L * 0.8, 0, 3 * S, C[3], 0.16);
  }
  if (!core) return;
  const head = (cx, cy, k, hot) => {   // 雨滴形，前圆后尖；芯白、外圈钢蓝高光
    for (let x = -4 * k; x <= 2 * k; x += 0.5)
      for (let y = -2 * k; y <= 2 * k; y += 0.5) {
        const hw = x >= 0 ? Math.sqrt(Math.max(0, 1 - (x / (2 * k)) ** 2)) * 1.8 * k : 1.8 * k * (1 + x / (4.5 * k));
        const e = Math.abs(y) / Math.max(hw, 0.01);
        if (e > 1 || hw <= 0.2) continue;
        p.px(cx + x, cy + y, hot && e < 0.3 && Math.abs(x) < 1 ? AC : e < 0.45 && x > -2.5 * k ? C[6] : e < 0.8 ? C[5] : C[4]);
      }
  };
  // 尾：E0 前 2 像素宽往后收，E1 / E2 加厚一档；亮斑沿尾往后跑（循环无缝）
  for (let d = 2; d <= L; d += 0.5) {
    const v = d / L, run = Math.max(0, 1 - Math.abs(((v - ph + 1) % 1) - 0.5) * 7);
    const ci = clamp(Math.round(5.4 - v * 3.2 + run * 1.4), 2, 6), w = (E === 0 ? 0.5 : 1) * (1 - v) + 0.5;
    for (let q = -w; q <= w; q += 0.5) p.dot(-d, q, Math.abs(q) < 0.6 ? C[ci] : C[Math.max(2, ci - 1)], v > 0.8 ? (1 - v) * 5 : 1);
  }
  head(0, 0, S, E === 2);
  if (E === 2) { head(-9, -3, 0.75, false); head(-15, 2, 0.6, false); }
}
