// 艾丽妮二技能「碎潮」锥形斩（docs/229 §9 D 组）：俯视圆弧，圆心 = 艾丽妮，正右为出手方向，游戏里按瞄准方向旋转。
// 细剑的刀光：比斯卡蒂的大剑薄、快，白热刃口冷却成玫瑰色，刀头甩出光屑，刀停处一点星芒。
// The crescent recipe is adapted from Sprite Fusion's open-source slash
// (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Irene shattertide",
  desc: "Top-down rapier cleave across a 90 degree cone: a thin ragged crescent flashes white, cools to rose, flings glinting motes off its edge and ends in a small star at the tip.",
  tags: ["melee", "slash", "rapier", "topdown", "one-shot"],
  size: [192, 176],
  origin: [96, 88],
  duration: 0.35,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.irene],
    radius: 84,       // 1x 像素：判定半径 199 × 0.85 ÷ 2
    span: 1.75,       // 弧度：判定 ±0.8 rad 再收一点
    seed: 5,
  },
};

const onArc = (s, r, a) => [Math.cos(a) * r, Math.sin(a) * r];

function crescent(p, s, ta, L, W, age) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, span = Math.abs(L), B = s.R + 3;
  p.shade(-B, -B, B, B, (x, y, out) => {
    const r = Math.hypot(x, y), ang = Math.atan2(y, x);
    const jag = 1.6 * noise(ang * 11, s.seed) + 0.9 * noise(ang * 29, s.seed + 7);   // 不等距的刃口毛边
    const Rr = s.R + jag * (0.3 + age);
    if (r > Rr + 0.5 || r < s.R - W - 1) return;
    let u = (ang - ta) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 2.2)), 0.6);
    if (w < 0.35) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    const hot = age < 0.1 ? 3 : 0;   // 第一帧整条爆亮
    const ci = q < 0.18 && age < 0.2 ? 0 : Math.round(q * (n - 1) * 0.75 + age * 4 - v * 0.6 + 1.6 - hot);
    out.c = R[n - 1 - clamp(ci, 0, n - 1)];
    out.a = Math.min(1, v / 0.3) * (q > 0.75 ? 0.75 : 1);
  });
  for (let u = 0; u <= span; u += 0.3) {
    const [x, y] = onArc(s, s.R - W * 0.4, ta + u);
    p.glow(x, y, 5 + W * 0.6, R[n - 3], 0.16 * (1 - age) * (u / span));
  }
}

function drawSlash(p, s, t) {
  const u = t - s.t0;
  if (u < 0) return;
  const span = s.a1 - s.a0, head = ease.outExpo(clamp(u / s.sweep)), tail = smooth(s.sweep + s.hold, s.sweep + s.hold + s.trail, u);
  const age = clamp(u / (s.sweep + s.hold + s.trail));
  if (tail < 1) crescent(p, s, s.a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.5), age);
}

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[3]] }), lights = new Lights();
  const R0 = o.radius, a0 = -o.span / 2, a1 = o.span / 2;
  const A = { seed: o.seed, R: R0, a0, a1, W: 11, t0: 0, sweep: 0.05, hold: 0.04, trail: 0.22, ramp: C };
  // 内侧一道细的回光：短、偏后，像剑身反光
  const E = { ...A, seed: o.seed + 3, R: R0 * 0.8, W: 3, a0: a0 + o.span * 0.2, a1: a1 - o.span * 0.08, t0: 0.03, hold: 0.02, trail: 0.18, ramp: C.slice(0, 7) };
  const tip = onArc(A, A.R - 3, a1);
  let t = 0.025, passed = 0, landed = false;
  return {
    update(dt) {
      t += dt;
      const head = ease.outExpo(clamp(t / A.sweep));
      while (passed < head && passed < 1) {
        const a = a0 + o.span * passed, [x, y] = onArc(A, A.R - Rg.range(0, 4), a);
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(70, 190);
        ps.spawn(P.SPARK, x, y, (tx * 0.7 + nx * 0.7) * sp, (ty * 0.7 + ny * 0.7) * sp, Rg.range(0.08, 0.2));
        passed += Rg.range(0.07, 0.16);
      }
      if (!landed && t >= A.sweep) {
        landed = true;
        const ta = Math.atan2(Math.cos(a1), -Math.sin(a1));
        for (let i = 0; i < 8; i++) {
          const a = ta + Rg.range(-0.8, 0.8), sp = Rg.range(80, 220);
          ps.spawn(P.SPARK, tip[0], tip[1], Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.08, 0.22));
        }
        // 刃口外缘散几粒光屑：不等距
        for (let a = a0 + 0.12; a < a1; a += Rg.range(0.14, 0.34)) {
          const [x, y] = onArc(A, A.R + Rg.range(0, 2), a), sp = Rg.range(20, 60);
          ps.spawn(P.MOTE, x, y, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.15, 0.3), C[5 + Rg.int(0, 2)], Rg.range(0.5, 0.9), Rg.range(0, 0.05));
        }
        lights.add(tip[0], tip[1], 22, C[5], 0.4, 0.2);
      }
      ps.update(dt);
      lights.update(dt);
    },
    draw(p) {
      drawSlash(p, E, t);
      drawSlash(p, A, t);
      if (t < 0.2) {
        const [x, y] = onArc(A, A.R - 3, A.a0 + o.span * ease.outExpo(clamp(t / A.sweep)));
        p.glow(x, y, 20, C[5], 0.3 * (1 - t / 0.2));
      }
      const g = t - A.sweep * 0.7;
      if (g > 0 && g < 0.18) sparkle(p, tip[0], tip[1], 7 * ease.outBack(Math.min(1, g / 0.05)) * (1 - g / 0.18), C[7], C[5], 0.5);
      ps.draw(p);
      lights.draw(p);
    },
  };
}
