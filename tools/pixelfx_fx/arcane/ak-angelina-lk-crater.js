// 安洁莉娜连携落定的坑（静帧，俯视圆，代码压成 sy 0.62；@2x 168×168，原点 = 中心，目标半径 0.55 × 150 ≈ 82 世界像素）：
// 坑底暗紫，坑沿一圈翻起的碎石（大小、间距随机），几道长短不一的裂纹往外；只一圈坑沿，不画同心圈。
import { Rng, fit, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina link crater",
  desc: "The crater from Angelina's link: a dark violet pit inside one rim of upturned rubble of random size and spacing, with a few uneven cracks running out.",
  tags: ["arcane", "gravity", "crater", "floor", "still"],
  size: [168, 168],
  origin: [84, 84],
  duration: 0.05,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.angelina, seed: 4 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), S = o.seed, R = 66;
  p.shade(-R - 2, -R - 2, R + 2, R + 2, (x, y) => {
    const a = Math.atan2(y, x), d = Math.hypot(x, y) / (R * (1 + 0.08 * noise(a * 3.3, S)));
    if (d > 1) return;
    p.blend(x, y, C[d < 0.6 ? 0 : 1], d < 0.85 ? 0.7 : 0.9);
  });
  for (let a = Rg.range(0, 0.3); a < TAU; a += Rg.range(0.12, 0.3)) {
    const r = R * Rg.range(0.94, 1.08), s = Rg.range(1.5, 4), x = Math.cos(a) * r, y = Math.sin(a) * r;
    p.disc(x, y, s, (d) => C[d < 0.5 ? 3 : 2], () => 1);
    if (Rg.chance(0.4)) p.px(x - 1, y - 1, C[4]);
  }
  for (let i = 0, a = Rg.range(0, TAU); i < 5; i++, a += Rg.range(0.8, 1.7)) {
    let x = Math.cos(a) * R, y = Math.sin(a) * R, d = a;
    const L = Rg.range(8, 16);
    for (let s = 0; s < L; s += 0.5) {
      d += Rg.range(-0.12, 0.12); x += Math.cos(d) * 0.5; y += Math.sin(d) * 0.5;
      p.px(x, y, C[s < L * 0.5 ? 2 : 1]);
    }
  }
}
