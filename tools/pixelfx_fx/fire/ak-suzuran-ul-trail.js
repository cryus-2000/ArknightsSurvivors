// 铃兰精二「狐火拖尾」的一处路火（pixelfx 放开版，docs/242）：1x，原点 = 地面一点，一次性；seg 沿路径错开铺几块。
// 贴地一条短余烬带 + 两三团矮胖的小狐火此起彼落（用户 11-04：短胖火团，不画细长火舌），最后只剩几点暗红。
import { fit, clamp } from "../../core/index.js";
import { pnoise, hotFirst, floorLight } from "./_lib.js";
import { foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire trail patch unleashed",
  desc: "One patch of a burning foxfire trail: a low ember band on the ground with two or three small plump foxfire balls that flare, shrink into embers and fade to a few dark-red points.",
  tags: ["fire", "ground", "trail", "foxfire", "one-shot"],
  size: [40, 30],
  origin: [20, 22],
  duration: 1.0,
  loop: false,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", seed: 3 },
};

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, u = clamp(t / meta.duration);
  const r1 = (k) => (Math.sin(S * 12.9898 + k * 78.233) * 43758.5453) % 1, rr = (k) => Math.abs(r1(k));
  if (core) {
    // 余烬带：贴地、两头收、噪声边；越到后面越暗越窄
    const L = 9 + 3 * rr(1), heat = 1 - u;
    for (let x = -L; x <= L; x += 0.5) {
      const e = 1 - Math.abs(x) / L, half = (0.6 + 1.4 * heat) * Math.sqrt(e) + 0.4 * pnoise(x * 0.5 + S, 17, S);
      if (half < 0.35) continue;
      const c = heat > 0.7 ? (e > 0.5 ? H[2] : H[4]) : heat > 0.35 ? (e > 0.5 ? H[4] : H[6]) : e > 0.6 && pnoise(x * 0.9, 23, S + 2) > 0.2 ? H[6] : H[8];
      for (let q = -half; q <= half; q += 0.5) p.px(x, q * 0.6, c);
    }
    const n = 2 + (rr(2) > 0.5 ? 1 : 0);
    for (let i = 0; i < n; i++) {
      const x = -6 + 12 * (i + 0.3 * rr(10 + i)) / n, r0 = 2.4 + 1.2 * rr(20 + i), d0 = 0.06 * i * rr(30 + i);
      const v = clamp((t - d0) / 0.75), g = v < 1 ? Math.sin(Math.PI * Math.min(1, v * 1.4)) : 0;
      if (g > 0.15) foxClump(p, x, -r0 * g * 0.8, r0 * g, { H, t, fps: meta.fps, seed: S * 9 + i, tips: 2, heat: 1 - 0.6 * v, sq: 0.8 });
    }
  }
  if (deco) floorLight(p, 0, 0, 12, 4, F[5], 0.3 * (1 - u) * (1 - u));
}
