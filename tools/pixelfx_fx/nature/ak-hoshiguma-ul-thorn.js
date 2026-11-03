// 星熊 S2「荆棘」放开版：热砂每跳（圆形判定 sand_r，圆心 = 热砂中心），俯视地面透视 sy 0.55，原点 = 热砂中心。
// 半径 = fit（1x，= sand_r / 2）。原作 S2 buff 是一圈荆棘光环（build/ark_ref/hoshiguma/jingjiguanghuan.png）：这里做成从热砂里扎出的荆棘尖刺，
// 尖刺位置 / 高矮 / 倾角都随机（不排成等距一圈），根部一摊发红的热砂。每跳都放，所以短（0.4 s）、克制。
// S2 开着时每次普攻命中都留一块热砂、每块按周期结算，同屏会叠好几份：所以每跳只扎 4–6 根刺、热砂斑驳几片，保持克制；
// 原作那圈暗红荆棘菱环（hsguma_skill_02_buff）放在 S2 起手（ak-hoshiguma-ul-cast kind 2），只在星熊脚下出一次。
// 精英档：S2 精一才解锁 —— E1 钢色尖刺 + 斑驳热砂 + 火星；E2 尖刺尖端翠绿 + 暗红余烬上飘（般若），余韵略长。E0 = E1 去掉火星（兜底用）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2 } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Hoshiguma thorn sand tick unleashed",
  desc: "Hot-sand tick: irregular thorn spikes stab up out of glowing sand and sink back; higher tiers add sparks, then jade thorn tips and rising red embers.",
  tags: ["nature", "thorn", "ground", "one-shot"],
  size: [112, 84],
  origin: [56, 56],
  duration: 0.55,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // §12.6：不用金（经验结晶暖金），钢色 = PRTS 黑钢盾
    sand: ["#1a0806", "#3a0f0a", "#5e1a10", "#8a2a14", "#b4401c"],   // 热砂压成暗锈红，不到琥珀（§12.6）
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    radius: 40,
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 6,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), S = fit(o.sand, 5), J = fit(o.jade, 5), E = fit(o.ember, 5), Rg = new Rng(o.seed);
  const R = o.radius, el = +o.elite, LQ = +o.quick > 0 ? 0.6 : 1;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const TAIL = (el >= 2 ? 0.3 : 0.2) * LQ;
  // 尖刺：角度抖动、离心远近不一、高矮 6–18、底宽 1.5–3、倾角往外 0.1–0.5，出现早晚不一
  const spikes = jitterAngles(Rg, Rg.int(4, 6), 0, Math.PI * 2, 0.5).map((a) => {
    const r = R * Math.sqrt(Rg.range(0.08, 0.85));
    return { x: Math.cos(a) * r, y: Math.sin(a) * r * SY, a, h: Rg.range(6, 18) * (Rg.chance(0.2) ? 1.4 : 1), w: Rg.range(1.5, 3), lean: Rg.range(0.1, 0.5), d: Rg.range(0, 0.06) };
  });
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [S[4], S[3], S[2], S[1]] });
  const ems = new Particles({ rng: Rg, ground: () => 1e9, sparks: [E[4], E[3], E[2], E[1]] });
  let t = 0, fired = false;
  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        // 11-04 §0：火星 / 余烬点删
      }
    },
    draw(p) {
      // —— 装饰：热砂（11-04 §0 改）：每根刺脚下一块实心的灼红沙斑（不规整椭圆），先亮后逐阶暗下，不用斑驳噪点（读成脏）
      if (deco) for (const s of spikes) {
        const u = t + 0.03 - s.d, k = 1 - smooth(0.12, 0.3 + TAIL * 0.5, u);   // 与刺同时收（刺走了沙斑不单留，免得读成孤立圆点）
        if (u < 0 || k < 0.2) continue;
        const ci = u < 0.06 ? 3 : k > 0.6 ? 2 : 1, rx = 3 + s.w * 1.6, ry = rx * 0.5;
        for (let y = -ry; y <= ry; y += 0.5) for (let x = -rx; x <= rx; x += 0.5) {
          const d = Math.hypot(x / rx, y / ry) * (1 + 0.15 * noise(x * 0.6 + s.x, y + o.seed));
          if (d <= 1) p.blend(s.x + x, s.y + y, S[d > 0.7 ? ci - 1 : ci], 1);
        }
      }
      // —— 核心：尖刺（扎出 → 停 → 缩回），首帧尖端白热；E2 尖端翠绿
      if (core) for (const s of spikes) {
        const u = t + 0.03 - s.d;
        if (u < 0) continue;
        const up = ease.outBack(clamp(u / 0.06)) * (1 - smooth(0.18, 0.32 + TAIL * 0.5, u)), H = s.h * up;
        if (H < 1) continue;
        for (let d = 0; d <= H; d += 0.5) {
          const v = d / H, hw = s.w * (1 - v);
          for (let e = -hw; e <= hw; e += 0.6) {
            let c = C[clamp(Math.round(2 + v * 3 - Math.abs(e) * 0.5 + (u < 0.05 && v > 0.7 ? 2 : 0) - (u > 0.15 ? 1 : 0)), 0, 6)];
            if (el >= 2 && v > 0.65) c = J[clamp(Math.round(2 + v * 2.5 + (u < 0.05 ? 1 : 0)), 1, 4)];
            p.blend(s.x + Math.cos(s.a) * d * s.lean + e, s.y - d, c, v > 0.92 ? 0.9 : 1);
          }
        }
      }
    },
  };
}
