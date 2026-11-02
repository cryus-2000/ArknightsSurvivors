// 流明精二「灯塔光柱」整条光束（docs/229，0.2 s @20）：@2x，画布 208×24、原点 (4,12) = 起点，朝右，长 200（pillar_len）、半宽 5（pillar_w 10）。
// 游戏里整条画一次（替换原来 fx_lumen_beam 沿线等距平铺）。首帧芯线一道白、两侧浅蓝，边缘按噪声起伏；
// 随后收细冷却，从远端起按噪声断成长短不一的几截，散出几点光屑。
import { Particles, P, Rng, fit, clamp, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lumen beacon beam",
  desc: "Lumen's lighthouse beam: a straight shaft of lantern light flashes with a white core line, thins and cools, and breaks into uneven pieces from the far end.",
  tags: ["holy", "beam", "light", "one-shot"],
  size: [208, 24],
  origin: [4, 12],
  duration: 0.2,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, len: 200, half: 5, seed: 2 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), L = o.len, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  for (let i = 0; i < 6; i++) ps.spawn(P.FLAKE, Rg.range(0.2, 1) * L, Rg.range(-3, 3), Rg.range(-10, 10), Rg.range(-25, 25), Rg.range(0.08, 0.15), Rg.pick([C[4], C[5]]), 1, Rg.range(0.04, 0.08));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const u = clamp(t / 0.16);
      if (u < 1) {
        const hw = o.half * (1 - 0.6 * u);
        for (let x = 0; x <= L; x++) {
          // 断开：从远端起按噪声挖掉
          if (u > 0.3 && noise(x * 0.07, S + 3) * 0.5 + 0.5 < (u - 0.3) * 1.6 * (x / L + 0.3)) continue;
          const w = hw * (0.8 + 0.25 * noise(x * 0.09 + t * 40, S)) * (x < 6 ? x / 6 : 1);
          for (let y = -Math.ceil(w); y <= Math.ceil(w); y++) {
            const q = Math.abs(y) / Math.max(0.5, w);
            if (q > 1) continue;
            const ci = t < 0.04 ? (q < 0.2 ? 6 : q < 0.55 ? 4 : 3) : clamp(Math.round(4.4 - u * 2 - q * 2), 1, 4);   // 白只在芯线
            p.blend(x, y, C[ci], q > 0.7 ? 0.6 : 0.95);
          }
        }
      }
      ps.draw(p);
    },
  };
}
