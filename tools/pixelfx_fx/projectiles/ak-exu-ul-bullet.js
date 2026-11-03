// 能天使曳光弹（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 弹头，正右为飞行方向，循环 4 帧（拖尾闪烁）。
// 白热弹头（亮芯 + 色阶外圈）→ 一条往后变细、逐级冷却的曳光尾，尾上有一两处亮斑跑动；光晕不烤满（k 0.45）。
import { fit, clamp, cycle, TAU } from "../../core/index.js";

export const meta = {
  name: "Exusiai tracer unleashed",
  desc: "A bright rifle tracer: a white-hot slug with a coloured rim and a long tapering trail that flickers as hot spots run down it.",
  tags: ["projectile", "bullet", "tracer", "loop"],
  size: [56, 20],
  origin: [44, 10],
  duration: 0.2,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: ["#3a0a10", "#7c1622", "#c4283a", "#f24d4d", "#ff9a8a", "#ffd8cc", "#ffffff"], length: 36, seed: 2 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), L = o.length, ph = (t / meta.duration) % 1;
  // 曳光尾：越往后越细、越暗；尾上两处亮斑沿尾巴往后跑（循环无缝）
  for (let d = 0; d <= L; d += 0.5) {
    const v = d / L, w = 2.6 * (1 - v) + 0.4, run = Math.max(0, 1 - Math.abs(((v - ph + 1) % 1) - 0.5) * 8), run2 = Math.max(0, 1 - Math.abs(((v - ph + 1.5) % 1) - 0.5) * 10);
    const heat = 1 - v * 1.15 + 0.5 * run + 0.35 * run2;
    for (let s = -w; s <= w; s += 0.5) {
      const q = Math.abs(s) / w, ci = clamp(Math.round(heat * 5.2 - q * 2 + 0.6), 1, 6);
      if (ci <= 1 && q > 0.6) continue;
      p.dot(-d, s, C[ci], v > 0.85 ? 1.6 - v : 1);
    }
  }
  // 弹头：白芯 + 一圈色阶外缘（前尖后钝）
  for (let x = -5; x <= 3; x += 0.5)
    for (let y = -3; y <= 3; y += 0.5) {
      const e = (x > 0 ? (x / 3) ** 2 : (x / 5) ** 2) + (y / 2.6) ** 2;
      if (e > 1) continue;
      p.px(x, y, e < 0.35 ? C[6] : e < 0.7 ? C[5] : C[4]);
    }
  p.glow(0, 0, 9, C[4], 0.45);
  p.glow(-L * 0.4, 0, 12, C[3], 0.2);
}
