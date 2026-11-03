// 怪物受击（怪物风格试点 11-04，docs: Claude outputs/monster_fx_pilot.md）：原点 = 命中点，打击方向朝右（+x）。
// 两种元素：① 一帧白热锯齿切痕（2 px，横过命中点）→ 第 2 帧退成本体亮阶；② 5–8 片本体材质碎屑顺打击方向崩出、受重力下坠、翻面换色、落地前消失。
// 不画圆、不放光；颜色全取本体色阶（palette），白只占 1 帧。白闪剪影仍用游戏原有的 _white（不在本帧条里）。
import { Rng, fit, clamp, noise } from "../../core/index.js";

export const meta = {
  name: "Monster hit chips",
  desc: "A one-frame white jagged cut across the hit point, then a few chips of the monster's own material break off along the blow and drop.",
  tags: ["monster", "hit", "impact", "chips", "one-shot"],
  size: [64, 48],
  origin: [24, 26],
  duration: 0.25,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#1b2333", "#3a4660", "#6d7b98", "#a9b6cc", "#e3e9f2"],   // 本体材质 5 阶（暗 → 亮）
    big: 0,      // 1 = Boss：碎屑多一倍、切痕长一半
    seed: 1,
  },
};

export function create(o) {
  const C = fit(o.palette, 5), Rg = new Rng(o.seed), big = +o.big > 0;
  const L = big ? 22 : 14, n = big ? Rg.int(10, 14) : Rg.int(6, 9);
  const tilt = Rg.range(-0.5, 0.5);
  const chips = [];
  for (let i = 0; i < n; i++) {
    const a = Rg.range(-0.9, 0.7), sp = Rg.range(50, 120) * (big ? 1.3 : 1);
    chips.push({ x: Rg.range(-2, 2), y: Rg.range(-3, 3), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - Rg.range(10, 40), s: Rg.int(2, big ? 4 : 3), c: Rg.int(1, 3), life: Rg.range(0.14, 0.24), flip: Rg.range(0.03, 0.07) });
  }
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      if (t < 0.09) {   // 切痕：第 1 帧白、第 2 帧本体亮阶
        const col = t < 0.045 ? "#ffffff" : C[4];
        for (let u = -L / 2; u <= L / 2; u += 0.5) {
          const j = 1.3 * noise(u * 0.7, o.seed), x = u * Math.cos(tilt), y = u * Math.sin(tilt) + j;
          const w = (1 - Math.abs(u) / (L / 2)) > 0.35 ? 1 : 0;
          p.px(x, y, col);
          if (w) p.px(x, y + 1, col);
        }
      }
      for (const c of chips) {   // 碎屑：小方块（1–3 px），翻面在亮暗两阶之间跳
        if (t > c.life) continue;
        const x = c.x + c.vx * t, y = c.y + c.vy * t + 260 * t * t, k = Math.floor(t / c.flip) % 2;
        const col = C[clamp(c.c + (k ? 1 : -1) * (t < 0.05 ? -0 : 1), 0, 4)];
        for (let dx = 0; dx < c.s; dx++) for (let dy = 0; dy < (k ? c.s : Math.max(1, c.s - 1)); dy++) p.px(x + dx, y + dy, col);
      }
    },
  };
}
