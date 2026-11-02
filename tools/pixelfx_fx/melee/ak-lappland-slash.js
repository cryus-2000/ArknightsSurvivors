// 拉普兰德普攻「双刃」横扫（docs/231 普攻试点）：@2x 密度（1 像素 = 1 世界像素），正右为出手方向，游戏里按瞄准方向旋转。
// 原点 = 帧中心 = 身前 along 0.5 × 判定半径（100）处；拉普兰德本人在原点左边 50 px（cx）。刀弧半径 = 判定半径 × 0.85（docs/229 §2.8），
// 张角 = 判定半角 1.3 × 2。普攻预算（docs/229 §0 / §2.5）：主体 ≤ 0.2 s + 余韵 ≤ 0.15 s（alpha ≤ 0.4、稀疏），24 fps，≤ 5 + 3 帧。
// 颜色层硬色阶、白只在刀口最烫的那一线（近白 ≤ 12%）；柔光靠 p.glow 进 light 层，导出成 _glow 条在游戏里加色叠画。
import { Particles, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { OP, FPS, REACH, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Lappland twin slash",
  desc: "A fast twin-blade sweep: a ragged silver crescent with a white-hot edge snaps across, a thinner second blade follows, both cool to steel and leave a faint broken trace.",
  tags: ["melee", "slash", "twin", "topdown", "one-shot"],
  size: [128, 192],
  origin: [64, 96],
  duration: 0.17 + DUR.basicTail,
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: OP.lappland,
    cx: -50,          // 拉普兰德相对原点的位置
    radius: 100 * REACH.sweep,
    span: 2.6,        // 弧度：判定半角 1.3 × 2
    seed: 5,
  },
};

const onArc = (s, r, a) => [s.cx + Math.cos(a) * r, Math.sin(a) * r];

// 刀弧：前缘最厚、尾部收成线。色阶从设定色（第 3 阶）往下走：外缘设定色、往里和往尾部变暗；
// 只有出刀头两帧、最外 1 像素的刀口用最亮两阶。外缘用噪声做不等距的崩口
function crescent(p, s, ta, L, W, age) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, span = Math.abs(L), B = s.R + 2;
  p.shade(s.cx - B, -B, s.cx + B, B, (x, y, out) => {
    const dx = x - s.cx, dy = y, r = Math.hypot(dx, dy);
    const ang = Math.atan2(dy, dx), jag = 1.6 * noise(ang * 11, s.seed) + 0.9 * noise(ang * 29, s.seed + 3);
    const Rr = s.R + jag * (0.3 + age * 1.4);
    if (r > Rr + 0.5 || r < s.R - W - 1) return;
    let u = (ang - ta) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 2.2)), 0.6);
    if (w < 0.35) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    const edge = Rr - r < 1.1 && v > 0.55 && age < 0.3;   // 刀口：最外一线、靠刀头那段、只在头两帧
    const ci = edge ? (v > 0.8 ? n - 1 : n - 2) : clamp(Math.round(n - 4 - q * 2.2 - age * 2.4 + v * 0.8), 0, n - 3);
    out.c = R[ci];   // 不设 out.a：painter 的半透明是 Bayer 抖动（棋盘格，docs/229 §2.4 禁用），刀尾靠变细收掉
  });
  // 光晕（light 层）：沿刀身、越靠刀头越亮
  for (let u = 0; u <= span; u += 0.22) {
    const [x, y] = onArc(s, s.R - W * 0.4, ta + u);
    p.glow(x, y, 5 + W * 0.7, R[n - 3], 0.3 * (1 - age) * (u / span));
  }
}

function drawSlash(p, s, t) {
  const u = t - s.t0;
  if (u < 0) return;
  const span = s.a1 - s.a0, head = ease.outExpo(clamp(u / s.sweep)), tail = smooth(s.sweep + s.hold, s.sweep + s.hold + s.trail, u);
  const age = clamp(u / (s.sweep + s.hold + s.trail));
  if (tail < 1) crescent(p, s, s.a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.7), age);
  // 余韵：刀走过的地方留一道断续残痕，alpha ≤ TAIL_ALPHA，稀疏、不等距，主体收完后 DUR.basicTail 内淡掉
  const tr = TAIL_ALPHA * (1 - clamp((u - s.sweep - s.hold) / (s.trail + DUR.basicTail)));
  if (tail > 0.05 && tr > 0)
    for (const [k0, k1] of s.gaps) {
      if (k0 > tail) break;
      for (let k = k0; k <= Math.min(k1, tail); k += 0.6 / (span * s.R)) {
        const [x, y] = onArc(s, s.R - 1, s.a0 + span * k);
        p.blend(x, y, s.ramp[s.ramp.length - 4], tr * (0.4 + 0.6 * k));   // 真半透明（p.dot 带 alpha 是抖动）
      }
    }
}

// 残痕分段：长短不一（±30% 以上）
function gaps(Rg) {
  const out = [];
  for (let k = Rg.range(0, 0.06); k < 1; ) {
    const len = Rg.range(0.06, 0.16);
    out.push([k, k + len]);
    k += len + Rg.range(0.03, 0.09);
  }
  return out;
}

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[3], C[3], C[2], C[1]] });   // 火星不用近白两阶
  const a0 = -o.span / 2, a1 = o.span / 2;
  // 主刃 + 稍晚、稍内、更细的第二刃（双刃）；两道都从上往下扫
  const A = { seed: o.seed, cx: o.cx, R: o.radius, a0, a1, W: 10, t0: 0, sweep: 0.045, hold: 0.02, trail: 0.1, ramp: C, gaps: gaps(Rg) };
  const B = { ...A, seed: o.seed + 11, R: o.radius - 13, W: 4, a0: a0 + 0.22, a1: a1 - 0.1, t0: 0.025, trail: 0.08, ramp: C.slice(0, 6), gaps: [] };   // 第二刃不留残痕：两道同心残痕是被否的「同心圈」
  let t = 0.012, passed = 0, chipped = false;   // 从挥出一点开始：第 0 帧就有刀
  return {
    update(dt) {
      t += dt;
      // 刀头经过时沿切线甩出少量碎光（数量少：普攻量大）
      const head = ease.outExpo(clamp(t / A.sweep));
      while (passed < head && passed < 1) {
        const a = a0 + o.span * passed, [x, y] = onArc(A, A.R - Rg.range(0, 4), a);
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(120, 260);
        if (Rg.chance(0.55)) ps.spawn(P.SPARK, x, y, (tx * 0.7 + nx * 0.7) * sp, (ty * 0.7 + ny * 0.7) * sp, Rg.range(0.05, 0.11));
        passed += Rg.range(0.08, 0.16);
      }
      if (!chipped && t >= A.sweep) {
        chipped = true;
        // 刀停处崩出几片碎刃：方向偏前、长短不一
        const [x, y] = onArc(A, A.R - 3, a1);
        for (let i = 0; i < 5; i++) {
          const a = a1 + Math.PI / 2 + Rg.range(-0.8, 0.5), sp = Rg.range(140, 300);
          ps.spawn(P.SPARK, x, y, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.05, 0.1));
        }
      }
      ps.update(dt);
    },
    draw(p) {
      drawSlash(p, B, t);
      drawSlash(p, A, t);
      if (t < 0.09) {
        const [x, y] = onArc(A, A.R - 4, a0 + o.span * ease.outExpo(clamp(t / A.sweep)));
        p.glow(x, y, 14, C[4], 0.3 * (1 - t / 0.09));
      }
      ps.draw(p);
    },
  };
}
