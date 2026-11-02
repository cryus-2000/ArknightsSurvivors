// 艾雅法拉「熔蚀」敌人脚下裂纹（docs/229，地面层，@2x，原点 = 脚下中心，透视 sy 0.45；7 帧 @10）：
// 游戏按 7 帧播：0–3 帧裂开（第 0 帧芯最亮）、第 3 帧停住到状态快结束、4–6 帧冷却溶解。
// 三四条参差的裂缝从中心往外，角度和长度都随机、各带一个分叉（不等距放射），缝里透出熔岩、边上暗红。
import { Rng, fit, clamp, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla melt crack",
  desc: "Molten cracks open under an enemy: a few jagged forked fissures glow with lava, hold, then cool and crumble away.",
  tags: ["fire", "lava", "crack", "floor", "status"],
  size: [56, 28],
  origin: [28, 14],
  duration: 0.7,
  loop: false,
  fps: 10,
  bg: "dark",
  options: { palette: OP.eyjafjalla, seed: 3 },
};

const SY = 0.45, L = 24;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const cracks = [];
  let a = Rg.range(0, TAU);
  for (let i = 0, n = Rg.int(3, 4); i < n; i++) {
    a += Rg.range(1.1, 2.3);
    const pts = [[0, 0]], len = L * Rg.range(0.6, 1), seg = Rg.int(4, 6);
    let x = 0, y = 0, d = a;
    for (let k = 1; k <= seg; k++) { d += Rg.range(-0.5, 0.5); x += Math.cos(d) * len / seg; y += Math.sin(d) * len / seg; pts.push([x, y]); }
    const fk = Rg.int(2, seg - 1), fd = d + Rg.sign() * Rg.range(0.5, 1.1), fl = len * Rg.range(0.25, 0.45);
    cracks.push({ pts, fork: [pts[fk], [pts[fk][0] + Math.cos(fd) * fl, pts[fk][1] + Math.sin(fd) * fl]] });
  }
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const f = Math.floor(t * 10 + 1e-6);
      if (f > 6) return;
      const open = f <= 3 ? (f + 1) / 4 : 1, cool = f <= 3 ? 0 : (f - 3) / 3;
      const line = (x0, y0, x1, y1, hot, k) => {
        const n = Math.ceil(Math.hypot(x1 - x0, y1 - y0) * 2);
        for (let i = 0; i <= n; i++) {
          const u = i / n, x = x0 + (x1 - x0) * u, y = (y0 + (y1 - y0) * u) * SY;
          if (cool > 0 && noise(x * 0.4 + y, o.seed + 7) * 0.5 + 0.5 < cool * 0.9) continue;   // 冷却时按噪声碎掉
          p.px(x, y, C[clamp(Math.round(hot - cool * 3), 1, 6)]);
          if (k > 0.5) p.blend(x, y + 1, C[1], 0.6 * (1 - cool));
        }
      };
      for (const c of cracks) {
        const m = Math.max(1, Math.round((c.pts.length - 1) * open));
        for (let i = 0; i < m; i++) line(c.pts[i][0], c.pts[i][1], c.pts[i + 1][0], c.pts[i + 1][1], f === 0 ? 5.6 - i * 0.6 : 4.6 - i * 0.4, 1 - i / m);
        if (open >= 1) line(c.fork[0][0], c.fork[0][1], c.fork[1][0], c.fork[1][1], 3.6, 0);
      }
      if (f === 0) p.px(0, 0, C[6]);
    },
  };
}
