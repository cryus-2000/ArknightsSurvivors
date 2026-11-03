// 流明成长「灯塔守望·回光」光脉冲（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底（圆形判定圆心）。
// 判定：半径 r = watch2_r（1x = watch2_r / 2），沐雨时和灯火不灭期间每秒一圈，命中减速。原作无（本作成长）。
// 用户 11-04 否外扩光环：不做「一圈往外推的环」，改成判定半径上 4–5 段弧原地亮一下再熄，弧上各挂一颗被照亮的小十字；中心一下竖直细光。
// 每秒都会放，要克制：0.35 s 收完。只用钢蓝 7 阶。分层：core = 边弧、十字、竖光；deco = 弧上的淡光。
import { Rng, fit, clamp, smooth, noise, TAU } from "../../core/index.js";
import { OP, jitterAngles } from "../house.js";

export const meta = {
  name: "Lumen lighthouse pulse unleashed",
  desc: "Four or five broken arcs flash in place on the pulse radius with small glints on them, then go out.",
  tags: ["light", "pulse", "one-shot"],
  size: [136, 110],
  origin: [68, 70],
  duration: 0.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", r: 60, seed: 3 },
};

const SY = 0.5;

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, Rg = new Rng(o.seed);
  const segs = jitterAngles(Rg, Rg.int(4, 5), 0, TAU, 0.35).map((c) => ({ c, half: Rg.range(0.2, 0.32), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) }));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const ea = 1 - smooth(0.08, 0.35, t);
      if (ea <= 0) return;
      for (const sg of segs) {
        if (deco) p.glow(Math.cos(sg.c) * R, Math.sin(sg.c) * R * SY, 6, C[4], 0.18 * ea);
        if (!core) continue;
        for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.45 / R) {
          const e = 1 - Math.abs(an - sg.c) / sg.half, n = noise(an * 3 + sg.s, o.seed);
          p.dot(Math.cos(an) * R, Math.sin(an) * R * SY, t < 0.05 ? C[6] : n > 0.6 ? C[6] : C[5], ea * smooth(0, 0.35, e));
        }
        const ga = sg.c + sg.g * sg.half, x = Math.cos(ga) * R, y = Math.sin(ga) * R * SY - 3, m = Math.round(2.5 * ea);
        for (let d = 1; d <= m; d++) { p.px(x + d, y, C[5]); p.px(x - d, y, C[5]); p.px(x, y + d, C[5]); p.px(x, y - d, C[5]); }
        if (m > 0) p.px(x, y, C[6]);
      }
      if (core && t < 0.2) for (let y = 0; y <= 22; y += 1) p.blend(0, -y, C[5], (1 - t / 0.2) * (1 - y / 26));
    },
  };
}
