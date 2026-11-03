// 拉普兰德普攻「双刃」（docs/242 放开版）：俯视，原点 = 拉普兰德，正右为出手方向，游戏里按瞄准方向旋转。
// 原作普攻（whitew_attack_01，build/ark_ref/lappland/original_moves.md）：两段细月牙刀光（ray_daoguang_01 / 03），命中一道细横线 + 小亮点。
// 本作照此：两柄刀先后反向各划一道细月牙，克制（普攻量大）；刀弧半径 = 判定半径 reach（targets judge 传入，1x 像素），张角 = 判定半角 half × 2。
// elite（docs/242 §10，和 S2 用同一套标记，三档一眼分开）：
//   E0 一道细月牙（只有主刃）；E1 双刃（第二道反向月牙）+ 刀口崩出几枚小封印纹（精一「精神摧毁」）；
//   E2 双刃 + 两道细剑气从刀弧上交叉射出（精二「双生刃」每次横扫附带两道交叉剑气）。
// 分层：core = 刀弧、刀口亮线、封印纹、交叉剑气；deco = 光晕、碎光、余韵残痕。
import { Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Lappland twin blades unleashed",
  desc: "Two thin cold-grey crescents cut in opposite directions; elite 1 sheds small seal marks, elite 2 fires two crossing blade glints off the arc.",
  tags: ["melee", "slash", "twin", "topdown", "one-shot"],
  size: [160, 160],
  origin: [80, 80],
  duration: 0.75,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],   // 原作 langtou_02 亮度分位（冷灰白，同 S2）
    radius: 50,       // 判定半径 reach（1x），由 targets judge 覆盖
    span: 2.6,        // 判定半角 × 2，由 targets judge 覆盖
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 3,
  },
};

const onArc = (r, a) => [Math.cos(a) * r, Math.sin(a) * r];

// 细月牙：前缘最厚（W）、两头收尖；外缘一格亮线（只在头两帧白），往里降阶；外缘按噪声崩口
function crescent(p, s, ta, L, W, age, hot, core) {
  if (!core || Math.abs(L) < 0.03 || W < 0.3) return;
  const R = s.C, dir = Math.sign(L), span = Math.abs(L), B = s.R + 3;
  p.shade(-B, -B, B, B, (x, y, out) => {
    const r = Math.hypot(x, y), ang = Math.atan2(y, x);
    const Rr = s.R + 1.2 * noise(ang * 13, s.seed) * (0.4 + age);
    if (r > Rr + 0.5 || r < s.R - W - 1) return;
    let u = (dir * (ang - ta)) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 1.8)), 0.6);
    if (w < 0.45) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    out.c = q < 0.3 ? R[hot ? 6 : 5] : R[clamp(Math.round(4 - q * 2 - age * 2), 1, 4)];
  });
}

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const R0 = +o.radius, span = +o.span, a0 = -span / 2;
  const DL = [0.25, 0.4, 0.6][el] * (quick ? 0.5 : 1), GK = [0.2, 0.3, 0.45][el];
  // 主刃自上而下、第二刃（E1+）自下而上，稍内、稍晚、更细
  const A = { R: R0, C, seed: o.seed, a0, dir: 1, W: 4, t0: 0, sw: 0.06, hold: 0.03, tr: 0.09, trace: true };
  const B = { R: R0 * 0.84, C, seed: o.seed + 9, a0: a0 + span * 0.85, dir: -1, W: 2.6, t0: 0.05, sw: 0.06, hold: 0.02, tr: 0.08, trace: false };   // 第二刃不留残痕：两道同心残痕是禁止的同心圈
  const blades = el >= 1 ? [A, B] : [A];
  const chips = jitterSteps(Rg, span, 0.18, 0.42).map((u) => ({ a: a0 + u, sp: Rg.range(30, 80), life: Rg.range(0.15, 0.3) * (0.7 + DL) }));
  const seals = el >= 1 ? jitterSteps(Rg, span * 0.8, 0.5, 0.9).map((u) => ({ a: a0 + span * 0.1 + u, s: Rg.range(2.2, 3.2), r: Rg.range(-0.6, 0.6), d: Rg.range(4, 9) })) : [];
  const glints = el >= 2 ? [[0.25, -1], [-0.25, 1]].map(([da, sg]) => ({ a: da + Rg.range(-0.05, 0.05), sg })) : [];
  const trace = jitterSteps(Rg, span, 0.1, 0.24).map((u) => [u, Rg.range(0.06, 0.14)]);
  let t = 0;
  const seal = (p, x, y, s, c, r) => {
    const cs = Math.cos(r), sn = Math.sin(r), Lp = (a, b) => [x + a * cs - b * sn, y + a * sn + b * cs];
    p.line(...Lp(-s, -s * 0.8), ...Lp(s * 1.1, s * 0.9), c);
    p.line(...Lp(-s * 0.7, s), ...Lp(s * 0.6, -s * 0.7), c);
  };
  return {
    update(dt) { t += dt; },
    draw(p) {
      for (const s of blades) {
        const u = t - s.t0;
        if (u < 0) continue;
        const head = ease.outExpo(clamp(u / s.sw)), tail = smooth(s.sw + s.hold, s.sw + s.hold + s.tr, u);
        const age = clamp(u / (s.sw + s.hold + s.tr)), hot = u < 0.06;
        const ta = s.a0 + s.dir * span * tail, L = s.dir * span * (head - tail);
        if (tail < 1) crescent(p, s, ta, L, s.W * (1 - tail * 0.5), age, hot, core);
        if (deco && tail < 1) for (let k = 0.1; k < 1; k += 0.22) {   // 光晕沿刀弧（不是一个圆）
          const [x, y] = onArc(s.R - 2, ta + L * k);
          p.glow(x, y, 6, C[3], GK * (1 - age) * k);
        }
        // 余韵：刀走过处一道断续细残痕，alpha ≤ 0.4，分段长短不一
        const tr = 0.4 * (1 - clamp((u - s.sw) / (s.tr + DL)));
        if (deco && s.trace && tr > 0.02) for (const [u0, len] of trace) {
          if (u0 > span * Math.min(1, head)) continue;
          for (let k = u0; k < u0 + len; k += 0.6 / s.R) {
            const [x, y] = onArc(s.R - 1, s.a0 + s.dir * k);
            p.blend(x, y, C[3], tr);
          }
        }
      }
      // 刀口碎光（装饰）：沿弧外甩、细小
      if (deco) for (const c of chips) {
        const u = t - 0.04;
        if (u < 0 || u > c.life) continue;
        const d = R0 + c.sp * u, [x, y] = onArc(d, c.a), k = 1 - u / c.life;
        if (k > 0.25) p.dot(x, y, C[k > 0.6 ? 5 : 3]);
      }
      // E1+ 封印纹：刀口外崩出几枚小歪十字，亮一下变暗
      if (core) for (const s of seals) {
        const u = t - 0.07;
        if (u < 0 || u > 0.12 + DL * 0.5) continue;
        const [x, y] = onArc(R0 + s.d * Math.min(1, u * 8), s.a);
        seal(p, x, y, s.s, C[u < 0.06 ? 6 : u < 0.16 ? 5 : 3], s.r);
      }
      // E2 双生刃：两道剑气从刀弧中段交叉射出，在刀弧外交成一个 X，往外飞、越飞越细（核心），刃尖带光（装饰）
      if (el >= 2) {
        const u = t - 0.06;
        if (u >= 0 && u < 0.26) {
          const d = R0 * 1.05 + 150 * u, L = 13 * (1 - u / 0.26) + 4, c = C[u < 0.06 ? 6 : u < 0.15 ? 5 : 4];
          for (const g of glints) {
            const ax = 1, ay = 0;                                                 // X 的中心在出手方向上
            const cx = ax * d, cy = ay * d, rot = g.sg * 0.55;                   // 两道各斜 ±0.55 弧度，交在中心
            const dx = Math.cos(rot) * L, dy = Math.sin(rot) * L;
            if (core) { p.line(cx - dx, cy - dy, cx + dx, cy + dy, c); p.line(cx - dx, cy - dy + 1, cx + dx * 0.6, cy + dy * 0.6 + 1, C[3]); }
            if (deco) p.glow(cx + dx, cy + dy, 5, C[4], 0.45 * (1 - u / 0.26));
          }
        }
      }
    },
  };
}
