// 远程怪攻击起手（怪物风格试点 11-04）：原点 = 出手点（投掷手 / 发射口）。
// 3–4 道细流从身边绕弧收进出手点（mode 0 = 砂砾：颗粒成串、灰白；mode 1 = 神经丝：连续细线），收满一帧短十字闪。
// 预警亮部用危险色 #ff2667（只给预警）；敌弹青 #33ceff 不用在这里（留给子弹本体）。元素 2 种。
import { Rng, fit, clamp, smooth, ease, TAU } from "../../core/index.js";

export const meta = {
  name: "Monster ranged windup",
  desc: "A few thin streams curl in to the release point, grit or nerve thread, and end in a short danger-red cross flash.",
  tags: ["monster", "windup", "telegraph", "one-shot"],
  size: [56, 56],
  origin: [28, 28],
  duration: 0.38,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#262a33", "#4b5260", "#8a93a3", "#c9cfd8"],          // 细流本体色（砂砾 / 神经丝）
    danger: ["#8a1838", "#ff2667", "#ffd0dc"],                         // 预警亮部
    mode: 0,
    seed: 4,
  },
};

export function create(o) {
  const C = fit(o.palette, 4), D = fit(o.danger, 3), Rg = new Rng(o.seed), grit = +o.mode === 0;
  const n = Rg.int(3, 4), a00 = Rg.range(0, TAU), spin = Rg.chance(0.5) ? 1 : -1;
  const ss = [];
  for (let i = 0; i < n; i++) ss.push({ a: a00 + (i + Rg.range(-0.25, 0.25)) * TAU / n, d: Rg.range(16, 22), turn: spin * Rg.range(0.9, 1.4), t0: Rg.range(0, 0.06), T: Rg.range(0.2, 0.26) });
  const at = (s, u) => { const r = s.d * (1 - u), a = s.a + s.turn * u; return [Math.cos(a) * r, Math.sin(a) * r * 0.8]; };
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      for (const s of ss) {
        const u = clamp((t - s.t0) / s.T);
        if (t < s.t0 || u >= 1) continue;
        const hd = ease.inQuad(u), tl = Math.max(0, hd - 0.4);
        for (let v = tl; v <= hd; v += grit ? 0.05 : 0.015) {
          const f = (v - tl) / Math.max(0.01, hd - tl), [x, y] = at(s, v);
          if (grit && ((v * 97 + s.a * 13) % 1) < 0.35) continue;   // 砂砾：颗粒间留空
          p.px(x, y, f > 0.8 ? D[1] : C[clamp(Math.round(1 + f * 2.2), 1, 3)]);
          if (grit && f > 0.5) p.px(x + 1, y, C[2]);
        }
      }
      if (t >= 0.28 && t < 0.37) {
        const k = 1 - smooth(0.28, 0.37, t), L = 3.5 * k + 1;
        for (let d = -L; d <= L; d += 0.5) { p.px(d, 0, D[t < 0.32 ? 2 : 1]); p.px(0, d, D[t < 0.32 ? 2 : 1]); }
      }
    },
  };
}
