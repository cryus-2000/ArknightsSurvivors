// 推进之王精二「破阵」岩刺（D 组）：@2x 密度，原点 = 底边中点，7 帧 @18：拔起 → 停 → 缩回碎开。替换 Codex fx_siege_rock_spike。
// 一根带金色裂纹的岩刺（棱面受光、倾角随机），旁边一根矮的；拔起首帧刺尖白亮，缩回时掉碎石、扬一点尘。
import { Bits, B, Particles, P, Rng, fit, clamp, ease, crystal } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Siege rock spike",
  desc: "A rock spike veined with gold thrusts from the floor with a white tip flash, holds, then sinks and crumbles with grit and a puff of dust.",
  tags: ["earth", "spike", "ground", "one-shot"],
  size: [40, 64],
  origin: [20, 60],
  duration: 0.4,
  loop: false,
  fps: 18,
  bg: "ground",
  options: { palette: ["#0e0c0a", "#2a241c", "#4a3e2e", "#6e5c40", OP.siege[2], OP.siege[3], OP.siege[5], "#ffffff"], seed: 3 },
};

export function create(o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed);
  const bits = new Bits({ ground: () => 0 }), ps = new Particles({ rng: R, ground: () => 0 });
  const lean = R.range(-4, 4), H = R.range(40, 48), side = { x: R.sign() * R.range(6, 9), h: R.range(12, 18) };
  let t = 0, crumbled = false;
  return {
    update(dt) {
      t += dt;
      if (!crumbled && t > 0.24) {
        crumbled = true;
        for (let i = 0; i < 5; i++) bits.add({ kind: B.CHUNK, ramp: [C[0], C[1], C[2], C[3], C[4]], x: R.range(-4, 4), y: -R.range(6, 20), vx: R.range(-50, 50), vy: -R.range(20, 70), a: R.range(0, 3), va: R.range(-10, 10), s: R.range(1, 2), g: 0.6, life: R.range(0.12, 0.16) });
        for (let i = 0; i < 2; i++) ps.spawn(P.DUST, R.range(-6, 6), -1, R.range(-15, 15), -6, R.range(0.12, 0.15), C[2], R.range(3, 4));
      }
      bits.update(dt); ps.update(dt);
    },
    draw(p) {
      const up = ease.outBack(clamp((t + 0.02) / 0.1)), down = clamp((t - 0.22) / 0.12), g = up * (1 - down);
      if (g > 0.05) {
        crystal(p, side.x, 0, side.h * g, 7, side.x * 0.3, C.slice(0, 7));
        crystal(p, 0, 0, H * g, 12, lean, t < 0.06 ? C.slice(1, 8) : C.slice(0, 7), { white: t < 0.05, glint: t < 0.15 ? 0.85 : -1 });
        // 金色裂纹：不等距的两三道斜缝
        for (const v of [0.25 + R.range(0, 0.1), 0.55 + R.range(0, 0.1)]) {
          const y = -H * g * v, x = lean * v;
          p.line(x - 3, y + 1, x + 2, y - 2, C[t < 0.15 ? 6 : 5]);
        }
      }
      bits.draw(p); ps.draw(p);
    },
  };
}
