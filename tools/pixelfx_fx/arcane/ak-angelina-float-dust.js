// 安洁莉娜失重井里浮空敌人脚下的尘（循环 0.6 s @10，@2x，原点 = 敌人脚下，透视 sy 0.5）：
// 几粒碎屑和尘点在脚下高低不一地慢慢往上飘、一圈若隐若现的淡影；位置和速度都不等距。
import { fit, cycle, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina float dust",
  desc: "Dust and specks drifting up unevenly beneath an enemy lifted by Angelina's gravity well, over a faint shadow on the floor.",
  tags: ["arcane", "gravity", "dust", "floor", "loop"],
  size: [40, 32],
  origin: [20, 22],
  duration: 0.6,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.angelina, seed: 4 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7);
  p.shade(-10, -4, 10, 4, (x, y) => { const d = Math.hypot(x / 9, y / 3.5); if (d <= 1) p.blend(x, y, C[0], 0.4 * (1 - d * 0.6)); });   // 真半透明，不用抖动
  cycle(t, meta.duration, 7, o.seed, (g) => g.range(0.35, 0.6), (age, L, g) => {
    const a = g.range(0, TAU), d = g.range(2, 10), u = age / L;
    const x = Math.cos(a) * d, y = Math.sin(a) * d * 0.5 - u * g.range(8, 16);
    p.blend(x, y, C[g.chance(0.4) ? 4 : 3], 0.75 * (1 - u));
    if (g.chance(0.35)) p.blend(x, y - 1, C[2], 0.5 * (1 - u));
  });
}
