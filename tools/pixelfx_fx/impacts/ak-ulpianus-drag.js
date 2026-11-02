// 乌尔比安拖锚扬尘（锚链拖地每 36 px 一团 / 冲锋起点，替换 fx_ulpianus_drag_dust）：@2x，保留画布，游戏按 bottom 锚 × PX 放，随拖动方向转。
// 锚刮过海床：一小股深海泥沙贴地向后翻起（团块大小、高低不等），表面几粒碎石弹开，随后泥沙摊平沉下。颜色走深海环境梯度，不抢敌方色。
import { Particles, Bits, B, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { ENV, FPS } from "../house.js";

export const meta = {
  name: "Ulpianus anchor drag silt",
  desc: "Seabed silt churned up behind a dragged anchor: uneven low clumps roll backward, a few pebbles skip off, then it settles flat.",
  tags: ["impact", "dust", "ground", "one-shot"],
  size: [64, 30],
  origin: [32, 26],
  duration: 0.3,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [ENV[0], ENV[1], ENV[2], "#3b5560", "#566b6b", "#7d9493", "#b7c9c4"],
    seed: 5,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 0, sparks: [C[6], C[5], C[4]] });
  const bits = new Bits({ ground: () => 0 });
  const clumps = [];
  for (let x = Rg.range(-4, 0); x > -24; x -= Rg.range(4, 8)) clumps.push({ x, r: Rg.range(2.5, 5.5), h: Rg.range(3, 9), d: Rg.range(0, 0.05) });
  let t = 0, kicked = false;
  return {
    update(dt) {
      t += dt;
      if (!kicked) {
        kicked = true;
        for (let i = 0; i < 4; i++) bits.add({ kind: B.CHUNK, x: Rg.range(-4, 2), y: -1, vx: Rg.range(-70, -25), vy: Rg.range(-80, -40), a: 0, va: Rg.range(-10, 10), s: Rg.range(1, 2), ramp: [C[2], C[3], C[5]], g: 2, bounce: 0.3, life: Rg.range(0.18, 0.26) });
      }
      ps.update(dt);
      bits.update(dt);
    },
    draw(p) {
      for (const c of clumps) {
        const u = t - c.d;
        if (u < 0) continue;
        const rise = ease.outQuart(clamp(u / 0.08)), fall = smooth(0.08, 0.24, u);
        const h = c.h * rise * (1 - fall), R = c.r * (1 + fall * 0.6);
        if (fall >= 1) continue;
        for (let y = -Math.ceil(h + R * 0.5); y <= 1; y++) for (let x = -Math.ceil(R); x <= Math.ceil(R); x++) {
          const q = Math.hypot(x / R, (y + h * 0.5) / Math.max(1, h * 0.6 + R * 0.4)) / (1 + 0.25 * noise(x * 0.6 + c.x, o.seed));
          if (q > 1) continue;
          const top = y < -h * 0.5;
          const ci = clamp(Math.round((top ? 5 : 3) - fall * 2 + (t < 0.03 ? 1 : 0)), 1, 6);
          p.blend(Math.round(c.x + x), y, C[ci], (q > 0.75 ? 0.55 : 0.8) * (1 - fall * 0.7));
        }
      }
      bits.draw(p);
      ps.draw(p);
    },
  };
}
