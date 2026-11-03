// 流明精二「灯塔光柱」（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 出光处，正右为光柱方向。
// 判定：直线长 len、宽 w（lumen.json attack.beam = pillar_len / pillar_w，世界像素；1x 像素 = /2）。
// 光柱整条一下子出现（不从中间往外扩），首帧白芯满宽，之后两边往中线收、从出光端往末端熄掉；出光处一颗四芒星（不是圆光）；
// 沿光柱零星挂几颗被照亮的水点。原作参照：S3 trail_02 的直线光（颜色按钢蓝色阶，不照搬原作暖橙）。
// 分层：core = 光柱、白芯、四芒星；deco = 光柱外的淡光、水点。只有 E2。
import { Rng, fit, clamp, smooth, noise } from "../../core/index.js";

export const meta = {
  name: "Lumen lighthouse pillar unleashed",
  desc: "A short straight beam of steel-blue light snaps on at full length, narrows to a thread and dies out from the lamp end.",
  tags: ["projectile", "beam", "one-shot"],
  size: [116, 24],
  origin: [6, 12],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", len: 100, w: 5, seed: 6 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), L = o.len, W = o.w / 2, Rg = new Rng(o.seed);
  const drops = [];
  for (let i = 0; i < 5; i++) drops.push({ x: Rg.range(0.15, 0.95) * L, y: Rg.range(-W - 3, W + 3), d: Rg.range(0, 0.08) });
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const narrow = smooth(0.04, 0.2, t), die = smooth(0.08, 0.28, t);
      if (deco) {
        if (t < 0.15) p.glowLine(0, 0, L, 0, W + 3, C[4], 0.22 * (1 - t / 0.15));
        for (const d of drops) {
          const a = t - d.d;
          if (a > 0 && a < 0.22) p.dot(d.x, d.y + a * 18, a < 0.08 ? C[6] : C[5], 1 - a / 0.22);
        }
      }
      if (!core) return;
      for (let x = 0; x <= L; x += 0.5) {
        const v = x / L;
        if (v < die) continue;   // 从出光端往末端熄
        const w = Math.max(0.5, W * (1 - 0.8 * narrow) * (0.92 + 0.16 * noise(v * 4 + t * 20, o.seed)) * (v > 0.92 ? (1 - v) / 0.08 : 1));
        for (let y = -w; y <= w; y += 0.5) {
          const q = Math.abs(y) / w;
          p.dot(x, y, t < 0.05 ? (q < 0.7 ? C[6] : C[5]) : q < 0.35 ? (t < 0.1 ? C[6] : C[5]) : C[4], 1);
        }
      }
      // 出光处四芒星
      if (t < 0.2) {
        const k = Math.round(6 * (1 - t / 0.2));
        for (let d = 1; d <= k; d++) { const c = d < k * 0.5 ? C[6] : C[5]; p.px(d, 0, c); p.px(-d, 0, c); p.px(0, d * 0.7, c); p.px(0, -d * 0.7, c); }
        p.px(0, 0, C[6]);
      }
    },
  };
}
