// 能天使普攻弹体（docs/231 普攻试点）：@2x 密度，原点 = 帧中心，正右为飞行方向。
// 画布 40×16，与她技能弹 proj_exusiai_bullet_s1 同尺寸（11-02 用户嫌第一版 32×12 太小）；仍远小于拉普兰德的掷剑。
// 旧弹体是一根实心红条，射速高时首尾相接连成光束（docs/228 §7.3）；这里弹头亮而饱满、弹尾断成长短不一的几截。
// 白只在弹头最前两格（近白 ≤ 12%），柔光走 light 层（_glow 条）。
import { clamp, fit } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Exusiai bullet",
  desc: "A tracer round: a fat white-tipped slug with a red jacket and a broken tail of red dashes of uneven length that flickers between two frames.",
  tags: ["projectile", "bullet", "tracer", "loop"],
  size: [40, 16],
  origin: [20, 8],
  duration: 0.1,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.exusiai, seed: 1 },
};

// 两帧的弹尾断口位置不同：[起点, 终点, 色阶]，x 向左为负；长短不一
const TAILS = [
  [[0, 3, 3], [-6, -2, 2], [-11, -9, 2], [-15, -14, 1]],
  [[1, 3, 3], [-4, -1, 2], [-9, -7, 2], [-14, -12, 1]],
];

export function draw(p, t, o) {
  const C = fit(o.palette, 7), f = Math.floor(clamp(t / 0.1) * 2) % 2;
  for (const [x0, x1, ci] of TAILS[f]) for (let x = x0; x <= x1; x++) p.dot(x, 0, C[ci]);
  // 弹头：中线白芯在最前两格，往后粉、红；上下两层红壳，最外层短、暗
  for (let x = 4; x <= 13; x++) p.dot(x, 0, C[x >= 12 ? 6 : x >= 9 ? 5 : 4]);
  for (let x = 5; x <= 12; x++) { p.dot(x, -1, C[x >= 9 ? 4 : 3]); p.dot(x, 1, C[x >= 9 ? 4 : 3]); }
  for (let x = 6 + f; x <= 10; x++) { p.dot(x, -2, C[2]); p.dot(x, 2, C[2]); }
  p.dot(14, 0, C[4]);
  p.glow(10, 0, 7, C[3], 0.3);
}
