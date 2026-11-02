// 乌尔比安拖锚奔跑的锚爪刮地（blocks.run_fx，跑动时每 0.12 秒在脚下播一次，随跑动方向转）：@2x，保留画布，原点 = 脚底（画布右侧），
// 锚爪着地点在身后 28–52 px（同 op_ulpianus_run 拖锚条，11-03）。一小段刮出的浅沟（不等长、略弯），沟边翻起两三团深海泥沙往后落，偶尔擦出一两粒铁色火星。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP, ENV, FPS, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Ulpianus anchor drag furrow",
  desc: "Where the dragged anchor's flukes bite the seabed: a short uneven scraped furrow, a few silt clumps kicked back, now and then an iron spark.",
  tags: ["impact", "dust", "ground", "trail", "one-shot"],
  size: [80, 26],
  origin: [70, 20],
  duration: 0.36,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.ulpianus],
    silt: [ENV[0], ENV[1], "#3b5560", "#566b6b", "#7d9493"],
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), D = fit(o.silt, 5), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1, sparks: [C[6], C[5], C[4]] });
  const x0 = -Rg.range(30, 46), L = Rg.range(8, 15), bend = Rg.range(-1.2, 1.2), sd = Rg.range(0, 30);
  const clumps = [];
  for (let i = 0, n = Rg.int(2, 3); i < n; i++) clumps.push({ x: x0 - Rg.range(0, L), y: Rg.range(-2, 1), r: Rg.range(1.5, 3.2), up: Rg.range(3, 7), d: Rg.range(0, 0.06) });
  let t = 0, fired = false;
  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        if (Rg.chance(0.55)) {
          const n = Rg.int(1, 2);
          for (let i = 0; i < n; i++) ps.spawn(P.SPARK, x0 + 2, -1, Rg.range(-110, -50), Rg.range(-60, -20), Rg.range(0.06, 0.1));
        }
      }
      ps.update(dt);
    },
    draw(p) {
      // 浅沟：锚爪刮过留下的暗线，前端（靠人那头）先亮一下，随后变暗、从尾端淡掉
      const fade = 1 - smooth(0.12, 0.3, t);
      if (fade > 0) {
        for (let i = 0; i <= L; i++) {
          const v = i / L, x = x0 - i, y = bend * v * v + 0.6 * noise(i * 0.5, sd);
          if (v > fade * 1.1) continue;
          p.blend(Math.round(x), Math.round(y), D[1], 0.8 * fade);
          if (t < 0.05 && v < 0.3) p.px(Math.round(x), Math.round(y) - 1, C[5]);   // 刚刮那一下的亮口
        }
      }
      for (const c of clumps) {
        const u = t - c.d;
        if (u < 0) continue;
        const rise = ease.outQuart(clamp(u / 0.08)), fall = smooth(0.08, 0.28, u);
        if (fall >= 1) continue;
        const cy = c.y - c.up * rise * (1 - fall), R = c.r * (1 + fall * 0.5);
        for (let yy = -3; yy <= 3; yy++) for (let xx = -4; xx <= 4; xx++) {
          if (Math.hypot(xx / R, yy / (R * 0.8)) > 1) continue;
          p.blend(Math.round(c.x + xx - u * 10), Math.round(cy + yy), D[yy < 0 ? 4 : 3], (yy < 0 ? 0.7 : 0.55) * (1 - fall) * (u > 0.2 ? TAIL_ALPHA / 0.55 : 1));
        }
      }
      ps.draw(p);
    },
  };
}
