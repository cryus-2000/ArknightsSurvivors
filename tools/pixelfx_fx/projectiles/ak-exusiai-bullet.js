// 能天使普攻弹体（docs/231 普攻试点）：@2x 密度，画布 32×12 与旧弹体相同，原点 = 帧中心，正右为飞行方向。
// 旧弹体是一根实心红条，射速高时首尾相接连成光束（docs/228 §7.3）；这里弹头亮、弹尾断成长短不一的几截。
import { clamp, fit } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Exusiai bullet",
  desc: "A tiny tracer round: a white-hot slug with a red jacket and a short broken tail of red dashes that flickers between two frames.",
  tags: ["projectile", "bullet", "tracer", "loop"],
  size: [32, 12],
  origin: [16, 6],
  duration: 0.1,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.exusiai, seed: 1 },
};

// 两帧的弹尾断口位置不同：[起点, 终点, 色阶]，x 向左为负
const TAILS = [
  [[0, 3, 2], [-5, -2, 2], [-9, -8, 1], [-12, -12, 1]],
  [[1, 3, 2], [-3, -1, 2], [-7, -6, 1], [-11, -10, 0]],
];

export function draw(p, t, o) {
  const C = fit(o.palette, 6), f = Math.floor(clamp(t / 0.1) * 2) % 2;
  for (const [x0, x1, ci] of TAILS[f]) for (let x = x0; x <= x1; x++) p.dot(x, 0, C[ci]);
  // 弹头：白芯、粉边、红壳，上下各一像素
  for (let x = 4; x <= 9; x++) p.dot(x, 0, C[x >= 7 ? 5 : 4]);
  p.dot(10, 0, C[3]);
  for (let x = 4; x <= 8; x++) { p.dot(x, -1, C[x >= 6 ? 3 : 2]); p.dot(x, 1, C[x >= 6 ? 3 : 2]); }
  p.dot(5 + f, -2, C[1]);
  p.dot(6 - f, 2, C[1]);
  p.glow(8, 0, 5, C[2], 0.3);
}
