// 安洁莉娜「失重井」井心浮球（循环 1.2 s @10，竖直件，画布 96×96、原点 (48,72) 同旧 well_front 的 anchor [24,36]）：
// 暗紫的小奇点外面一圈紫亮边，亮边上一段高光绕着走；几块碎石在不同半径、不同速度、不同倾角的轨道上转，转到后面时变暗（不等距、不同步）。
import { clamp, fit, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina gravity well core",
  desc: "The floating core of Angelina's gravity well: a dark violet singularity with a bright rim and a sliding highlight, debris chips orbiting at uneven radii and speeds.",
  tags: ["arcane", "gravity", "orb", "loop"],
  size: [96, 96],
  origin: [48, 72],
  duration: 1.2,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.angelina, seed: 7 },
};

const CY = -24;
// 碎石：轨道半径、倾角、每个循环转几圈（整数才无缝）、起角、大小
const DEBRIS = [
  { r: 15, tilt: 0.35, n: 1, a: 0.4, s: 1.6 },
  { r: 22, tilt: 0.55, n: 1, a: 2.6, s: 1.2 },
  { r: 19, tilt: 0.25, n: 2, a: 4.1, s: 1.0 },
  { r: 27, tilt: 0.45, n: 1, a: 5.3, s: 1.4 },
];

function chip(p, C, d, ph, back) {
  const a = d.a + TAU * d.n * ph, z = Math.sin(a);
  if ((z < 0) !== back) return;
  const x = Math.cos(a) * d.r, y = CY + z * d.r * d.tilt;
  const c = C[back ? 2 : 4];
  p.px(x, y, c);
  if (d.s > 1.1) p.px(x + 1, y, C[back ? 1 : 3]);
  if (d.s > 1.3) p.px(x, y - 1, C[back ? 1 : 5]);
}

export function drawBack(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration;
  for (const d of DEBRIS) chip(p, C, d, ph, true);
}

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration;
  p.disc(0, CY, 9, (d) => C[d < 0.55 ? 0 : 1], (d) => (d < 0.8 ? 0.95 : 0.6));
  // 亮边：一段高光绕着走
  for (let a = 0; a < TAU; a += 0.08) {
    const hl = Math.cos(a - TAU * ph) > 0.55;
    p.px(Math.cos(a) * 9, CY + Math.sin(a) * 9, C[hl ? 5 : 3]);
  }
  p.glow(0, CY, 14, C[3], 0.25);
  for (const d of DEBRIS) chip(p, C, d, ph, false);
}
