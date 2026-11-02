// 能天使技能 / 倾泻弹体（D 组）：@2x 密度，循环 2 帧，原点 = 弹头，正右飞。替换 proj_exusiai_bullet_s1/s2/s3/power（普攻弹体归 fx-basic-atk）。
// 白热弹头 + 按技能代表色的曳光尾，尾巴长短、亮度两帧交替闪，尾端断成两三点（不画整条长线，免得连成光束）。
import { fit, clamp } from "../../core/index.js";

export const meta = {
  name: "Exusiai bullet",
  desc: "A tracer round loop: white-hot head, a tail in the skill's colour that flickers in length and brightness between two frames and breaks into dots at the end.",
  tags: ["projectile", "bullet", "tracer", "loop"],
  size: [40, 16],
  origin: [30, 8],
  duration: 0.1,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: ["#2a1a06", "#7a4c0e", "#d89a2a", "#ffd76a", "#fff3cc", "#ffffff"], len: 22, thick: 1, seed: 1 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 6), f = Math.floor(t * 20 + 1e-6) % 2, L = o.len * (f ? 0.82 : 1), th = +o.thick;
  for (let x = 0; x > -L; x -= 1) {
    const u = -x / L;
    if (u > 0.78 && (Math.floor(-x) % 3 !== (f ? 1 : 0))) continue;   // 尾端断成点
    const ci = clamp(Math.round(5 - u * 4 - (f ? 0.5 : 0)), 1, 5);
    p.px(x, 0, C[ci]);
    if (th > 0 && u < 0.45) { p.px(x, -1, C[Math.max(1, ci - 2)]); p.px(x, 1, C[Math.max(1, ci - 2)]); }
  }
  p.rect(-1, -1, 3, 3, C[f ? 4 : 5]);
  p.px(2, 0, C[5]);
  p.glow(0, 0, 5, C[3], 0.2);
}
