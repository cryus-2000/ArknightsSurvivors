// 流明普攻光弹命中（docs/229 §3 普攻档）：@2x，1 贴图像素 = 1 世界像素，原点 = 命中点。
// 白芯一闪，四道长短不一、角度略歪的灯光芒（竖向最长，不等距、不对称），一段断开的光弧往外推，几片光屑往上飘散。
import { Particles, P, Rng, fit, clamp, ease } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lumen hit",
  desc: "A lantern bolt hits: a white core pops, four uneven glints flare and shrink, a broken arc of light pushes out, flecks drift up.",
  tags: ["impact", "hit", "light", "holy", "one-shot"],
  size: [44, 44],
  origin: [22, 22],
  duration: 0.2,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.lumen, seed: 3 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  for (let i = 0; i < 5; i++)
    ps.spawn(P.FLAKE, Rg.range(-6, 6), Rg.range(-4, 3), Rg.range(-25, 25), -Rg.range(30, 80), Rg.range(0.1, 0.19), Rg.pick([C[6], C[5], C[4]]), Rg.range(1, 1.6));
  // 光芒：角度在十字附近随机偏一点，长短不一
  const rays = [[-Math.PI / 2, 13], [Math.PI / 2, 7], [0, 9], [Math.PI, 6]].map(([a, l]) => [a + Rg.range(-0.18, 0.18), l * Rg.range(0.85, 1.15)]);
  const arcs = [[-2.6, -1.7], [-1.2, -0.3], [0.5, 1.4], [2.0, 2.7]].map(([a0, a1]) => [a0 + Rg.range(-0.2, 0.2), a1 + Rg.range(-0.25, 0.1)]).filter(() => Rg.chance(0.8));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      const pop = 1 - clamp(t / 0.12);
      if (pop > 0) {
        for (const [a, l0] of rays) {
          const l = l0 * (0.6 + 0.4 * ease.outBack(clamp(t / 0.03 + 0.3))) * pop, dx = Math.cos(a), dy = Math.sin(a);
          for (let d = 0; d <= l; d += 0.5) p.px(dx * d, dy * d, d < l * 0.2 ? C[t < 0.04 ? 6 : 4] : d < l * 0.6 ? C[4] : C[3]);
        }
        const r = 3.5 * pop + 1;
        p.poly([[0, -r], [r * 0.8, 0], [0, r], [-r * 0.8, 0]], C[4]);
        if (t < 0.05) p.px(0, 0, C[6]);   // 白只在核心一点
      }
      const ar = 4 + 9 * ease.outQuart(clamp(t / 0.15)), ak = 1 - clamp((t - 0.03) / 0.15);
      if (ak > 0) for (const [a0, a1] of arcs) p.arc(0, 0, ar, ak > 0.5 ? 1.5 : 1, a0, a1, C[ak > 0.55 ? 4 : 3]);
      p.glow(0, 0, 9, C[4], 0.28 * pop);
      ps.draw(p);
    },
  };
}
