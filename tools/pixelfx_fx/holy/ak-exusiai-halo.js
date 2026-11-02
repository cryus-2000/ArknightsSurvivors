// 能天使精二「天使的祝福」（D 组）：@2x 密度。mode 0 = 队友头顶的光环循环（8 帧 @10，原点 = 环心，替换 fx_exusiai_halo）；
// mode 1 = 队友出手时一闪（替换 fx_exusiai_blessed_flash）。只有一道倾斜的金环（她的光环），一段亮光绕环走，环上零星闪点间距随机；不画同心圈。
import { Rng, fit, clamp, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Exusiai halo",
  desc: "Exusiai's blessing: mode 0 is a single tilted gold halo with a bright run circling it and a few unevenly spaced glints; mode 1 is the quick flash when an ally attacks.",
  tags: ["holy", "halo", "buff", "loop"],
  size: [64, 48],
  origin: [32, 24],
  duration: 0.8,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: ["#2a1a06", "#7a4c0e", "#d89a2a", "#ffd76a", "#fff3cc", "#ffffff"], mode: 0, seed: 3 },
};

const RX = 24, RY = 6;

export function draw(p, t, o) {
  const C = fit(o.palette, 6), flash = +o.mode === 1;
  if (flash) {
    if (t >= 0.2) return;
    const k = 1 - t / 0.2, s = t < 0.05 ? 1 : k;
    // 环整圈一亮 + 不对称四芒
    for (let a = 0; a < TAU; a += 0.04) p.px(Math.cos(a) * RX * (1 + 0.15 * (1 - k)), Math.sin(a) * RY - 6, C[t < 0.05 ? 5 : a > Math.PI ? 3 : 4]);
    for (const [dx, dy, l] of [[0, -1, 9], [0, 1, 4], [1, 0, 6], [-1, 0, 5]])
      for (let d = 0; d <= l * s; d++) p.px(dx * d, dy * d - 6, C[d < l * s * 0.4 ? 5 : 3]);
    p.glow(0, -6, 10, C[3], 0.3 * k);
    return;
  }
  const head = (t / 0.8) * TAU;
  for (let a = 0; a < TAU; a += 0.03) {
    const back = Math.sin(a) < 0;   // 远半圈暗
    let d = (a - head) % TAU; if (d < 0) d += TAU;
    const run = d > TAU - 1.1 ? 1 - (TAU - d) / 1.1 : 0;   // 绕环走的亮段（尾巴渐暗）
    const ci = clamp(Math.round((back ? 2 : 3) + run * 2.5), 1, 5);
    p.px(Math.cos(a) * RX, Math.sin(a) * RY, C[ci]);
    if (!back) p.px(Math.cos(a) * RX, Math.sin(a) * RY + 1, C[Math.max(1, ci - 2)]);
  }
  // 零星闪点：位置按噪声取、不等距，随时间轮换
  const R = new Rng(o.seed);
  for (let i = 0; i < 3; i++) {
    const a = R.range(0, TAU), ph = R.range(0, 1), on = ((t / 0.8 + ph) % 1) < 0.25;
    if (on) { const x = Math.cos(a) * RX, y = Math.sin(a) * RY; p.px(x, y - 1, C[5]); p.px(x, y - 2, C[4]); p.px(x - 1, y - 1, C[3]); p.px(x + 1, y - 1, C[3]); }
  }
  p.glow(0, 0, 12, C[3], 0.12 + 0.04 * noise(t * 8, o.seed));
}
