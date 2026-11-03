// 近战怪命中干员（怪物风格试点 11-04）：原点 = 干员身上命中点，攻击方向朝右下。
// 三道锯齿爪痕依次划出（间隔 0.035 秒），先亮后暗、从中间往两端收；外加几粒暗红碎屑顺划向甩出。元素 2 种，不画圆环。
import { Rng, fit, clamp, smooth, noise } from "../../core/index.js";

export const meta = {
  name: "Monster claw rake hit",
  desc: "Three jagged claw rakes tear across in quick succession, flare and fade from the ends in, with a few dark red flecks flung along.",
  tags: ["monster", "hit", "claw", "one-shot"],
  size: [48, 48],
  origin: [24, 24],
  duration: 0.36,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#2a0710", "#6a1226", "#c21f48", "#ff2667", "#ffd6e0"],
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 5), Rg = new Rng(o.seed);
  const rakes = [0, 1, 2].map((i) => ({ off: (i - 1) * 5 + Rg.range(-0.8, 0.8), L: Rg.range(15, 19) - Math.abs(i - 1) * 3, t0: i * 0.035, sd: o.seed + i * 7 }));
  const ang = Math.PI * 0.28 + Rg.range(-0.08, 0.08), ux = Math.cos(ang), uy = Math.sin(ang), nx = -uy, ny = ux;
  const flecks = [];
  for (let i = 0, n = Rg.int(4, 6); i < n; i++) flecks.push({ s: Rg.range(-6, 6), vx: ux * Rg.range(50, 90), vy: uy * Rg.range(50, 90) - 20, t0: Rg.range(0.03, 0.09), c: Rg.int(1, 2) });
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      for (const r of rakes) {
        const u = t - r.t0;
        if (u < 0) continue;
        const draw = clamp(u / 0.05), fade = smooth(0.1, 0.3, u);
        if (fade >= 1) continue;
        const half = r.L / 2 * (1 - fade);   // 从两端往中间收
        for (let s = -r.L / 2; s <= -r.L / 2 + r.L * draw; s += 0.5) {
          if (Math.abs(s) > half) continue;
          const j = 1.2 * noise(s * 0.6, r.sd), x = ux * s + nx * (r.off + j), y = uy * s + ny * (r.off + j);
          const ci = u < 0.04 ? 4 : clamp(Math.round(3.4 - fade * 3), 1, 3);
          p.px(x, y, C[ci]);
          if (Math.abs(s) < half * 0.5 && fade < 0.5) p.px(x + nx, y + ny, C[Math.max(1, ci - 1)]);
        }
      }
      for (const f of flecks) {
        const u = t - f.t0;
        if (u < 0 || u > 0.22) continue;
        p.px(nx * f.s + f.vx * u, ny * f.s + f.vy * u + 200 * u * u, C[f.c]);
      }
    },
  };
}
