// 德克萨斯剑雨的地面标记（docs/229 §7，替 fx_texas_rain_mark）：@2x 24×12，锚 = 帧中心（游戏里随剑的 scale 0.93 / 0.8 放，每 1x 像素 1.6–1.9 世界像素）；帧语义同原条：
// 第 0–2 帧预兆（落点上一圈不规整的琥珀色细点在收拢、逐帧变亮），第 3–5 帧焦痕（插地后一摊外缘破碎的暗琥珀焦痕，逐帧变暗变碎）。地面透视 sy 0.5。
import { fit, clamp, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Texas rain mark",
  desc: "Floor mark for the sword rain: three omen frames of a ragged amber dotted ring closing in and brightening, then three frames of a broken scorch that darkens and breaks apart.",
  tags: ["floor", "mark", "rain", "sheet"],
  size: [24, 12],
  origin: [12, 6],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2a1606", "#5c3208", "#a8620e", "#f0a020", "#ffe053", "#fff6c4", "#ffffff"],
    seed: 5,
  },
};

const SY = 0.5;
export function draw(p, t, o) {
  if (t >= meta.duration - 1e-6) return;
  const C = fit(o.palette, 7), f = Math.floor(t * meta.fps + 1e-6), sd = o.seed;
  if (f <= 2) {
    const R = 10 - f * 2;
    for (let a = 0; a < TAU; a += 0.1) {   // 几段长短不一的虚弧，断口随噪声（不等距）
      if (noise(a * 2.3 + f * 0.7, sd) < 0.05) continue;
      const r = R * (1 + 0.1 * noise(a * 5, sd + 1));
      p.px(Math.cos(a) * r, Math.sin(a) * r * SY, C[clamp(3 + f + (Math.sin(a) > 0 ? 0 : -1), 2, 5)]);
    }
    p.px(0, 0, C[3 + f]);
    return;
  }
  const u = (f - 3) / 2;   // 焦痕
  for (let y = -5.5; y <= 5.5; y++)
    for (let x = -11.5; x <= 11.5; x++) {
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY), edge = 7 * (1 + 0.28 * noise(a * 2.6, sd + 2) + 0.12 * noise(a * 7, sd + 3));
      if (r > edge) continue;
      const q = r / edge, n = 0.5 + 0.5 * noise(x * 0.9 + noise(y * 1.2, sd + 6) * 2, sd + 7);
      if (n < 0.25 + u * 0.4 + q * 0.2) continue;
      const ci = clamp(Math.round(3 - q * 2 - u * 1.5 + (q < 0.2 && f === 3 ? 2 : 0)), 0, 5);
      p.blend(x, y, C[ci], (0.85 - u * 0.4) * (1 - q * 0.4));
    }
}
