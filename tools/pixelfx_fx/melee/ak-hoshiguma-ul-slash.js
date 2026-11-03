// 星熊普攻「盾斧斩」放开版（docs/242；开关 fx/px_unleashed）：俯视刀弧，圆心 = 星熊，正右为出手方向，游戏按出手方向转（px_ul.json draw）。
// 弧半径 = fit（1x），运行时按判定半径缩放 → 刀弧落在判定半径 × 1.0；span 从 hoshiguma.json half_deg 读。普攻保持克制：薄刀身、短余韵、少甩出物。
// 精英档（docs/242 §10，docs/91 §4）：
//   E0 钢色刀弧 + 少量火星，余韵约 0.25 s；
//   E1 + 刀弧外缘一道暗红（精一「反击架势」：格挡后刀光转暗红；这里常驻为细边，示意架势已解锁）+ 内侧一道往回撩的暗红反手斩 + 刃头碎钢屑；余韵约 0.35 s；
//   E2 刀身内侧转翠绿（精二「般若」翠绿盾锯）+ 沿弧不等距的青绿鬼火星 + 刀尾残影，余韵约 0.45 s（普攻不顶到 0.6）。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Hoshiguma shield-axe cut unleashed",
  desc: "Restrained shield-axe arc in steel; elite tiers add a dark-red stance rim and steel chips, then a jade inner edge, uneven teal motes and a ghost trail.",
  tags: ["melee", "slash", "basic", "topdown", "one-shot"],
  size: [120, 130],
  origin: [26, 65],
  duration: 0.6,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    radius: 47,       // = draw fit：判定半径 94 / 2
    span: 2.44,       // 2 × half_deg（judge）
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), E = fit(o.ember, 5), J = fit(o.jade, 5), Rg = new Rng(o.seed);
  const R = o.radius, el = +o.elite, LQ = +o.quick > 0 ? 0.5 : 1, half = o.span / 2;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const TAIL = [0.25, 0.35, 0.45][el] * LQ;
  const SW = 0.07;                                  // 刀头扫过整条弧的时间
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  const motes = el >= 2 ? jitterSteps(Rg, o.span, 0.12, 0.42).map((u) => ({ a: -half + u, r: R + Rg.range(-6, 3), d: Rg.range(0.03, 0.12), life: Rg.range(0.15, 0.35) * (0.5 + TAIL) })) : [];
  // 原作参照（11-03 还原 hsguma_attack_01）：回旋斩弧内有一层刷开的流纹（huixuan），命中甩出几片小三角碎片。这里照形不照色（原作蓝青太靠近敌弹青 #33ceff）
  const streaks = [0, 1].slice(0, [1, 2, 2][el]).map((i) => { const v0 = Rg.range(0.08, 0.45) + i * 0.2; return { r: R - Rg.range(6, 9) - i * Rg.range(4, 7), v0, v1: Math.min(0.97, v0 + Rg.range(0.25, 0.45)), lag: Rg.range(0.0, 0.03) }; });   // 一两道、错开、长短不一（多道等长平行会读成同心弧）
  const shards = Array.from({ length: [3, 4, 6][el] }, () => {
    const a = -half + o.span * Rg.range(0.25, 1.0);
    return { a, sp: Rg.range(40, 90), dv: Rg.range(-0.5, 0.5), rot: Rg.range(0, 6.28), spin: Rg.range(-14, 14), s: Rg.range(1.6, 2.8), d: SW * ((a + half) / o.span), life: Rg.range(0.18, 0.3) * (0.7 + TAIL) };
  });
  let t = 0, fired = false;
  return {
    update(dt) {
      t += dt;
      if (!fired && t > SW * 0.6) {
        fired = true;
        lights.add(Math.cos(half) * R, Math.sin(half) * R, 10, C[5], 0.35, 0.12);
        // 11-04 §0：火星 / 钢屑删（同屏 ≤ 3 种：刀弧主形、E2 残影、照地）
      }
      ps.update(dt); lights.update(dt);
    },
    draw(p) {
      const head = ease.outExpo(clamp((t + 0.02) / SW)), tail = smooth(SW, SW + 0.12 + TAIL * 0.3, t);
      const a1 = -half + o.span * head, a0 = -half + o.span * tail, cool = clamp((t - 0.04) / 0.18);
      // 装饰：E2 刀尾残影（往回拖的一道淡翠绿弧）
      if (deco && el >= 2) {
        const gk = 1 - smooth(0.05, 0.05 + TAIL, t);
        if (gk > 0) for (let a = -half; a < a1; a += 0.02) {
          const v = (a + half) / o.span;
          p.blend(Math.cos(a) * (R - 5), Math.sin(a) * (R - 5), J[2], 0.35 * gk * v);
        }
      }
      if (deco) {   // （回旋细纹 / 往外甩的小三角碎片 11-04 删：§0 不碎、不往外甩）
        const gk = (el >= 2 ? 0.3 : 0.2) * (1 - smooth(0.03, 0.12 + TAIL * 0.3, t));
        if (gk > 0.01) for (let a = a0; a < a1; a += 0.25) p.glow(Math.cos(a) * (R - 3), Math.sin(a) * (R - 3), 9, el >= 2 ? J[3] : C[4], gk);
        ps.draw(p, "back");
      }
      // 核心：刀弧（判定半径内），刀头厚、刀尾细；首帧白热，第 2 帧余热，之后回钢色并淡出
      if (core && a1 - a0 > 0.03) {
        const hot = t < 0.045 ? 2 : t < 0.09 ? 1 : 0, W = 5.5 * [1, 1.25, 1.5][el] * (1 - 0.4 * tail);   // §8：E1 ×1.25、E2 ×1.5 加厚
        for (let y = -R - 2.5; y <= R + 2.5; y++)
          for (let x = -4.5; x <= R + 2.5; x++) {
            const ang = Math.atan2(y, x);
            if (ang < a0 || ang > a1) continue;
            const v = (ang - a0) / Math.max(a1 - a0, 0.01);
            const rim = R + 0.9 * noise(ang * 13, o.seed) + 0.5 * noise(ang * 29, o.seed + 3);
            const w = W * Math.pow(Math.sin(Math.PI * Math.min(1, v * 0.6 + 0.1)), 1.1) + 0.5, q = (rim - Math.hypot(x, y)) / w;
            if (q < 0 || q > 1) continue;
            let c = C[clamp(Math.round(4.5 + hot - q * 3 - cool * 1.8 - (1 - v) * 1.2), 1, 6)];
            if (el >= 1 && q < 0.16 && t > 0.04) c = E[clamp(Math.round(3.4 - cool * 1.5), 1, 4)];   // E1：外缘暗红细边（反击架势）
            if (el >= 2 && q > 0.55 && t > 0.04) c = J[clamp(Math.round(3.6 - cool * 1.6 - (q - 0.55) * 2), 1, 4)];   // E2：内侧翠绿（般若）
            p.blend(x, y, c, q > 0.8 ? 0.7 : 1);
          }
      }
      // 核心：E1 起「反击架势」反手斩——主刀弧走完后，内侧一道暗红细弧从刀头往回撩（反向、只扫 55%），E0 没有
      if (core && el >= 1) {
        const bt = t - SW - 0.01, bh = ease.outExpo(clamp(bt / 0.06)), bk = 1 - smooth(0.06, 0.12 + TAIL * 0.4, bt);
        if (bt > 0 && bk > 0) {
          // E2 质变（§8）：反手斩变成整条翠绿第二刃（单刀 → 双刃新月），扫满全弧、厚 0.8 主刃，专属青绿
          const q2 = el >= 2, SPN = q2 ? 1.0 : 0.55, b0 = half - o.span * SPN * bh, rb = q2 ? R - 5.5 * 1.5 - 4 : R - 8;
          for (let a = b0; a <= half - 0.04; a += 0.012) {
            const v = (half - a) / (o.span * SPN), th = (q2 ? 5.5 * 1.2 : 1.6) * Math.sin(Math.PI * clamp(v * 0.9 + 0.05)) + 0.3;
            const rr = rb + 0.8 * noise(a * 17, o.seed + 9);
            for (let e = 0; e <= th; e += 0.5) p.blend(Math.cos(a) * (rr - e), Math.sin(a) * (rr - e), q2 ? (bt < 0.03 ? C[6] : J[clamp(Math.round(4 - e / th * 2 - (bt > 0.08 ? 1 : 0)), 1, 4)]) : E[clamp(Math.round(4 - e * 0.8 - (bt > 0.05 ? 1 : 0)), 1, 4)], bk);
          }
        }
      }
      if (deco) { ps.draw(p, "front"); lights.draw(p); }
    },
  };
}
