// 铃兰连携的小狐火（静帧 3 种，竖直，@2x 28×30，原点 = 中心；目标高 26 世界像素，代码按运动方向左右翻）：
// 狐首形的一团金色火：两只长短不一的耳尖、往一侧甩的火尾，芯一点白。seed 出三种。
import { Rng, fit, clamp, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran link fox",
  desc: "A small fox-head foxfire for Suzuran's link: a golden flame with two uneven ear points and a flicked tail, white at the very core.",
  tags: ["holy", "fire", "foxfire", "still"],
  size: [28, 30],
  origin: [14, 16],
  duration: 0.05,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 1 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed * 5 + 1), S = o.seed;
  const ea = Rg.range(5, 8), eb = Rg.range(3.5, 6.5), tail = Rg.range(6, 10);
  p.shade(-13, -14, 13, 14, (x, y) => {
    const head = Math.hypot(x * 1.1, (y - 1) * 1.25) < 7.5 * (1 + 0.1 * noise(Math.atan2(y, x) * 2 + S, S));
    const earL = y < -3 && y > -4 - ea && Math.abs(x + 3.5 + (y + 3) * 0.15) < (1 - (-3 - y) / ea) * 2.2;
    const earR = y < -3 && y > -4 - eb && Math.abs(x - 3.5 - (y + 3) * 0.2) < (1 - (-3 - y) / eb) * 2;
    const tl = x < -4 && x > -5 - tail && Math.abs(y - 4 + (x + 5) * 0.35) < (1 + (x + 5 + tail) / tail) * 1.6 * (0.6 + 0.4 * noise(x * 0.5, S + 2));
    if (!(head || earL || earR || tl)) return;
    const d = Math.hypot(x * 0.9, y - 1) / 8;
    p.px(x, y, C[clamp(Math.round(5 - d * 2.6 - (tl ? 1 : 0)), 2, 5)]);
  });
  p.px(1, 1, C[6]);
  p.glow(0, 0, 12, C[4], 0.25);
}
