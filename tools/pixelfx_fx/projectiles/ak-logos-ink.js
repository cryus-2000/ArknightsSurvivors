// 逻各斯普攻墨弹（docs/231 弹体，循环 4 帧 @16，@2x 64×24，朝右，原点 = 弹心）：
// 一滴深墨，外缘一圈紫亮、前端一像素高光；身后两三缕长短不一、摆动相位不同的墨丝，末端散成墨点。curl 控制墨丝摆幅（_a / _b 两版）。
import { fit, clamp, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos ink bolt",
  desc: "Logos's ink bolt: a drop of deep ink with a violet rim and a glint at the tip, trailing a few uneven wavering ink strands that break into drops.",
  tags: ["projectile", "ink", "arcane", "loop"],
  size: [64, 24],
  origin: [44, 12],
  duration: 0.25,
  loop: true,
  fps: 16,
  bg: "dark",
  options: { palette: OP.logos, curl: 1, seed: 1 },
};

const STR = [[0, 1, 1.6, 0], [-2, 0.7, 1, 0.3], [2.2, 0.5, 0.9, 0.65]];

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration, H = 5, L = 34;
  for (const [dy, lk, w0, p0] of STR) {
    const l = L * lk;
    for (let s = 0; s <= l; s += 0.5) {
      const v = s / l, y = dy * (1 + v * 0.6) + Math.sin(v * 6 * o.curl + (ph + p0) * TAU) * (0.5 + v * 2 * o.curl);
      if (v > 0.65 && noise(s * 0.5 + ph * 8, o.seed + p0 * 10) > 0.15) continue;
      const w = w0 * (1 - v);
      for (let q = -w; q <= w; q += 1) p.px(-H * 0.5 - s, y + q, C[v < 0.3 ? 2 : v < 0.6 ? 1 : 0]);
    }
  }
  p.shade(-H - 1, -H - 1, H + 2, H + 1, (x, y) => {
    const a = Math.atan2(y, x), d = Math.hypot(x * 0.85, y) / (H * (1 + 0.12 * noise(a * 2.1 + ph * TAU, o.seed)));
    if (d > 1) return;
    p.px(x, y, C[d > 0.72 ? 4 : d > 0.5 ? 1 : 0]);
  });
  p.px(H - 1, -1, C[6]);
  p.glow(0, 0, 9, C[3], 0.2);
}
