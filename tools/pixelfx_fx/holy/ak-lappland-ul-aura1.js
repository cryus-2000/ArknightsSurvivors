// 拉普兰德 S1「日晷」开技期间常驻标识（docs/242 放开版，用户 11-03 定第 2 条「身上常驻一层淡的灰白标识，光环、星点、速度线」）：
// 原点 = 脚底，循环播放（S1 是永久技能，开了就一直在，所以必须淡、必须稀：用户「画面不能脏」）。
// 原作 whitew_skill_01_buff：身周一圈断续细环（ray_15，灰）+ 上飘星点（star_10）+ 上冲速度线（trail_08）。本作照此：
//   - 脚下一圈断续细弧（地面透视 sy 0.55），只有三段、慢慢转，最暗两阶，不是完整圆、不是同心圈（§12.3）；
//   - 身侧两三颗小三角光点上飘（同 S1 起手的三角，和起手呼应）；
//   - 偶尔一道竖向速度线从脚边往上冲。
// 一圈 1.2 秒首尾相接（所有运动按周期写）。分层：core = 断续弧；deco = 光点、速度线。队友版（quick）光点减半。
import { Rng, fit, clamp, TAU } from "../../core/index.js";

export const meta = {
  name: "Lappland sundial aura",
  desc: "A faint looping self-buff mark: three short broken arcs slowly turning on the ground at her feet, two or three small triangles drifting up beside her, an occasional upward speed line.",
  tags: ["buff", "aura", "topdown", "loop"],
  size: [64, 60],
  origin: [32, 46],
  duration: 1.2,
  loop: true,
  fps: 10,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    ring: 15,
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 31,
  },
};

const SY = 0.55, P = 1.2;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", R = +o.ring;
  const arcs = [[0.2, 0.9], [2.3, 0.7], [4.1, 1.0]].map(([a, L]) => [a + Rg.range(-0.2, 0.2), L]);
  const tris = Array.from({ length: quick ? 1 : 3 }, (_, i) => ({ x: (i % 2 ? 1 : -1) * Rg.range(8, 14), ph: i / 3 + Rg.range(-0.05, 0.05), s: Rg.range(1, 1.6) }));
  const line = { x: Rg.range(-9, 9), ph: Rg.range(0, 1) };
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const tt = t % P, rot = (tt / P) * TAU / 3;   // 一个周期转 120°，三段弧轮换回原位，首尾相接
      if (core) for (const [a0, L] of arcs) {
        for (let a = a0 + rot; a < a0 + rot + L; a += 0.06) {
          const x = Math.round(Math.cos(a) * R), y = Math.round(Math.sin(a) * R * SY);
          p.dot(x, y, C[Math.sin(a) > 0 ? 3 : 2]);   // 前半圈（靠近镜头）亮一阶
        }
      }
      if (deco) for (const q of tris) {
        const u = ((tt / P + q.ph) % 1);
        const y = -4 - u * 28, a = Math.sin(u * Math.PI);
        if (a < 0.2) continue;
        const s = q.s, x = q.x + Math.sin(u * 6.28) * 1.5;
        p.blend(Math.round(x), Math.round(y - s), C[5], 0.8 * a);
        p.blend(Math.round(x - s), Math.round(y + s * 0.6), C[4], 0.6 * a);
        p.blend(Math.round(x + s), Math.round(y + s * 0.6), C[4], 0.6 * a);
      }
      if (deco) {   // 速度线：每周期一次，从脚边往上冲 0.3 秒
        const u = ((tt / P + line.ph) % 1) / 0.25;
        if (u < 1) {
          const y0 = -2 - u * 30, L = 7;
          for (let k = 0; k < L; k++) p.blend(Math.round(line.x), Math.round(y0 + k), C[4], 0.7 * (1 - k / L) * (1 - u * 0.6));
        }
      }
    },
  };
}
