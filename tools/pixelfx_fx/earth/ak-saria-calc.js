// 塞雷娅连携「区域钙化」的钙晶簇（D 组）：@2x 密度，单张静态图（脚本负责长出、淡出），原点 = 底边中点。替换 fx_lk_sa_calc1–3。
// 一簇 3–5 根琥珀钙晶，高矮、粗细、倾角都随机，后排暗、前排亮，底部一圈碎晶。
import { Rng, fit, crystal } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria calcite cluster",
  desc: "A still cluster of three to five amber calcite crystals of uneven height, width and lean, darker at the back, with grit at the base.",
  tags: ["earth", "crystal", "prop", "still"],
  size: [76, 80],
  origin: [38, 76],
  duration: 0.1,
  loop: false,
  fps: 10,
  bg: "ground",
  options: { palette: [...OP.saria], seed: 1 },
};

export function draw(p, t, o) {
  if (t >= 0.1) return;
  const C = fit(o.palette, 8), R = new Rng(o.seed), n = R.int(3, 5);
  const xs = [];
  for (let i = 0; i < n; i++) xs.push({ x: R.range(-22, 22), h: R.range(26, 66), w: R.range(9, 16), lean: R.range(-10, 10), back: R.chance(0.4) });
  xs.sort((a, b) => (a.back === b.back ? b.h - a.h : a.back ? -1 : 1));
  for (const s of xs) crystal(p, s.x, 0, s.h, s.w, s.lean + s.x * 0.15, s.back ? C.slice(0, 7) : C.slice(1, 8), { glint: s.back ? -1 : R.range(0.3, 0.7) });
  for (let i = 0; i < 9; i++) { const x = R.range(-26, 26); p.px(x, R.range(-2, 1), C[R.int(3, 6)]); }
}
