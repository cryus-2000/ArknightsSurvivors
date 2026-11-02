// 斯卡蒂精二潮刃出手（docs/229 §7 第 2 批，替 fx_skadi_surge_release）：@2x，原点 = 出手点，朝右，游戏里按方向旋转。
// 剑锋前方迸开一片扇形水幕：前缘白、往后变深、边缘按噪声起伏，随后碎成往前飞的水珠和水雾，0.25 s 收尽。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";

export const meta = {
  name: "Skadi tide release",
  desc: "Launch burst: a ragged fan of water flares ahead of the blade, white rim cooling to deep blue, then breaks into forward-flying droplets and mist.",
  tags: ["water", "muzzle", "burst", "one-shot"],
  size: [96, 64],
  origin: [30, 32],
  duration: 0.35,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    seed: 8,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, haze: C[4] }), lights = new Lights();
  lights.add(8, 0, 22, C[5], 0.6, 0.18);
  let t = 0, broke = false;
  const SPAN = 0.95;
  return {
    update(dt) {
      t += dt;
      if (!broke && t > 0.1) {
        broke = true;
        for (let i = 0; i < 18; i++) {
          const a = Rg.range(-SPAN, SPAN) * 0.9, r = Rg.range(12, 26), sp = Rg.range(80, 220);
          ps.spawn(P.MOTE, Math.cos(a) * r, Math.sin(a) * r, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.1, 0.22), C[5 + Rg.int(0, 2)], Rg.range(0.5, 0.9));
        }
        for (let i = 0; i < 5; i++) {
          const a = Rg.range(-SPAN, SPAN) * 0.7, r = Rg.range(10, 22);
          ps.spawn(P.VAPOUR, Math.cos(a) * r, Math.sin(a) * r, Math.cos(a) * 40, Math.sin(a) * 40, Rg.range(0.15, 0.22), C[4], Rg.range(3, 5));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    draw(p) {
      const grow = ease.outQuart(clamp((t + 0.03) / 0.08)), fade = 1 - smooth(0.08, 0.16, t);
      if (fade > 0) {
        const R = 6 + 19 * grow, cool = clamp(t / 0.1) * 2;
        for (let y = -R - 0.5; y <= R + 0.5; y++)
          for (let x = -0.5; x <= R + 4.5; x++) {
            const a = Math.atan2(y, x), r = Math.hypot(x, y);
            if (Math.abs(a) > SPAN) continue;
            const edge = R * (1 + 0.16 * noise(a * 5.3, o.seed) + 0.08 * noise(a * 13, o.seed + 4)) * (1 - 0.25 * Math.pow(Math.abs(a) / SPAN, 2));
            const q = (edge - r) / (R * 0.45);
            if (q < 0 || q > 1) continue;
            const ci = clamp(Math.round(7 - q * 5 - cool - Math.abs(a) * 1.2), 1, 7);
            if (q < 0.35) p.px(x, y, C[ci]);
            else p.blend(x, y, C[ci], (1.25 - q) * fade);
          }
      }
      ps.draw(p);
      lights.draw(p);
    },
  };
}
