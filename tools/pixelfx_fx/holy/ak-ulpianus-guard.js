// 乌尔比安 S2 发动（替换通用 fx_shield_amber × 1.4：琥珀色不是他的色、1x 放大到每像素 2.8 世界像素）：@2x，原点 = 身体中心（at self off [0,-20]），游戏 scale 1.0。
// 脚下海水猛地掀起，在身前合成一道不规整的半透明水幕护墙（前半圈，高度按噪声起伏），首帧白闪；水幕顶端碎成水沫往后落，整片沉回地面。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Ulpianus tide guard",
  desc: "Seawater heaves up around him into a ragged translucent half-wall in front, a white flash, then its crest breaks into spray and it sinks back.",
  tags: ["water", "shield", "buff", "one-shot"],
  size: [120, 100],
  origin: [60, 50],
  duration: 0.55,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.ulpianus],
    radius: 34,
    seed: 2,
  },
};

const SY = 0.45, FEET = 20;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => FEET + 14, sparks: [C[7], C[6], C[5]], haze: C[4] });
  const hAt = (a) => 26 * (0.55 + 0.45 * (0.5 + 0.5 * noise(a * 2.3, o.seed))) * (0.85 + 0.3 * (0.5 + 0.5 * noise(a * 7, o.seed + 4)));
  let t = 0, broke = false;
  function wall(p) {
    const rise = ease.outQuart(clamp((t + 0.02) / 0.12)), sink = smooth(0.24, 0.5, t);
    if (sink >= 1) return;
    const seen = new Set();
    for (let a = 0.15; a < Math.PI - 0.15; a += 0.6 / R) {   // 只画前半圈（身前）
      const x = Math.cos(a) * R, y0 = FEET + Math.sin(a) * R * SY, h = hAt(a) * rise * (1 - sink);
      for (let d = 0; d <= h; d += 1) {
        const px = Math.round(x), py = Math.round(y0 - d), key = px * 1000 + py;
        if (seen.has(key)) continue;
        seen.add(key);
        const v = d / Math.max(h, 1), crest = v > 0.82;
        const ci = clamp(Math.round((crest ? 6.5 : 3 + v * 2.5) - sink * 2 + (t < 0.03 ? 2 : 0)), 1, 7);
        p.blend(px, py, C[ci], crest ? 0.9 : 0.5);
      }
    }
  }
  return {
    update(dt) {
      t += dt;
      if (!broke && t >= 0.16) {
        broke = true;
        for (let a = Rg.range(0.2, 0.5); a < Math.PI - 0.2; a += Rg.range(0.25, 0.55)) {
          const x = Math.cos(a) * R, y = FEET + Math.sin(a) * R * SY - hAt(a);
          ps.spawn(Rg.chance(0.5) ? P.FLAKE : P.SPARK, x, y, Rg.range(-30, 30), Rg.range(-60, -20), Rg.range(0.15, 0.25), C[Rg.int(5, 7)], 1.5);
        }
      }
      ps.update(dt);
    },
    draw(p) {
      wall(p);
      ps.draw(p);
    },
  };
}
