// 星熊 S2「荆棘」放开版：热砂每跳（圆形判定 sand_r，圆心 = 热砂中心），俯视地面透视 sy 0.55，原点 = 热砂中心。
// 半径 = fit（1x，= sand_r / 2）。原作 S2 buff 是一圈荆棘光环（build/ark_ref/hoshiguma/jingjiguanghuan.png）：这里做成从热砂里扎出的荆棘尖刺，
// 尖刺位置 / 高矮 / 倾角都随机（不排成等距一圈），根部一摊发红的热砂。每跳都放，所以短（0.4 s）、克制。
// 精英档：S2 精一才解锁 —— E1 尖刺 + 热砂 + 火星；E2 尖刺尖端转翠绿 + 暗红余烬上飘（般若），余韵略长。E0 = E1 去掉火星（兜底用）。
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
    palette: ["#55431b", "#91732e", "#c2993d", "#f2bf4c", "#f7d58b", "#fbecc9", "#ffffff"],
    sand: ["#2a0e06", "#5a1e0c", "#9a3a12", "#d8661e", "#ffa040"],
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ffa070"],
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
  const spikes = jitterAngles(Rg, Rg.int(7, 10), 0, Math.PI * 2, 0.45).map((a) => {
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
        if (deco && el >= 1) for (const s of spikes) if (Rg.chance(0.6)) ps.spawn(P.SPARK, s.x, s.y - s.h * 0.6, Math.cos(s.a) * Rg.range(30, 90), -Rg.range(60, 140), Rg.range(0.12, 0.25), 0, 1, s.d);
        if (deco && el >= 2) for (let i = 0; i < 6; i++) ems.spawn(P.EMBER, Rg.range(-R, R) * 0.7, Rg.range(-R, R) * 0.7 * SY, Rg.range(-10, 10), -Rg.range(20, 50), Rg.range(0.3, 0.5), E[3], 1, Rg.range(0, 0.1));
      }
      ps.update(dt); ems.update(dt);
    },
    draw(p) {
      // —— 装饰：热砂（根部一摊，边缘按噪声起伏，发红后暗下去，真半透明）
      if (deco) {
        const k = ease.outQuart(clamp((t + 0.03) / 0.06)) * (1 - smooth(0.1, 0.25 + TAIL, t));
        if (k > 0.02) for (let y = -R * SY - 2; y <= R * SY + 2; y++) for (let x = -R - 2; x <= R + 2; x++) {
          const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / (1 + 0.15 * noise(a * 3, o.seed));
          if (r > R) continue;
          const n = 0.5 + 0.5 * noise2(x * 0.16, y * 0.3, o.seed + 2);
          if (n < 0.35) continue;
          p.blend(x, y, S[clamp(Math.round(1 + n * 2.5 - r / R * 1.2 + (t < 0.08 ? 1 : 0)), 0, 4)], 0.4 * k * (1 - r / R * 0.6));
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
      if (deco) { ems.draw(p); ps.draw(p); }
    },
  };
}
