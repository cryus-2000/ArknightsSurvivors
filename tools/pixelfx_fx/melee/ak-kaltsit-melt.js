// 凯尔希 · Mon3tr S2「熔毁」斩（替换 fx_mon3tr_melt_slash，旧条 scale_r 0.0275 × 116 = 每 1x 像素 3.2 世界像素）：@2x 帧条，原点 = 斩痕中心（side_x 0.38），
// 游戏 scale_r 0.01724：判定半径 93 × r_mult 1.25 = 116 时每个 1x 像素 2 世界像素。一道薄而烫的熔红弧：刃口白热、往里冷却成暗血红，刃停处迸出几粒熔渣。
// 红色避开敌方危险色 0.92–0.98：色相取 0.99–0.03，高光往橙偏（docs/229 §2.2）。
import { Particles, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { FPS } from "../house.js";

export const meta = {
  name: "Mon3tr melt slash",
  desc: "A thin, searing arc: white-hot edge cooling inward to dark blood red, with a few molten flecks spat where it stops.",
  tags: ["melee", "slash", "fire", "topdown", "one-shot"],
  size: [120, 140],
  origin: [60, 70],
  duration: 0.17,
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: ["#06142a", "#1c0807", "#3f0d0b", "#6e1513", "#a8241f", "#e0553a", "#ffc9b0", "#ffffff"],
    cx: -36,
    radius: 62,
    span: 1.9,
    seed: 12,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius, cx = o.cx;
  const a0 = -o.span / 2, span = o.span;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const SWEEP = 0.05, HOLD = 0.02, TRAIL = 0.07, W = 9;
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
      const hot = t < 0.045 ? 1.6 : 0;                    // 第 1 帧整条爆亮（不烤 p.glow：加色光会让 32 色量化出抖动、包体涨 15%）
      const ci = Math.round(q * 5.4 + 0.5 + age * 4.2 - v * 1.2 - hot);
      const c = C[7 - clamp(ci, 0, 6)];
      if (q > 0.5) p.blend(x, y, c, 0.7);   // 刃身往里半透明（shade 的 out.a 是抖动，不用）
      else out.c = c;
    });
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
      ps.draw(p);
    },
  };
}
