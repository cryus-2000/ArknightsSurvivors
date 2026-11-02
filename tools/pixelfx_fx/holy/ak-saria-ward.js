// 塞雷娅治疗星光 / 持续回复护盾（D 组）：@2x 密度，原点 = 帧中心。
// mode 0 = 头顶星光（替换 fx_holy_impact）：不对称的四芒琥珀星一闪，下面三粒光屑往下落。
// mode 1 = 钙质护盾（替换 fx_shield_amber）：几片六边形钙晶鳞片在身前合拢一亮再散开，片的大小、位置不规整。
import { Rng, fit, clamp, ease, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria ward",
  desc: "Saria's heal accents: mode 0 an uneven four-point amber star flash with motes falling; mode 1 a few hexagonal calcite scales that close in front of the ally, flash and drift apart.",
  tags: ["holy", "heal", "shield", "one-shot"],
  size: [64, 64],
  origin: [32, 32],
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#06142a", "#3a2a1c", OP.saria[1], OP.saria[2], OP.saria[3], "#ffe6c0", "#f4f8ff", "#ffffff"], mode: 0, seed: 7 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed), shield = +o.mode === 1;
  if (!shield) {
    if (t >= 0.35) return;
    const k = 1 - t / 0.35, s = ease.outBack(clamp(t / 0.06 + 0.3)) * k;
    for (const [dx, dy, l] of [[0, -1, 14], [0, 1, 9], [1, 0, 11], [-1, 0, 8]])
      for (let d = 0; d <= l * s; d++) p.px(dx * d, dy * d, C[t < 0.05 ? 7 : d < l * s * 0.3 ? 6 : d < l * s * 0.7 ? 5 : 4]);
    p.rect(-1, -1, 3, 3, C[t < 0.1 ? 7 : 5]);
    for (let i = 0; i < 3; i++) { const x = R.range(-6, 6), y = 4 + t * R.range(40, 70); if (t > 0.05) p.blend(x, y, C[5], k); }
    p.glow(0, 0, 12, C[5], 0.3 * k);
    return;
  }
  if (t >= 0.45) return;
  const close = ease.outQuart(clamp(t / 0.12)), open = clamp((t - 0.25) / 0.2);
  for (let i = 0; i < 6; i++) {
    const a = R.range(0, TAU), d0 = R.range(18, 26), d1 = R.range(4, 12), r = R.range(4, 7);
    const d = d0 + (d1 - d0) * close + 14 * open, x = Math.cos(a) * d, y = Math.sin(a) * d * 0.8;
    const rr = r * (1 - open * 0.8);
    if (rr < 1) continue;
    const pts = []; for (let j = 0; j < 6; j++) pts.push([x + Math.cos(j * TAU / 6 + a) * rr, y + Math.sin(j * TAU / 6 + a) * rr * 0.9]);
    const ci = t < 0.15 && close > 0.95 ? 7 : clamp(Math.round(5 - open * 3), 2, 6);
    p.poly(pts, C[Math.max(1, ci - 1)]);
    p.polyline([...pts, pts[0]], C[ci]);
  }
  if (t > 0.1 && t < 0.2) p.glow(0, 0, 16, C[5], 0.3);
}
