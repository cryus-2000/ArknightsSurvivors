// 乌尔比安「锚击」普攻（docs/229 §3 普攻档）：@2x 帧条，正右为出手方向，游戏里随这一击的方向转（rot_ang）。
// 原点 = 锚击圆心（attack.fx along -0.1）。游戏里 scale_r 0.0209：判定半径 89 时每个 1x 像素 1.86 世界像素，帧里判定圆半径 ≈ 96 px。
// 一道短而厚的铁锚弧从身侧砸到前方，刃口白热、刃背深海铁蓝；落点处地面迸出几道不等长的裂口和碎石，不画圈。
import { Particles, Bits, B, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP, FPS, REACH, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Ulpianus anchor slam",
  desc: "A short, thick anchor arc slams forward: white-hot edge, iron-blue back, then a few uneven ground cracks and chips burst at the point of impact.",
  tags: ["melee", "slam", "anchor", "topdown", "one-shot"],
  size: [200, 200],
  origin: [100, 100],
  duration: 0.30,   // 主体 + 余韵
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: [...OP.ulpianus],
    cx: -48,                    // 弧心在圆心后方半个判定半径
    radius: 96 * REACH.sweep,   // 判定圆半径 96 px（帧里）× 0.85
    span: 2.2,
    seed: 6,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius, cx = o.cx;
  const a0 = -o.span / 2, span = o.span;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]] });
  const bits = new Bits({ ground: () => 1e9 });
  const SWEEP = 0.05, HOLD = 0.02, TRAIL = 0.07, W = 26;
  const hitX = cx + R * 0.92, hitY = R * 0.12;          // 落点：弧的正前方略偏下
  const cracks = [];
  for (let a = Rg.range(-1.5, -1.1); a < 1.5; a += Rg.range(0.75, 1.25))   // 只往前方裂，角度和长度都不等
    cracks.push({ a, len: Rg.range(14, 34), bend: Rg.range(-1, 1), fork: Rg.chance(0.6) ? Rg.range(0.35, 0.7) : 0, sd: Rg.range(0, 50) });
  let t = 0.01, hit = false;

  function arc(p) {
    const head = ease.outExpo(clamp(t / SWEEP)), tail = smooth(SWEEP + HOLD, SWEEP + HOLD + TRAIL, t);
    if (tail >= 1) return;
    const age = clamp(t / (SWEEP + HOLD + TRAIL)), ta = a0 + span * tail, L = span * (head - tail), Wn = W * (1 - tail * 0.6);
    if (L < 0.02) return;
    const Bd = R + 4;
    p.shade(cx - Bd, -Bd, cx + Bd, Bd, (x, y, out) => {
      const dx = x - cx, r = Math.hypot(dx, y), ang = Math.atan2(y, dx);
      const Rr = R + 1.4 * noise(ang * 7, o.seed) * (0.3 + age);
      if (r > Rr + 0.5 || r < R - Wn - 1) return;
      const u = ang - ta;
      if (u < 0 || u > L) return;
      const v = u / L, w = Wn * Math.pow(Math.sin(Math.PI * Math.pow(v, 1.4)), 0.5);
      if (w < 0.4) return;
      const q = (Rr - r) / w;
      if (q < 0 || q > 1) return;
      const hot = t < 0.045 ? 0.8 : 0;                    // 首帧只让刃口芯爆白（白只在核心，近白 ≤ 12%）
      const c = C[7 - clamp(Math.round(q * 5 + 0.4 + age * 4 - v * 1.3 - hot), 0, 6)];
      if (q > 0.55) p.blend(x, y, c, 0.75);   // 刃背半透明（真半透明，不抖动）
      else out.c = c;
    });
  }

  function crackDraw(p) {
    if (!hit) return;
    const u = clamp((t - SWEEP) / 0.04), fade = 1 - smooth(0.1, 0.19, t);
    if (fade <= 0) return;
    for (const k of cracks) {
      const L = k.len * ease.outQuart(u);
      let x = hitX + Math.cos(k.a) * 3, y = hitY + Math.sin(k.a) * 2, a = k.a;   // 从落点外 3 px 起裂，中心不成星
      for (let d = 0; d < L; d += 1) {
        a += k.bend * 0.03 + 0.25 * noise(d * 0.3, k.sd);   // 曲折
        x += Math.cos(a); y += Math.sin(a) * 0.6;           // 地面透视
        const c = C[clamp(Math.round(6 - d / k.len * 4 - (1 - fade) * 3), 1, 7)];
        p.blend(Math.round(x), Math.round(y), c, fade);
        if (k.fork && Math.abs(d - L * k.fork) < 0.5) {
          let fx = x, fy = y, fa = a + (k.bend > 0 ? -0.7 : 0.7);
          for (let e = 0; e < L * 0.4; e += 1) { fx += Math.cos(fa); fy += Math.sin(fa) * 0.6; p.blend(Math.round(fx), Math.round(fy), C[3], fade * 0.8); }
        }
      }
    }
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
      if (!hit && t >= SWEEP) {
        hit = true;
        for (let i = 0; i < 5; i++) {
          const a = Rg.range(-2.4, 2.4), sp = Rg.range(60, 150);
          bits.add({ kind: B.CHUNK, x: hitX, y: hitY, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.6 - 40, a: Rg.range(0, 6), va: Rg.range(-12, 12),
            s: Rg.range(1.5, 3), ramp: [C[1], C[2], C[3]], g: 0, drag: 3, life: Rg.range(0.08, 0.13) });
        }
        for (let i = 0; i < 4; i++) {
          const a = Rg.range(-1.2, 1.2), sp = Rg.range(120, 240);
          ps.spawn(P.SPARK, hitX, hitY, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.05, 0.1));
        }
      }
      ps.update(dt);
      bits.update(dt);
    },
    draw(p) {
      crackDraw(p);
      arc(p);
      bits.draw(p);
      halo(p);
      tail(p);
      ps.draw(p);
    },
  };
}
