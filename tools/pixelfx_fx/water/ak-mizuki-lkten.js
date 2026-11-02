// 水月连携「脚下小触手」（link_fx_b.gd MZ_TEN，替换 fx_lk_mz_ten1–3）：@2x 单帧、保留画布，代码以画布底边中点为锚、按 34–44 世界像素高缩放并做长出 / 淡出。
// 一根半透明的水母触手从地面暗水里钻出，根粗梢细、左上受光，梢头卷成不等大的钩；variant 1–3 换弯向、卷度和高度，不复用同一形。
import { Rng, fit, clamp, noise } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Mizuki link tentacle",
  desc: "A small translucent jellyfish tentacle rising out of a dark pool, thick at the root, curling into a hook at the tip; three variants.",
  tags: ["water", "tentacle", "still", "one-shot"],
  size: [44, 48],
  origin: [22, 45],
  duration: 0.05,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.mizuki],
    variant: 1,
  },
};

export function draw(p, t, o) {
  if (t >= 0.05) return;
  const C = fit(o.palette, 8), v = o.variant;
  const H = [38, 42, 34][(v - 1) % 3], lean = [0.12, -0.18, 0.22][(v - 1) % 3], curl = [1.4, 1.0, 1.8][(v - 1) % 3];
  // 地面暗水
  for (let y = -2; y <= 2; y++) for (let x = -9; x <= 9; x++) {
    const r = Math.hypot(x / 9, y / 2.6) / (1 + 0.2 * noise(x * 0.5, v));
    if (r <= 1) p.blend(x, y, C[r > 0.75 ? 3 : 1], r > 0.75 ? 0.8 : 0.65);
  }
  const seen = new Set();
  const N = H * 2;
  let x = 0, y = 0, a = -Math.PI / 2 + lean;
  for (let i = 0; i <= N; i++) {
    const s = i / N;
    a += (s > 0.55 ? curl * 3.4 / N : 0) * Math.sign(lean) + 0.03 * noise(s * 6, v * 9);   // 梢头往倾斜那侧卷成钩
    x += Math.cos(a) * H / N; y += Math.sin(a) * H / N;
    const w = 3.6 * (1 - s * 0.85) + 0.5;
    for (let d = -w; d <= w; d += 0.5) {
      const q = Math.abs(d) / w, px = Math.round(x + d), py = Math.round(y), key = px * 1000 + py;
      if (seen.has(key)) continue;
      seen.add(key);
      const c = C[clamp(Math.round((q > 0.62 ? 6 : 4) + s * 1.2 - (d > 0 ? 1 : 0)), 2, 7)];   // 左上受光
      p.blend(px, py, c, q > 0.62 ? 0.95 : 0.65);
    }
  }
}
