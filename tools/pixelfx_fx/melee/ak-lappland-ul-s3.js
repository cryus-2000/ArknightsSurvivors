// 拉普兰德 S3「噤声」叠满（docs/242 放开版，本作自创，草图 tools/pixelfx_fx/ref/lappland_s3.png 已过用户）：俯视，原点 = 目标。
// 观察叠满时：一道一长一短、不对称的十字斩穿过目标（落在判定 s3_cut_r 上，targets judge 传入），外侧烙几枚封印纹 = 封印 + 定格 + 易伤。
// 主形「十字斩 + 封印」，和普攻的月牙、S2 的狼首、终结技的剑气帘都不同。起手：两道刃先从两侧一闪（预兆线），下一帧斩下。
// elite：E0 十字 + 2 枚封印纹；E1 封印纹 4 枚、更大（精神摧毁）；E2 十字的两臂各变成两层平行刃（双生刃），交点白热带淡蓝。
// 分层：core = 十字刃、封印纹、预兆线；deco = 光晕、碎光、淡蓝余韵切痕。
import { Rng, fit, hex, clamp, ease, noise } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Lappland silence cross",
  desc: "Two uneven blades flash in and cross through the target, then seal marks burn around it; elite 2 doubles each blade.",
  tags: ["melee", "slash", "cross", "seal", "topdown", "one-shot"],
  size: [120, 100],
  origin: [60, 50],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    r: 20,            // 十字斩半径 = s3_cut_r ÷ PX（1x），由 targets judge 覆盖
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 6,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", BLUE = hex("#cfe6f3");
  const R = +o.r, DL = [0.3, 0.45, 0.65][el] * (quick ? 0.5 : 1), GK = [0.35, 0.45, 0.6][el];
  const T0 = 0.05, TS = 0.06;   // 预兆 / 斩下
  // 两臂：一长一短，角度不对称（草图）
  const arms = [{ a: -0.64 + Rg.range(-0.05, 0.05), L0: R * 1.05, L1: R * 1.0 }, { a: 0.86 + Rg.range(-0.05, 0.05), L0: R * 0.85, L1: R * 0.8 }];
  const nSeal = [2, 4, 4][el];
  const seals = Array.from({ length: nSeal }, (_, i) => ({ a: (i / nSeal) * 6.28 + Rg.range(-0.5, 0.5), r: R * Rg.range(1.05, 1.3), s: (el >= 1 ? 3.6 : 2.6) * Rg.range(0.85, 1.15), rot: Rg.range(-0.6, 0.6), t0: T0 + TS + Rg.range(0, 0.12) }));
  const chips = jitterSteps(Rg, 6.28, 0.3, 0.8).map((a) => ({ a, sp: Rg.range(40, 110), life: Rg.range(0.2, 0.4) * (0.7 + DL) }));
  let t = 0;
  const seal = (p, x, y, s, c, r) => {
    const cs = Math.cos(r), sn = Math.sin(r), Lp = (a, b) => [x + a * cs - b * sn, y + a * sn + b * cs];
    p.line(...Lp(-s, -s * 0.8), ...Lp(s * 1.1, s * 0.9), c);
    p.line(...Lp(-s * 0.7, s), ...Lp(s * 0.6, -s * 0.7), c);
  };
  const blade = (p, a, L0, L1, off, c) => {   // 一柄直刃：中段两格、两头一格，off = 沿法线平移（E2 第二层）
    const ca = Math.cos(a), sa = Math.sin(a), nx = -sa * off, ny = ca * off;
    p.line(-ca * L1 + nx, -sa * L1 + ny, ca * L0 + nx, sa * L0 + ny, c);
    p.line(-ca * L1 * 0.5 + nx - sa, -sa * L1 * 0.5 + ny + ca, ca * L0 * 0.5 + nx - sa, sa * L0 * 0.5 + ny + ca, c);
  };
  return {
    update(dt) { t += dt; },
    draw(p) {
      // 预兆：两条细线从两侧一闪（只有 1 帧），提示要斩了
      if (core && t < T0) for (const m of arms) {
        const ca = Math.cos(m.a), sa = Math.sin(m.a);
        p.line(ca * m.L0 * 0.7, sa * m.L0 * 0.7, ca * m.L0 * 1.1, sa * m.L0 * 1.1, C[4]);
        p.line(-ca * m.L1 * 0.7, -sa * m.L1 * 0.7, -ca * m.L1 * 1.1, -sa * m.L1 * 1.1, C[4]);
      }
      const u = t - T0;
      if (u >= 0) {
        const grow = ease.outExpo(clamp(u / TS)), fade = clamp((u - TS - 0.05) / (0.25 + DL * 0.5));
        const hot = u < 0.06, c = hot ? C[6] : fade < 0.3 ? BLUE : fade < 0.7 ? C[4] : C[2];
        if (core && fade < 1) for (const m of arms) {
          blade(p, m.a, m.L0 * grow, m.L1 * grow, 0, c);
          if (el >= 2) blade(p, m.a, m.L0 * grow * 0.8, m.L1 * grow * 0.8, 3, fade < 0.5 ? C[4] : C[2]);   // 双生刃：第二层平行刃
        }
        if (core && hot) p.poly([[0, -2], [2, 0], [0, 2], [-2, 0]], C[6]);
        if (core && el >= 2 && !hot && fade < 0.5) p.dot(0, 0, BLUE);
        if (deco && fade < 1) {
          for (const m of arms) for (let k = -0.8; k <= 0.8; k += 0.27) p.glow(Math.cos(m.a) * R * k, Math.sin(m.a) * R * k, hot ? 8 : 5, hot ? C[5] : BLUE, GK * (1 - fade) * (hot ? 1.3 : 0.7));
        }
      }
      // 封印纹：斩下后在外侧烙上，亮一下转淡蓝、变暗
      for (const s of seals) {
        const v = t - s.t0;
        if (v < 0 || v > 0.25 + DL) continue;
        const x = Math.cos(s.a) * s.r, y = Math.sin(s.a) * s.r * 0.8;
        if (core) seal(p, x, y, s.s, v < 0.05 ? C[6] : v < 0.25 ? BLUE : C[3], s.rot);
        if (deco) p.glow(x, y, 5, BLUE, 0.35 * (1 - v / (0.25 + DL)));
      }
      // 碎光：从交点往外迸（方向随机、速度不一）
      if (deco) for (const ch of chips) {
        const v = t - T0 - TS;
        if (v < 0 || v > ch.life) continue;
        const d = ch.sp * v, k = 1 - v / ch.life;
        if (k > 0.25) p.dot(Math.cos(ch.a) * d, Math.sin(ch.a) * d * 0.8, k > 0.6 ? C[5] : BLUE);
      }
    },
  };
}
