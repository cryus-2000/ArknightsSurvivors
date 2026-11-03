// 星熊 S2「荆棘」放开版：热砂每跳（圆形判定 sand_r，圆心 = 热砂中心），俯视地面透视 sy 0.55，原点 = 热砂中心。
// 半径 = fit（1x，= sand_r / 2）。原作 S2 buff 是一圈荆棘光环（build/ark_ref/hoshiguma/jingjiguanghuan.png）：这里做成从热砂里扎出的荆棘尖刺，
// 尖刺位置 / 高矮 / 倾角都随机（不排成等距一圈），根部一摊发红的热砂。每跳都放，所以短（0.4 s）、克制。
// 原作参照（11-03 还原 hsguma_skill_02_buff）：脚下一圈转 45° 的暗红荆棘方框，倒刺往外，红光晕。这里照它在热砂上长出暗红荆棘菱环。
// 精英档：S2 精一才解锁 —— E1 钢色尖刺 + 斑驳热砂 + 火星 + 菱环的两条边；E2 质变：菱环四边合拢（带断口）+ 沿藤红光 + 尖刺尖端翠绿 + 暗红余烬上飘（般若），余韵略长。E0 = E1 去掉火星（兜底用）。
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
  const spikes = jitterAngles(Rg, Rg.int(7, 10), 0, Math.PI * 2, 0.45).map((a) => {
    const r = R * Math.sqrt(Rg.range(0.08, 0.85));
    return { x: Math.cos(a) * r, y: Math.sin(a) * r * SY, a, h: Rg.range(6, 18) * (Rg.chance(0.2) ? 1.4 : 1), w: Rg.range(1.5, 3), lean: Rg.range(0.1, 0.5), d: Rg.range(0, 0.06) };
  });
  // 荆棘菱环（照原作 S2 skill_02_buff 的 jingjiguanghuan：一圈转 45° 的方形荆棘框，倒刺往外支）：四条边各是一根略弯的暗红荆棘藤，
  // 边上随机断口、倒刺不等距；E1 只长出其中两条边（相邻），E2 四边合拢成整个菱框（仍有断口，不是整圈）
  const DR = R * 0.82, DV = [[DR, 0], [0, DR * SY], [-DR, 0], [0, -DR * SY]], e1 = Rg.int(0, 3);
  const vines = el >= 1 ? [0, 1, 2, 3].filter((k) => el >= 2 || k === e1 || k === (e1 + 1) % 4).map((k) => {
    const [x0, y0] = DV[k], [x1, y1] = DV[(k + 1) % 4], L = Math.hypot(x1 - x0, y1 - y0), nx = (y1 - y0) / L, ny = -(x1 - x0) / L;   // 法向朝外
    const bend = Rg.range(-0.08, 0.12) * L;
    const barbs = []; for (let v = Rg.range(0.05, 0.15); v < 0.95; v += Rg.range(0.09, 0.22)) barbs.push([v, Rg.chance(0.75) ? 1 : -1, Rg.range(2, 4.5)]);
    return { s0: { x: x0, y: y0 + 2 }, s1: { x: x1, y: y1 + 2 }, cx: (x0 + x1) / 2 + nx * bend, cy: (y0 + y1) / 2 + ny * bend * SY + 2, d: Rg.range(0, 0.05) + k * 0.015, barbs, gap: Rg.range(0.2, 0.8), gw: Rg.range(0.06, 0.12) };
  }) : [];
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
          const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / (1 + 0.3 * noise(a * 3, o.seed));
          if (r > R) continue;
          const n = 0.5 + 0.5 * noise2(x * 0.16, y * 0.3, o.seed + 2);
          if (n < 0.52) continue;   // 只留斑驳的几片热砂（不铺成一整块圆盘，§12.3）
          p.blend(x, y, S[clamp(Math.round(1 + n * 2.5 - r / R * 1.2 + (t < 0.08 ? 1 : 0)), 0, 4)], 0.4 * k * (1 - r / R * 0.6));
        }
      }
      // —— 核心：E2 荆棘藤（先于尖刺画，尖刺压在藤上）
      if (core) for (const vn of vines) {
        const u = t + 0.03 - vn.d;
        if (u < 0) continue;
        const g = clamp(u / 0.08), k = 1 - smooth(0.2, 0.34 + TAIL * 0.5, u);
        if (k <= 0) continue;
        const Pt = (v) => { const w = 1 - v; return [w * w * vn.s0.x + 2 * w * v * vn.cx + v * v * vn.s1.x, w * w * vn.s0.y + 2 * w * v * vn.cy + v * v * vn.s1.y]; };
        const hot = u < 0.06 ? 4 : u < 0.12 ? 3 : 2;   // 首帧亮红，之后压回暗红（不到敌方危险色 #ff2667 的亮粉红）
        for (let v = 0; v <= g; v += 0.012) {
          if (Math.abs(v - vn.gap) < vn.gw) continue;   // 断口
          const [x, y] = Pt(v), wob = 0.7 * noise(v * 9 + vn.gap * 7, o.seed + 13);
          p.blend(x, y + wob, E[hot], 0.95 * k);
          p.blend(x, y + wob + 1, E[clamp(hot - 2, 1, 4)], 0.8 * k);   // 藤两像素粗，下沿暗一档
        }
        for (const [bv, sd, bl] of vn.barbs) {
          if (bv > g || Math.abs(bv - vn.gap) < vn.gw) continue;
          const [x0, y0] = Pt(bv), [x1, y1] = Pt(Math.min(1, bv + 0.02)), tx = x1 - x0, ty = y1 - y0, tl = Math.hypot(tx, ty) || 1;
          p.line(x0, y0, x0 + (ty / tl * sd + tx / tl * 0.5) * bl, y0 + (-tx / tl * sd + ty / tl * 0.5) * bl * 0.8 - 0.5, E[clamp(hot, 2, 3)], 0.9 * k);
        }
        if (deco && el >= 2) for (let v = 0.1; v < 0.95; v += 0.3) { const [x, y] = Pt(v); p.glow(x, y, 6, E[3], 0.12 * k); }   // 光沿藤走（原作红光晕），不画中心圆光
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
