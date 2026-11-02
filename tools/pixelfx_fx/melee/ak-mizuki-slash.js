// 水月「伞击」普攻（docs/229 §3 普攻档）：@2x 密度，正右为出手方向，游戏里按瞄准方向旋转；原点 = 水月本人（seg_mizuki 在 o.pos 放）。
// 刀弧半径 = 挥击半径 112 × 0.85，张角 150°（swing_arc）。伞面扫过留下一片半透明的水母伞膜，内侧拖出几缕长短不一的触丝，末尾散成小气泡。
// 色阶：house.js OP.mizuki（PRTS Spine 取色：外套宝蓝 → 发梢薰衣草 → 白）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP, FPS, REACH } from "../house.js";

export const meta = {
  name: "Mizuki umbrella sweep",
  desc: "A translucent jellyfish-bell sweep: a white rim with a lavender membrane behind it, trailing uneven tendrils that thin out into bubbles.",
  tags: ["melee", "slash", "jellyfish", "topdown", "one-shot"],
  size: [220, 220],
  origin: [110, 110],
  duration: 0.19,
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.mizuki],
    radius: 112 * REACH.sweep,
    span: 2.62,       // 150°
    seed: 2,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const a0 = -o.span / 2, span = o.span;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]] });
  const SWEEP = 0.05, HOLD = 0.015, TRAIL = 0.075, W = 13;
  // 触丝：挂在伞缘内侧，长短、位置、起伏各不相同
  const tend = [];
  for (let v = Rg.range(0.12, 0.25); v < 0.95; v += Rg.range(0.2, 0.36))
    tend.push({ v, len: Rg.range(22, 40), ph: Rg.range(0, 6), w: Rg.range(0.6, 1.2) });
  let t = 0.01, popped = false;

  function rim(p, head, tail, age) {
    const ta = a0 + span * tail, L = span * (head - tail), Wn = W * (1 - tail * 0.5);
    if (L < 0.02) return;
    const B = R + 4;
    p.shade(-B, -B, B, B, (x, y, out) => {
      const r = Math.hypot(x, y), ang = Math.atan2(y, x);
      const Rr = R + 1.6 * noise(ang * 8, o.seed) * (0.3 + age);
      if (r > Rr + 0.5 || r < R - Wn - 1) return;
      const u = ang - ta;
      if (u < 0 || u > L) return;
      const v = u / L, w = Wn * Math.pow(Math.sin(Math.PI * Math.pow(v, 1.6)), 0.5);
      if (w < 0.4) return;
      const q = (Rr - r) / w;
      if (q < 0 || q > 1) return;
      const hot = t < 0.045 ? 1.6 : 0;
      const ci = Math.round(q * 4.5 + 0.4 + age * 4 - v * 1.1 - hot);
      const c = C[7 - clamp(ci, 0, 6)];
      if (q > 0.4) p.blend(x, y, c, 0.6);               // 伞膜：外缘实、往里真半透明（shade 的 out.a 是抖动，不用）
      else out.c = c;
    });
  }

  function tendrils(p, head, tail, age) {
    for (const s of tend) {
      if (s.v > head || s.v < tail) continue;
      const a = a0 + span * s.v, nx = Math.cos(a), ny = Math.sin(a), tx = -ny, ty = nx;
      const L = s.len * (1 - age * 0.5);
      let px = nx * (R - W * 0.6), py = ny * (R - W * 0.6);
      for (let d = 0; d < L; d += 1) {
        const wob = Math.sin(d * 0.35 + s.ph + t * 30) * 1.6 * (d / L);
        const x = px - tx * d * 0.9 - nx * d * 0.25 + nx * wob, y = py - ty * d * 0.9 - ny * d * 0.25 + ny * wob;
        p.blend(Math.round(x), Math.round(y), C[clamp(Math.round(7 - d / L * 3 - age * 2), 3, 7)], 0.95 - d / L * 0.5);
      }
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!popped && t >= SWEEP + HOLD) {
        popped = true;
        for (const s of tend) {
          const a = a0 + span * s.v, x = Math.cos(a) * (R - 6), y = Math.sin(a) * (R - 6);
          const n = Rg.int(1, 2);
          for (let i = 0; i < n; i++) {
            const da = a + Rg.range(-1.2, 1.2), sp = Rg.range(30, 90);
            ps.spawn(P.FLAKE, x, y, Math.cos(da) * sp, Math.sin(da) * sp, Rg.range(0.06, 0.12), C[Rg.int(5, 7)], Rg.range(1.5, 2.5));
          }
        }
      }
      ps.update(dt);
    },
    draw(p) {
      const head = ease.outExpo(clamp(t / SWEEP)), tail = smooth(SWEEP + HOLD, SWEEP + HOLD + TRAIL, t);
      const age = clamp(t / (SWEEP + HOLD + TRAIL));
      if (tail < 1) {
        tendrils(p, head, tail, age);
        rim(p, head, tail, age);
      }
      ps.draw(p);
    },
  };
}
