// 艾雅法拉连携：高抛的熔岩块（静帧 2 种，游戏按 f 挑一种、代码转着画；@2x 96×96，原点 = 中心，目标宽 2.2 × 42 ≈ 92 世界像素）。
// 不规整的岩块：暗色熔岩壳一块块，壳缝里透出亮熔岩（缝是噪声零线，不等距），受光一侧提亮。
import { fit, clamp, noise, noise2, hex } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla link lava rock",
  desc: "A thrown lava rock for Eyjafjalla's link: an irregular chunk of dark crust plates split by glowing molten seams, lit on one side.",
  tags: ["fire", "lava", "rock", "still"],
  size: [96, 96],
  origin: [48, 48],
  duration: 0.1,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.eyjafjalla, seed: 2 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), K = ["#170d0b", "#2a1611", "#43200f", "#592d12"].map(hex), v = Math.floor(t * 20 + 1e-6), S = o.seed + v * 17, R = v ? 36 : 42;
  p.shade(-46, -46, 46, 46, (x, y) => {
    const a = Math.atan2(y, x), d = Math.hypot(x, y * (v ? 1.15 : 0.95)) / (R * (1 + 0.16 * noise(a * 1.9, S) + 0.08 * noise(a * 4.7, S + 1)));
    if (d > 1) return;
    const n = noise2(x * 0.09, y * 0.09, S + 3) + 0.3 * noise2(x * 0.23, y * 0.23, S + 4);
    const lit = (-x - y) / (R * 1.4);
    if (Math.abs(n) < 0.07 + 0.05 * (1 - d)) return p.px(x, y, C[clamp(Math.round(4.6 - d * 1.2), 3, 5)]);
    p.px(x, y, K[clamp(Math.round(0.8 + lit * 1.6 + (d > 0.9 ? 0.6 : 0)), 0, 3)]);   // 岩壳是不发光的暗暖褐（docs/229 §2.2：碎石不用发光色阶；最亮一阶 = 本人色阶最暗阶）
  });
  p.px(v ? -6 : 4, v ? 3 : -2, C[6]);
}
