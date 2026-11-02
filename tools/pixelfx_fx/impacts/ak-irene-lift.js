// 艾丽妮精一挑飞（D 组）：@2x 密度，原点 = 敌人身上（游戏里 off [0, -18]）。替换 Codex fx_irene_lift_arc。
// 一道从下往上撩起的细弧（不对称、尾细头粗），白热后冷却成玫瑰色，弧顶甩出两三粒光屑往上飘。
import { Particles, P, Rng, fit, clamp, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Irene lift",
  desc: "An upward flick: a thin lopsided arc sweeps up from below, flashes white, cools to rose and tosses a few motes upward.",
  tags: ["melee", "launch", "rapier", "one-shot"],
  size: [44, 52],
  origin: [22, 30],
  duration: 0.36,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: [...OP.irene], seed: 6 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  const R = 15, a0 = 2.2, span = -2.9;   // 从左下往上绕到右上
  let t = 0.035, tossed = false;
  return {
    update(dt) {
      t += dt;
      if (!tossed && t > 0.05) {
        tossed = true;
        for (let i = 0; i < 3; i++) ps.spawn(P.MOTE, Rg.range(2, 9), -R + Rg.range(-2, 3), Rg.range(-20, 30), -Rg.range(50, 110), Rg.range(0.12, 0.2), C[5 + Rg.int(0, 2)], Rg.range(0.5, 0.9));
      }
      ps.update(dt);
    },
    draw(p) {
      const head = ease.outExpo(clamp(t / 0.05)), tail = clamp((t - 0.06) / 0.14), age = clamp(t / 0.2);
      for (let u = tail; u <= head; u += 0.01) {
        const a = a0 + span * u, w = 0.6 + 3.2 * Math.pow(u, 1.5) * (1 - tail * 0.5);
        const rr = R + 1.2 * noise(a * 5, o.seed);
        for (let d = 0; d < w; d += 0.5) {
          const q = d / Math.max(w, 0.5), ci = t < 0.03 ? 7 : clamp(Math.round(7 - q * 3 - age * 4 - (1 - u) * 1.5), 1, 7);
          p.px(Math.cos(a) * (rr - d), Math.sin(a) * (rr - d) * 1.1, C[ci]);
        }
      }
      if (t < 0.1) p.glow(Math.cos(a0 + span * head) * R, Math.sin(a0 + span * head) * R, 8, C[5], 0.3 * (1 - t / 0.1));
      ps.draw(p);
    },
  };
}
