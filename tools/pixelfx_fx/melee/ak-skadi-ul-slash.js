// 斯卡蒂「不加限制」大剑斩（claude/pixelfx-unleashed-skadi，开关 fx/px_unleashed）：俯视圆弧，圆心 = 斯卡蒂，正右为出手方向。
// span 选弧长：2.8（普攻 160°）/ 3.5（迅捷打击 200°）/ 6.28（涌潮悲歌全方向）；heavy = 跃浪击。
// 不设近白 / 色数 / 体积上限：两帧爆亮、强光、厚刀身、整条外缘甩浪、余韵（水雾 + 湿痕 + 浪沫慢慢沉下去）。
// The crescent / echo / trace recipe is adapted from Sprite Fusion's open-source slash
// (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Skadi slash unleashed",
  desc: "Top-down greatsword sweep with nothing held back: a thick white-hot deep-sea crescent, brine flung off its whole rim, foam and mist that linger and settle.",
  tags: ["melee", "slash", "greatsword", "water", "topdown", "one-shot"],
  size: [260, 260],
  origin: [130, 130],
  duration: 1.25,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#040c1c", "#08224a", "#0f4280", "#1a6cb4", "#34a8dc", "#7fe0f4", "#d4fbff", "#ffffff"],
    radius: 80,
    span: 3.5,
    heavy: 0,
    quick: 0,         // 1 = 余韵短（涌潮悲歌期间连续出手，长余韵会叠成一整个水泡）
    layer: "all",   // core / deco / all（分层导出时由 pixelfx_export.py 传）
    seed: 3,
  },
};

const onArc = (s, r, a) => [Math.cos(a) * r, Math.sin(a) * r];

function crescent(p, s, ta, L, W, age, hot, core, deco) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, dir = Math.sign(L), span = Math.abs(L), B = s.R + 4;
  if (core) p.shade(-B, -B, B, B, (x, y, out) => {
    const r = Math.hypot(x, y), ang = Math.atan2(y, x);
    const jag = 2.6 * noise(ang * 8, s.seed) + 1.4 * noise(ang * 21, s.seed + 7);
    const Rr = s.R + jag * (0.5 + age * 1.5);
    if (r > Rr + 0.5 || r < s.R - W - 2) return;
    let u = (dir * (ang - ta)) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 2.2)), 0.5);
    if (w < 0.4) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    const ci = q < 0.2 && age < 0.5 ? 0 : Math.round(q * (n - 1) * 0.75 + age * 2.8 - v * 1.1 + 0.3 - hot);
    out.c = R[n - 1 - clamp(ci, 0, n - 1)];
    out.a = q > 0.8 ? 0.7 : 1;   // 刀身内沿半透明（真透明，不抖动）
  });
  if (deco) for (let u = 0; u <= span; u += 0.18) {   // 刀身光晕归装饰层
    const [x, y] = onArc(s, s.R - W * 0.4, ta + dir * u);
    p.glow(x, y, (s.full ? 10 : 12) + W, R[n - 3], (s.full ? 0.28 : 0.36) * (1 - age) * (u / span) + (s.full ? 0.04 : 0.12) * hot);   // 光晕加强补回拆层后的亮度；全方向整圈不加（加了光晕会被读成第二道环）
  }
}

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), heavy = +o.heavy > 0, full = o.span > 6, quick = +o.quick > 0, LQ = quick ? 0.5 : 1;
  // 分层（docs/242 §8）：core = 刀弧 / 第 1 帧白热 / 爆点；deco = 光晕、甩出物、余韵。quick（队友版）只缩装饰的余韵，核心与队长版一样
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  const R0 = o.radius, span = full ? TAU * 1.04 : o.span, a0 = full ? -Math.PI : -span / 2, a1 = a0 + span;
  const SW = full ? 0.13 : heavy ? 0.09 : 0.07, W = heavy ? 30 : full ? 18 : 22;
  const A = { seed: o.seed, R: R0, W, ramp: C, full };
  const E = { seed: o.seed + 9, R: R0 * 0.72, W: W * 0.4, ramp: C.slice(0, 7) };
  let t = 0.02, passed = 0, landed = false;
  const tip = onArc(A, A.R - A.W * 0.3, a1);

  function drawArc(p, s, t0, hold, trail) {
    const u = t - t0;
    if (u < 0) return;
    const head = ease.outExpo(clamp(u / SW)), tail = smooth(SW + hold, SW + hold + trail, u), age = clamp(u / (SW + hold + trail));
    const hot = u < 0.09 ? 3.0 : u < 0.13 ? 0.3 : 0;   // 前 2 帧（20 fps）白热、第 3 帧起回落：保住 12:22 版的冲击力，又不连白 3 帧（docs/242 §9.3）
    if (tail < 1) crescent(p, s, a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.5), age, hot, core, deco);
  }
  return {
    update(dt) {
      t += dt;
      const head = ease.outExpo(clamp(t / SW));
      while (passed < head && passed < 1) {
        const a = a0 + span * passed, [x, y] = onArc(A, A.R - Rg.range(0, A.W * 0.5), a);
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a);
        for (let k = 0; k < (heavy ? 3 : 2); k++) {
          const sp = Rg.range(80, 260);
          ps.spawn(P.MOTE, x, y, (tx * 0.6 + nx * 0.9) * sp, (ty * 0.6 + ny * 0.9) * sp, Rg.range(0.25, 0.55), C[5 + Rg.int(0, 2)], Rg.range(0.7, 1.3));
        }
        if (Rg.chance(0.5)) ps.spawn(P.SPARK, x, y, nx * Rg.range(100, 240), ny * Rg.range(100, 240) - 60, Rg.range(0.3, 0.6));
        if (Rg.chance(0.3)) ps.spawn(P.VAPOUR, x + nx * 5, y + ny * 5, nx * 40 + tx * 25, ny * 40 + ty * 25, Rg.range(0.25, 0.45), C[5], Rg.range(2, 4));
        passed += (full ? 0.025 : 0.035) * Rg.range(0.4, 1.8);   // 步长随机：等距撒会排成一圈等距放射纹
      }
      if (!landed && t >= SW) {
        landed = true;
        lights.add(0, 0, R0 * 1.2, C[5], 0.6, 0.35);
        lights.add(tip[0], tip[1], 46, C[6], 0.9, 0.3);
        // 余韵：整条弧外缘碎成浪沫与水雾，慢慢沉下去
        for (let a = a0 + 0.1; a < a1; a += Rg.range(0.08, 0.2) / (quick ? 0.5 : 1)) {
          const [x, y] = onArc(A, A.R + Rg.range(-2, 5), a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(15, 60);
          ps.spawn(P.VAPOUR, x, y, nx * sp, ny * sp, Rg.range(0.5, 0.85) * LQ, C[4 + Rg.int(0, 1)], Rg.range(2.5, 5.5), Rg.range(0, 0.08));
          if (Rg.chance(0.35)) ps.spawn(P.STAR, x + Rg.range(-4, 4), y + Rg.range(-4, 4), nx * 6, ny * 6 - 4, Rg.range(0.35, 0.7) * LQ, C[6 + Rg.int(0, 1)], Rg.range(1, 2), Rg.range(0.05, 0.4) * LQ);   // 余韵里一闪一闪的水光
          if (Rg.chance(0.7)) ps.spawn(P.SPARK, x, y, nx * sp * 3, ny * sp * 3 - Rg.range(40, 140), Rg.range(0.35, 0.7) * LQ);
        }
        if (!full) {
          const ta = Math.atan2(Math.cos(a1), -Math.sin(a1));
          for (let i = 0; i < 18; i++) {
            const a = ta + Rg.range(-0.8, 0.8), sp = Rg.range(120, 320);
            ps.spawn(P.SPARK, tip[0], tip[1], Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.45));
          }
        }
        if (heavy) {
          const fx = R0 * 0.6;
          lights.add(fx, 0, 70, C[6], 1.0, 0.4);
          for (let i = 0; i < 46; i++) {
            const a = Rg.range(-Math.PI, Math.PI), sp = Rg.range(90, 300);
            ps.spawn(i % 3 ? P.MOTE : P.SPARK, fx, 0, Math.cos(a) * sp, Math.sin(a) * sp - 40, Rg.range(0.3, 0.7), C[5 + Rg.int(0, 2)], Rg.range(0.8, 1.4));
          }
          for (let i = 0; i < 14; i++) {
            const a = Rg.range(-Math.PI, Math.PI), d = Rg.range(2, 16);
            ps.spawn(P.VAPOUR, fx + Math.cos(a) * d, Math.sin(a) * d, Math.cos(a) * 40, Math.sin(a) * 40, Rg.range(0.6, 1.0), C[5], Rg.range(6, 10));
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (!full) drawArc(p, E, 0.025, 0.04, 0.3);   // 全方向时不画内弧（两道同心圈是被否的形状）
      drawArc(p, A, 0, 0.07, 0.4);
      if (deco && t < 0.32) {
        const [x, y] = onArc(A, A.R - 6, a0 + span * ease.outExpo(clamp(t / SW)));
        p.glow(x, y, 66, C[5], 0.8 * (1 - t / 0.32));
      }
      const g = t - SW * 0.6;
      if (deco && !full && g > 0 && g < 0.26) sparkle(p, tip[0], tip[1], (heavy ? 18 : 14) * ease.outBack(Math.min(1, g / 0.05)) * (1 - g / 0.26), C[7], C[5], 0.8);
      if (core && heavy && t > SW && t < SW + 0.14) {
        const k = 1 - (t - SW) / 0.14;
        p.disc(R0 * 0.6, 0, 16 * k + 5, C[7], 0.9 * k);
      }
      if (deco) {
        ps.draw(p, "front");
        lights.draw(p);
      }
    },
  };
}
