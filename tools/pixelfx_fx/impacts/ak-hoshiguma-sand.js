// 星熊脚下扬尘（docs/229，替 fx_hoshiguma_sand 的虚线椭圆 + 棋盘格）：@2x 96×48，4 帧 @8，原点 = 帧中心（地面，JSON fit 不变）。
// 地面透视下一摊不规整的尘：几团半透明尘雾（真半透明、上亮下暗）+ 贴地的碎石点，团的位置与大小不等，逐帧扩散变薄。
import { fit, clamp, noise } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma dust",
  desc: "Ground dust under the shield: uneven translucent dust puffs lit on top and scattered grit on a perspective floor, spreading and thinning over four frames.",
  tags: ["floor", "dust", "one-shot"],
  size: [96, 48],
  origin: [48, 24],
  duration: 0.5,
  loop: false,
  fps: 8,
  bg: "dark",
  options: { palette: ["#1c1812", "#3a3226", "#5e5240", "#857559", "#ab9a78", "#d4c6a4", "#f2ead6"], seed: 3 },
};

const PUFFS = [[-21, 3, 8], [-9, -5, 9], [5, 4, 11], [17, -3, 7], [26, 5, 5], [-28, -1, 4]];
export function draw(p, t, o) {
  if (t >= meta.duration - 1e-6) return;
  const C = fit(o.palette, 7), f = Math.floor(t * meta.fps + 1e-6), g = 1 + f * 0.12, a = [0.75, 0.6, 0.4, 0.2][f];
  for (const [cx, cy, r] of PUFFS) {
    const R = r * g;
    for (let y = -R * 0.55; y <= R * 0.55; y++)
      for (let x = -R; x <= R; x++) {
        const d = Math.hypot(x / R, y / (R * 0.55));
        if (d > 1 + 0.15 * noise(x * 0.4 + cx, o.seed)) continue;
        const ci = clamp(Math.round(4 - d * 2 - (y > 0 ? 1 : 0) - f * 0.5), 1, 5);
        p.blend(cx * g + x, cy * g * 0.8 + y, C[ci], a * (1 - d * 0.6));
      }
  }
  for (let i = 0; i < 16; i++) {   // 碎石点：位置不等距
    const x = noise(i * 1.31, o.seed + 5) * 32 * g, y = noise(i * 2.17, o.seed + 6) * 12 * g;
    p.blend(x, y, C[i % 3 === 0 ? 5 : 2], 1 - f * 0.25);
  }
}
