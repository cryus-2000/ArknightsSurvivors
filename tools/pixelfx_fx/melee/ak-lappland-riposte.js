// 拉普兰德「日晷·回敬」反斩（docs/229 §7，替 rage2 里放大 2.3 倍的 fx_lappland_slash）。1x，原点 = 帧中心 = 她前方 along 0.5 处，正右为出手方向。
// 双剑两道刀弧一先一后：第一道贴着判定半径 × 0.85、厚，第二道晚 0.04 s、半径小一截、薄，两道起止角也不同（不等距）。
// 首帧刃口白热，随后冷却成钢灰；刃头溅出几点冷白火星。0.3 s 收尽。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lappland riposte",
  desc: "Twin-sword counter cut: two crescents one after the other, at different radii and spans, white-hot edges cooling to steel grey, a few cold sparks off the heads.",
  tags: ["melee", "slash", "twin", "one-shot"],
  size: [64, 112],
  origin: [32, 56],
  duration: 0.32,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: OP.lappland,
    half: 32.5,      // 帧中心到她的距离（1x）：回敬半径 130 × along 0.5 / 2
    radius: 55,      // 第一道刀弧半径（1x）：130 × 0.85 / 2
    seed: 9,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), cx = -o.half;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  const cuts = [
    { R: o.radius, a0: -0.88, a1: 0.8, W: 8, t0: 0, sd: o.seed },
    { R: o.radius * 0.8, a0: 0.7, a1: -0.62, W: 5, t0: 0.04, sd: o.seed + 13 },   // 反方向回斩
  ];
  for (const c of cuts) {
    const hx = cx + Math.cos(c.a1) * c.R, hy = Math.sin(c.a1) * c.R;
    lights.add(hx, hy, 14, C[5], 0.45, 0.14);
    for (let i = 0; i < 4; i++) {
      const tg = Math.sign(c.a1 - c.a0), a = c.a1 + tg * Math.PI / 2 + Rg.range(-0.5, 0.5), sp = Rg.range(60, 130);
      ps.spawn(P.SPARK, hx, hy, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.06, 0.14), 0, 1, c.t0);
    }
  }
  let t = 0;
  function cut(p, c) {
    const u = t - c.t0;
    if (u < 0) return;
    const sweep = ease.outExpo(clamp((u + 0.03) / 0.06)), tail = smooth(0.05, 0.2, u), cool = clamp(u / 0.15);
    const lo = Math.min(c.a0, c.a1), dir = Math.sign(c.a1 - c.a0), span = Math.abs(c.a1 - c.a0);
    if (sweep - tail < 0.02) return;
    const W = c.W * (1 - 0.5 * tail);
    for (let y = -55.5; y <= 55.5; y++)
      for (let x = -31.5; x <= 31.5; x++) {
        const dx = x - cx, ang = Math.atan2(y, dx);
        if (ang < lo || ang > lo + span) continue;
        const v = (dir > 0 ? ang - c.a0 : c.a0 - ang) / span;   // 0 起刀 → 1 刃头
        if (v < tail || v > sweep) continue;
        const k = (v - tail) / Math.max(sweep - tail, 0.01);
        const rim = c.R + 1.4 * noise(ang * 12, c.sd) + 0.7 * noise(ang * 29, c.sd + 3);
        const w = W * Math.pow(Math.sin(Math.PI * Math.min(1, k * 0.6 + 0.08)), 1.1) + 0.6, q = (rim - Math.hypot(dx, y)) / w;
        if (q < 0 || q > 1) continue;
        const ci = q < 0.2 && u < 0.05 ? 6 : clamp(Math.round(5.5 - q * 4.5 - cool * 2.4 - (1 - k) * 1.5), 0, 5);
        if (q < 0.5) p.px(x, y, C[ci]);
        else p.blend(x, y, C[ci], 1.3 - q);
      }
  }
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      for (const c of cuts) cut(p, c);
      ps.draw(p);
      lights.draw(p);
    },
  };
}
