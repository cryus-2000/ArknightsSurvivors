// 水月「深蓝之籽」水母蛰刺命中（精一第 3 批 jelly sting，替换 fx_mizuki_jelly_sting）：@2x 帧条，原点 = 命中点（敌人身上半个半径处），游戏按 PX 放（1:1）。
// 几根长短不一的刺丝从四面不等角地扎进命中点，首帧白闪，随后刺点泛起一团薰衣草色的毒雾、刺丝缩回并散成小点。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Mizuki jelly sting",
  desc: "Uneven stinging threads stab into the hit point from odd angles, a white flash, then a lavender venom puff blooms and the threads recoil into specks.",
  tags: ["impact", "sting", "jellyfish", "topdown", "one-shot"],
  size: [56, 56],
  origin: [28, 28],
  duration: 0.35,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.mizuki],
    seed: 6,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]], haze: C[5] });
  const th = [];
  for (let a = Rg.range(0, 1); a < TAU - 0.4; a += Rg.range(0.9, 1.8)) th.push({ a, L: Rg.range(12, 22), bend: Rg.range(-4, 4), d: Rg.range(0, 0.03) });
  const STAB = 0.06;
  let t = 0, popped = false;

  return {
    update(dt) {
      t += dt;
      if (!popped && t >= STAB) {
        popped = true;
        for (let i = 0; i < 4; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(15, 40);
          ps.spawn(P.VAPOUR, Rg.range(-2, 2), Rg.range(-2, 2), Math.cos(a) * sp, Math.sin(a) * sp - 8, Rg.range(0.15, 0.25), C[Rg.int(4, 6)], Rg.range(3, 5));
        }
        for (let i = 0; i < 4; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(40, 90);
          ps.spawn(P.FLAKE, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.1, 0.2), C[Rg.int(5, 7)], 1.5);
        }
      }
      ps.update(dt);
    },
    draw(p) {
      for (const s of th) {
        const u = t - s.d;
        if (u < 0) continue;
        const inn = ease.outQuart(clamp((u + 0.02) / STAB)), back = smooth(0.1, 0.22, u);   // 扎进去，再缩回
        const r0 = s.L * (1 - inn * 0.85) + s.L * back * 0.6, r1 = s.L + s.L * back * 0.3;
        if (r1 - r0 < 1 || back >= 1) continue;
        const nx = Math.cos(s.a), ny = Math.sin(s.a);
        for (let r = r0; r <= r1; r += 1) {
          const v = (r - r0) / (r1 - r0), bow = s.bend * Math.sin(Math.PI * (r / s.L)) * 0.5;
          const x = nx * r - ny * bow, y = ny * r + nx * bow;
          const c = C[clamp(Math.round(7 - v * 3 - back * 3 - (t > 0.05 ? 1 : 0)), 2, 7)];
          if (v > 0.6) p.blend(Math.round(x), Math.round(y), c, 0.7); else p.px(Math.round(x), Math.round(y), c);
        }
      }
      if (t < 0.1) {
        const k = t < 0.05 ? 1 : 0.5;
        p.disc(0, 0, 3 * k + 0.6, C[t < 0.05 ? 7 : 6], 1);   // 刺点一闪：小而实，不是一团
        for (const s of th) p.px(Math.round(Math.cos(s.a) * 4 * k), Math.round(Math.sin(s.a) * 4 * k), C[6]);
      }
      ps.draw(p);
    },
  };
}
