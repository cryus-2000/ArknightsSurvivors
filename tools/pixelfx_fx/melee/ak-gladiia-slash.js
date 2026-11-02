// 歌蕾蒂娅「锚尖斩」（成长节点 slash，docs/229 §3 普攻档）：@2x 密度（1 像素 = 1 世界像素），正右为出手方向，游戏里按瞄准方向旋转。
// 原点 = 身前 along 0.5 × 判定半径（160）处；歌蕾蒂娅在原点左边 80 px（cx）。刀弧半径 = 判定半径 × 0.85（docs/229 §2.8），张角 = 判定半角 65° × 2。
// 和拉普兰德的细双刃不同：一道厚重的戟刃水弧，刃口白、刃身是半透明的深海水体，外缘按噪声卷起浪沫，刀停处甩出一串大小不一的水珠。
import { Particles, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { OP, FPS, REACH, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Gladiia tide slash",
  desc: "A heavy halberd arc of deep-sea water: white edge, translucent blue body, a ragged foam lip, and a spray of uneven droplets where the blade stops.",
  tags: ["melee", "slash", "water", "topdown", "one-shot"],
  size: [136, 280],
  origin: [68, 140],
  duration: 0.30,   // 主体 + 余韵
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: [...OP.gladiia],
    cx: -80,
    radius: 160 * REACH.sweep,
    span: 2.27,       // 判定半角 65° × 2
    seed: 4,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius, cx = o.cx;
  const a0 = -o.span / 2, span = o.span;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const SWEEP = 0.05, HOLD = 0.02, TRAIL = 0.07, W = 18;
  let t = 0.01, passed = 0, sprayed = false;

  function blade(p) {
    const head = ease.outExpo(clamp(t / SWEEP)), tail = smooth(SWEEP + HOLD, SWEEP + HOLD + TRAIL, t);
    if (tail >= 1) return;
    const age = clamp(t / (SWEEP + HOLD + TRAIL)), ta = a0 + span * tail, L = span * (head - tail), Wn = W * (1 - tail * 0.6);
    if (L < 0.02) return;
    const B = R + 6;
    p.shade(cx - B, -B, cx + B, B, (x, y, out) => {
      const dx = x - cx, r = Math.hypot(dx, y), ang = Math.atan2(y, dx);
      const lip = 2.2 * noise(ang * 9, o.seed) + 1.2 * noise(ang * 23, o.seed + 7);   // 外缘浪沫起伏（噪声，非周期）
      const Rr = R + lip * (0.4 + age * 1.6);
      if (r > Rr + 0.5 || r < R - Wn - 2) return;
      let u = ang - ta;
      if (u < 0 || u > L) return;
      const v = u / L, w = Wn * Math.pow(Math.sin(Math.PI * Math.pow(v, 1.8)), 0.55);
      if (w < 0.4) return;
      const q = (Rr - r) / w;
      if (q < 0 || q > 1) return;
      const hot = t < 0.045 ? 0.8 : 0;                    // 首帧只让刃口芯爆白（白只在核心，近白 ≤ 12%）
      const ci = Math.round(q * 5.4 + 0.5 + age * 4.2 - v * 1.2 - hot);
      const c = C[7 - clamp(ci, 0, 6)];
      if (q > 0.5) p.blend(x, y, c, 0.7);   // 刃身往里是真半透明水体（shade 的 out.a 是抖动，不用）
      else out.c = c;
    });
  }

  // 余韵（docs/229 §2.5，普攻 ≤ 0.15 s）：主体收尾后沿弧留几粒稀疏残光，alpha ≤ TAIL_ALPHA，往外飘散淡掉
  const Rt = new Rng(o.seed + 99), res = [];
  for (let v = Rt.range(0, 0.12); v < 1; v += Rt.range(0.1, 0.22)) res.push({ v, dr: Rt.range(-W * 0.6, 2), d: Rt.range(0, 0.04), out: Rt.range(3, 9) });
  const TAIL0 = SWEEP + HOLD + TRAIL * 0.6;
  function tail(p) {
    for (const r of res) {
      const u = (t - TAIL0 - r.d) / DUR.basicTail;
      if (u < 0 || u >= 1) continue;
      const a = a0 + span * r.v, rr = R + r.dr + r.out * u;
      p.blend(Math.round(cx + Math.cos(a) * rr), Math.round(Math.sin(a) * rr), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  // 光晕（light 层，导出成 _glow 条在加色层叠画）：跟着刃头，随冷却收
  function halo(p) {
    const k = 1 - clamp(t / 0.12);
    if (k <= 0) return;
    const a = a0 + span * ease.outExpo(clamp(t / SWEEP));
    p.glow(cx + Math.cos(a) * (R - 4), Math.sin(a) * (R - 4), 18, C[5], 0.9 * k);
  }

  return {
    update(dt) {
      t += dt;
      const head = ease.outExpo(clamp(t / SWEEP));
      while (passed < head && passed < 1) {
        const a = a0 + span * passed, x = cx + Math.cos(a) * (R + 2), y = Math.sin(a) * (R + 2);
        if (Rg.chance(0.7)) {
          const sp = Rg.range(70, 170), da = a + Rg.range(-0.3, 0.6);
          ps.spawn(Rg.chance(0.5) ? P.SPARK : P.FLAKE, x, y, Math.cos(da) * sp, Math.sin(da) * sp, Rg.range(0.07, 0.14), C[Rg.int(5, 7)], Rg.range(1.5, 3));
        }
        passed += Rg.range(0.09, 0.2);
      }
      if (!sprayed && t >= SWEEP) {
        sprayed = true;
        const a = a0 + span, x = cx + Math.cos(a) * R, y = Math.sin(a) * R;
        for (let i = 0; i < 6; i++) {
          const da = a + Math.PI / 2 + Rg.range(-0.9, 0.4), sp = Rg.range(90, 240);
          ps.spawn(Rg.chance(0.4) ? P.FLAKE : P.SPARK, x + Rg.range(-3, 3), y + Rg.range(-3, 3), Math.cos(da) * sp, Math.sin(da) * sp, Rg.range(0.06, 0.13), C[Rg.int(5, 7)], Rg.range(1.5, 3));
        }
      }
      ps.update(dt);
    },
    draw(p) {
      blade(p);
      halo(p);
      tail(p);
      ps.draw(p);
    },
  };
}
