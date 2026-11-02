// 斯卡蒂大剑横扫（docs/228 §7 试点）：俯视圆弧，圆心 = 斯卡蒂，正右为出手方向，游戏里按瞄准方向旋转。
// The crescent, echo and trace recipe is adapted from Sprite Fusion's open-source slash
// (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Skadi sweep",
  desc: "Top-down greatsword sweep, 200 degrees round the wielder: a ragged deep-sea crescent flashes white, cools to abyss blue and flings brine and foam off its edge.",
  tags: ["melee", "slash", "greatsword", "water", "topdown", "one-shot"],
  size: [200, 200],
  origin: [100, 100],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    radius: 74,
    span: 3.5,        // 弧度：200°
    heavy: 0,         // 1 = 跃浪击：更厚、正前方掀起水花
    seed: 3,
  },
};

const onArc = (s, r, a) => [s.cx + Math.cos(a) * r, s.cy + Math.sin(a) * r];

// 刀光主体：前缘最厚、尾部细成一根线；外缘白、往里逐级变深；随年龄和往尾部冷却
function crescent(p, s, ta, L, W, age) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, dir = Math.sign(L), span = Math.abs(L), B = s.R + 2;
  p.shade(s.cx - B, s.cy - B, s.cx + B, s.cy + B, (x, y, out) => {
    const dx = x - s.cx, dy = y - s.cy, r = Math.hypot(dx, dy);
    const ang = Math.atan2(dy, dx), jag = 2.2 * noise(ang * 9, s.seed) + 1.1 * noise(ang * 23, s.seed + 7);   // 不等距的水口
    const Rr = s.R + jag * (0.4 + age);
    if (r > Rr + 0.5 || r < s.R - W - 1) return;
    let u = (dir * (ang - ta)) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 2.4)), 0.55);
    if (w < 0.35) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    const hot = age < 0.12 ? 2.5 : 0;   // 出刀第一帧整条爆亮，随后冷却
    const ci = q < 0.16 && age < 0.45 ? 0 : Math.round(q * (n - 1) * 0.8 + age * 2.6 - v * 0.9 + 0.5 - hot);
    out.c = R[n - 1 - clamp(ci, 0, n - 1)];
    out.a = Math.min(1, v / 0.35);
  });
  for (let u = 0; u <= span; u += 0.25) {
    const [x, y] = onArc(s, s.R - W * 0.45, ta + dir * u);
    p.glow(x, y, 3 + W * 0.4, R[n - 4], 0.14 * (1 - age) * (u / span));   // 帧条里只烤小光晕（docs/229 §2.7），大光交给 optical
  }
}

function drawSlash(p, s, t) {
  const u = t - s.t0;
  if (u < 0) return;
  const span = s.a1 - s.a0, head = ease.outExpo(clamp(u / s.sweep)), tail = smooth(s.sweep + s.hold, s.sweep + s.hold + s.trail, u);
  const age = clamp(u / (s.sweep + s.hold + s.trail));
  if (tail < 1) crescent(p, s, s.a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.6), age);
  // 刀走过的地方留一道虚线残痕
  const th = 0.65 * (1 - clamp((u - s.sweep - s.hold) / (s.trail + 0.15)));
  if (tail > 0.02 && th > 0)
    for (let k = 0; k <= tail; k += 0.7 / (Math.abs(span) * s.R)) {
      const [x, y] = onArc(s, s.R - 0.5, s.a0 + span * k);
      p.dot(x, y, s.ramp[2], th * (0.35 + 0.65 * k));
    }
}

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), heavy = +o.heavy > 0;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, haze: C[4] }), lights = new Lights();
  const R0 = o.radius, a0 = -o.span / 2, a1 = o.span / 2;
  const A = { seed: o.seed, cx: 0, cy: 0, R: R0, a0, a1, W: heavy ? 22 : 16, t0: 0, sweep: heavy ? 0.08 : 0.065, hold: 0.05, trail: 0.3, ramp: C };
  const E = { ...A, R: R0 * 0.76, W: heavy ? 8 : 6, a0: a0 + o.span * 0.12, a1: a1 - o.span * 0.04, t0: 0.02, hold: 0.03, trail: 0.24, ramp: C.slice(0, 7) };
  const tip = onArc(A, A.R - A.W * 0.3, a1);
  let t = 0.03, passed = 0, landed = false;   // 从挥到一半开始：20 fps 下第 0 帧就有刀
  return {
    update(dt) {
      t += dt;
      // 刀头经过时沿切线 + 外抛甩出海水
      const head = ease.outExpo(clamp(t / A.sweep));
      while (passed < head && passed < 1) {
        const a = a0 + o.span * passed, [x, y] = onArc(A, A.R - Rg.range(0, A.W * 0.6), a);
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(60, 170);
        ps.spawn(P.MOTE, x, y, (tx * 0.8 + nx * 0.6) * sp, (ty * 0.8 + ny * 0.6) * sp, Rg.range(0.18, 0.4), C[5 + Rg.int(0, 2)], Rg.range(0.5, 0.9));
        if (Rg.chance(0.45)) ps.spawn(P.VAPOUR, x + nx * 3, y + ny * 3, nx * 25 + tx * 20, ny * 25 + ty * 20, Rg.range(0.25, 0.45), C[4], Rg.range(2, 4));
        passed += 0.045;
      }
      if (!landed && t >= A.sweep) {
        landed = true;
        // 刀停处：一簇浪沫 + 水珠
        const ta = Math.atan2(Math.cos(a1), -Math.sin(a1));
        for (let i = 0; i < 12; i++) {
          const a = ta + Rg.range(-0.7, 0.7), sp = Rg.range(90, 240);
          ps.spawn(P.MOTE, tip[0], tip[1], Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.15, 0.35), C[6 + Rg.int(0, 1)], 0.8);
        }
        for (let i = 0; i < 5; i++) ps.spawn(P.VAPOUR, tip[0] + Rg.range(-4, 4), tip[1] + Rg.range(-4, 4), Rg.range(-20, 20), Rg.range(-20, 20), Rg.range(0.3, 0.5), C[5], Rg.range(3, 5));
        lights.add(tip[0], tip[1], 16, C[5], 0.3, 0.2);
        // 整条弧外缘碎成浪沫：不等距、大小不一
        for (let a = a0 + 0.15; a < a1; a += Rg.range(0.12, 0.3)) {
          const [x, y] = onArc(A, A.R + Rg.range(0, 3), a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(20, 70);
          ps.spawn(P.VAPOUR, x, y, nx * sp, ny * sp, Rg.range(0.3, 0.55), C[5], Rg.range(2, 4.5), Rg.range(0, 0.05));
          if (Rg.chance(0.6)) ps.spawn(P.MOTE, x, y, nx * sp * 2.2, ny * sp * 2.2, Rg.range(0.2, 0.4), C[7], Rg.range(0.6, 1), Rg.range(0, 0.06));
        }
        if (heavy) {
          // 跃浪击：正前方水花冠
          const fx = R0 * 0.62;
          lights.add(fx, 0, 24, C[5], 0.3, 0.22);
          for (let i = 0; i < 26; i++) {
            const a = Rg.range(-Math.PI, Math.PI), sp = Rg.range(70, 230);
            ps.spawn(P.MOTE, fx, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.45), C[5 + Rg.int(0, 2)], Rg.range(0.6, 1));
          }
          for (let i = 0; i < 5; i++) {
            const a = Rg.range(-Math.PI, Math.PI), d = Rg.range(2, 12);
            ps.spawn(P.VAPOUR, fx + Math.cos(a) * d, Math.sin(a) * d, Math.cos(a) * 30, Math.sin(a) * 30, Rg.range(0.35, 0.55), C[5], Rg.range(4, 7));
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    draw(p) {
      ps.draw(p, "back");
      drawSlash(p, E, t);
      drawSlash(p, A, t);
      // 刀头一路带光
      if (t < 0.3) {
        const [x, y] = onArc(A, A.R - 5, A.a0 + o.span * ease.outExpo(clamp(t / A.sweep)));
        p.glow(x, y, 18, C[4], 0.28 * (1 - t / 0.3));
      }
      const g = t - A.sweep * 0.6;
      if (g > 0 && g < 0.2) sparkle(p, tip[0], tip[1], (heavy ? 12 : 9) * ease.outBack(Math.min(1, g / 0.05)) * (1 - g / 0.2), C[7], C[4], 0.6);
      if (heavy && t > A.sweep && t < A.sweep + 0.1) {
        const k = 1 - (t - A.sweep) / 0.1;
        p.disc(R0 * 0.62, 0, 10 * k + 4, C[7], 0.8 * k);
      }
      ps.draw(p, "front");
      lights.draw(p);
    },
  };
}
