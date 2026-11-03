// 流明普攻「荧光」光弹（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 弹头，正右为飞行方向，循环 4 帧。
// 照原作 lumen_attack_01_trail（水蓝彗星：亮头 + 往后变细的水流尾 + 沿途甩下的小水泡）：
// 白芯雨滴形弹头（前圆后尖）+ 一条 1–2 像素的钢蓝细尾，尾上一处亮斑往后跑；不画圆形光球。
// 分档（docs/242 §10，docs/91 流明）：E0 短尾；E1 弹头前缘多一颗一闪一闪的四芒小星（折光）；E2 尾巴更长，尾端掉下两颗水珠（长明）。
// 分层（docs/242 §8）：core = 弹头、细尾、四芒星、水珠；deco = 弹头光晕、尾部淡雾。颜色只用钢蓝 7 阶。
import { fit, clamp, TAU } from "../../core/index.js";

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
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", elite: 2 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), E = o.elite, ph = (t / meta.duration) % 1;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const L = E === 0 ? 16 : E === 1 ? 20 : 27;
  if (deco) {
    p.glow(0, 0, 6, C[4], 0.32);
    p.glowLine(-2, 0, -L * 0.8, 0, 3, C[3], 0.16);
  }
  if (!core) return;
  // 细尾：前 2 像素宽、往后收成 1 像素，颜色逐级变暗；亮斑沿尾往后跑（循环无缝）
  for (let d = 2; d <= L; d += 0.5) {
    const v = d / L, run = Math.max(0, 1 - Math.abs(((v - ph + 1) % 1) - 0.5) * 7);
    const ci = clamp(Math.round(5.4 - v * 3.2 + run * 1.4), 2, 6);
    p.dot(-d, 0, C[ci], v > 0.8 ? (1 - v) * 5 : 1);
    if (v < 0.35) p.dot(-d, v < 0.15 ? -1 : 1, C[Math.max(2, ci - 1)], 1 - v * 2.5);
  }
  // 弹头：雨滴形，前圆后尖；芯白、外圈钢蓝高光
  for (let x = -4; x <= 2; x += 0.5)
    for (let y = -2; y <= 2; y += 0.5) {
      const hw = x >= 0 ? Math.sqrt(Math.max(0, 1 - (x / 2) ** 2)) * 1.8 : 1.8 * (1 + x / 4.5);   // 前圆后尖
      const e = Math.abs(y) / Math.max(hw, 0.01);
      if (e > 1 || hw <= 0.2) continue;
      p.px(x, y, e < 0.45 && x > -2.5 ? C[6] : e < 0.8 ? C[5] : C[4]);
    }
  // E1：前缘一颗四芒小星，按帧一闪一闪（折光）
  if (E >= 1) {
    const k = [3, 2, 1, 2][Math.floor(ph * 4) % 4];
    for (let d = 1; d <= k; d++) { p.px(3 + d, 0, d < k ? C[6] : C[5]); p.px(3, -d, C[5]); p.px(3, d, C[5]); }
    p.px(3, 0, C[6]);
  }
  // E2：尾端掉下两颗水珠（随帧往后、往下漂）
  if (E === 2)
    for (const s of [0.55, 0.85]) {
      const u = (ph + s) % 1;
      p.px(-L * (0.45 + 0.4 * u), 2 + u * 3, u < 0.5 ? C[5] : C[4]);
    }
}
