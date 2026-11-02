// 塞雷娅晶柱（D 组）：@2x 密度。mode 0 = 拔起（5 帧 @20，原点 = 底边中点，替换 fx_saria_pillar_rise）；
// mode 1 = 碎裂（原点 = 柱身中段，替换 fx_saria_pillar_break）。一根琥珀钙晶柱，侧面带两根小晶；碎裂时首帧爆亮，碎片不等速往外甩、落地。
import { Bits, B, Particles, P, Rng, fit, clamp, ease, crystal, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria pillar",
  desc: "An amber calcite pillar: mode 0 thrusts up from the floor with a bright tip; mode 1 shatters with a one-frame flash and shards flung out at uneven speeds.",
  tags: ["earth", "crystal", "one-shot"],
  size: [72, 72],
  origin: [36, 64],
  duration: 0.35,
  loop: false,
  fps: 20,
  bg: "ground",
  options: { palette: ["#06142a", "#3a2a1c", OP.saria[1], OP.saria[2], OP.saria[3], "#ffe6c0", "#f4f8ff", "#ffffff"], mode: 0, seed: 4 },
};

export function create(o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed), brk = +o.mode === 1;
  const bits = new Bits({ ground: () => 0 }), ps = new Particles({ rng: R, ground: () => 0, sparks: [C[7], C[6], C[5], C[3]] });
  if (brk) {
    for (let i = 0; i < 9; i++) {
      const a = R.range(0, TAU), sp = R.range(50, 160);
      bits.add({ kind: B.SHARD, x: R.range(-4, 4), y: -30 + R.range(-12, 12), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 60, a: R.range(0, 3), va: R.range(-14, 14), s: R.range(1.5, 3.5), c: C[R.int(3, 6)], g: 0.6, life: R.range(0.2, 0.32) });
    }
    for (let i = 0; i < 5; i++) { const a = R.range(0, TAU); ps.spawn(P.SPARK, 0, -30, Math.cos(a) * R.range(80, 180), Math.sin(a) * R.range(80, 180), R.range(0.06, 0.14)); }
    for (let i = 0; i < 3; i++) ps.spawn(P.DUST, R.range(-6, 6), -2, R.range(-20, 20), -8, R.range(0.2, 0.3), C[2], R.range(3, 5));
  }
  const side = [{ x: R.range(-8, -6), h: R.range(10, 14), w: 6, lean: -3 }, { x: R.range(5, 8), h: R.range(7, 11), w: 5, lean: 3 }];
  let t = 0;
  return {
    update(dt) { t += dt; bits.update(dt); ps.update(dt); },
    draw(p) {
      if (!brk) {
        const g = ease.outBack(clamp((t + 0.02) / 0.2)), hot = t < 0.03;
        if (t >= 0.25) return;
        for (const s of side) crystal(p, s.x, 0, s.h * g, s.w, s.lean, C.slice(0, 7));
        crystal(p, 0, 0, 52 * g, 13, R.range(-1, 1), hot ? C.slice(1, 8) : C.slice(0, 6), { white: hot, glint: g > 0.9 ? 0.8 : -1 });
        if (t < 0.1) for (let i = 0; i < 4; i++) p.px(R.range(-10, 10), R.range(-1, 1), C[R.int(3, 6)]);
        return;
      }
      // 柱身中段（y -30）爆亮：首帧白的不规整晶块，下一帧缩成琥珀
      if (t < 0.03) { crystal(p, 0, -14, 34, 12, 0, C.slice(1, 8), { white: true }); p.glow(0, -30, 18, C[5], 0.35); }
      else if (t < 0.1) crystal(p, 0, -22, 18, 8, R.range(-3, 3), C.slice(0, 6));
      bits.draw(p); ps.draw(p);
    },
  };
}
