// 水月「束缚」（被水母蛰中的敌人脚下，替换 fx_mizuki_bind_ring）：@2x 循环帧条，地面透视，原点 = 敌人脚下；按敌人半径 14 设计（seg_mizuki 按 r ÷ 14 在 0.85–1.15 内缩放）。
// 三缕长短不一的触丝绕着脚下盘旋，各自起伏、粗细不同，转一整圈正好一个循环；不是一圈点线。
import { Rng, fit, clamp, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Mizuki bind",
  desc: "Three uneven jellyfish tendrils coil around the target's feet, each with its own wobble and thickness, looping seamlessly.",
  tags: ["status", "bind", "jellyfish", "loop", "topdown"],
  size: [56, 36],
  origin: [28, 18],
  duration: 0.6,
  loop: true,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.mizuki],
    radius: 19,
    seed: 3,
  },
};

const SY = 0.5;

function strands(o) {
  const Rg = new Rng(o.seed), out = [];
  for (let i = 0; i < 3; i++) out.push({ a: i * 2.1 + Rg.range(-0.4, 0.4), len: Rg.range(1.3, 2.4), dr: Rg.range(-3, 2), wav: Rg.int(2, 4), amp: Rg.range(1, 2.4), ph: Rg.range(0, TAU), w: Rg.range(1, 2) });
  return out;
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ph = t / 0.6 * TAU;                 // 一圈 = 一个循环，无缝
  for (const s of strands(o)) {
    const n = Math.ceil(s.len * o.radius * 1.4);
    for (let i = 0; i <= n; i++) {
      const v = i / n, a = s.a + ph + v * s.len;
      const r = o.radius + s.dr + Math.sin(v * s.wav * Math.PI + s.ph + ph * 2) * s.amp;
      const x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
      const far = Math.sin(a) < 0, head = v > 0.85;
      const c = C[clamp(Math.round((head ? 7 : 4 + v * 2) - (far ? 1.5 : 0)), 2, 7)];
      const w = s.w * Math.sin(Math.PI * Math.min(1, v * 1.1)) ;
      p.blend(Math.round(x), Math.round(y), c, far ? 0.55 : 0.9);
      if (w > 1.3) p.blend(Math.round(x), Math.round(y - 1), C[Math.max(2, (head ? 6 : 4) - (far ? 1 : 0))], far ? 0.4 : 0.7);
    }
  }
}
