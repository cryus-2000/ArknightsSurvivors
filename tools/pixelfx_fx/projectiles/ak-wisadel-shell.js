// 维什戴尔魂炮小炮弹（D 组）：@2x 密度，循环 2 帧，原点 = 弹头，正右飞（游戏沿飞行方向转）。替换 proj_wisadel_soul_shell。
// 暗红晶核带一点暖亮芯，后面拖两三团不等长的暗烟；两帧之间烟团错开、核心明暗交替。
import { fit } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Wisadel soul shell",
  desc: "A small shell loop: a dark-red crystal core with a warm hot point, dragging two or three uneven puffs of dark smoke that shift between the two frames.",
  tags: ["projectile", "shell", "loop"],
  size: [32, 16],
  origin: [22, 8],
  duration: 0.1,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: ["#0c0608", "#24080c", OP.wisadel[0], OP.wisadel[1], OP.wisadel[2], "#ff5a3a", "#ffb08a"] },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), f = Math.floor(t * 20 + 1e-6) % 2;
  const puffs = f ? [[-7, 0, 3.2], [-13, 1, 2.4], [-18, -1, 1.6]] : [[-6, -1, 3], [-12, 0, 2.6], [-17, 1, 1.4]];
  for (const [x, y, r] of puffs) p.disc(x, y, r, C[1], 0.75);
  p.poly([[4, 0], [0, -3], [-4, 0], [0, 3]], C[3]);
  p.poly([[3, 0], [0, -2], [-2, 0], [0, 2]], C[f ? 4 : 5]);
  p.px(1, -1, C[6]);
}
