// 维什戴尔炮击落点（D 组）：@2x 密度，原点 = 落点，8 帧 @20。同名替换 Codex fx_wisadel_cannon（seg_wisadel 按「实心半径 37 美术像素 = 74 贴图像素」换算缩放，tests 按名字查）。
// 她的红色尖晶爆裂：首帧只有一个小的暖白芯（偏橙，不进敌方品红区），随后实心爆团撑到半径 74、一圈长短 / 角度 / 粗细都随机的暗红尖晶刺出，
// 冷却成暗红、晶刺从尖端碎掉，黑烟不规整地翻开，最后留几粒余烬。按 docs/220 收特效口径：不画蓝环、不画旋涡盘、不画同心圈，亮部只在前两帧。
import { Particles, P, Rng, fit, clamp, ease, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Wisadel cannon",
  desc: "Wisadel's crimson spinel burst: a small warm-white core, a mottled blast with uneven dark-red crystal spikes that cool and break while black smoke rolls out.",
  tags: ["explosion", "crystal", "one-shot"],
  size: [240, 240],
  origin: [120, 120],
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#0c0606", "#240a08", "#3e1814", "#7c2a24", OP.wisadel[2], "#ff5a3a", "#ffb08a", "#fff0e0"], core: 74, seed: 8 },
};

export function create(o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed), CORE = o.core;
  const ps = new Particles({ rng: R, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  // 晶刺：角度间距随机（0.25–0.8 rad）、长短 0.25–0.55 × 实心半径、粗细不一
  const spikes = [];
  for (let a = R.range(0, 0.5); a < TAU - 0.2; a += R.chance(0.3) ? R.range(0.12, 0.25) : R.range(0.4, 1.1)) spikes.push({ a: a + R.range(-0.1, 0.1), L: CORE * (R.chance(0.3) ? R.range(0.95, 1.15) : R.range(1.2, 1.55)), w: R.range(4, 13), d: R.range(0, 0.05) });
  for (let i = 0; i < 10; i++) { const a = R.range(0, TAU); ps.spawn(P.SPARK, Math.cos(a) * 20, Math.sin(a) * 20, Math.cos(a) * R.range(200, 380), Math.sin(a) * R.range(200, 380), R.range(0.08, 0.18)); }
  for (let i = 0; i < 9; i++) { const a = R.range(0, TAU), d = CORE * R.range(0.4, 0.9); ps.spawn(P.SMOKE, Math.cos(a) * d, Math.sin(a) * d, Math.cos(a) * 40, Math.sin(a) * 40 - 20, R.range(0.22, 0.32), 0, R.range(10, 18), R.range(0.05, 0.12)); }
  const embers = [];
  for (let i = 0; i < 7; i++) { const a = R.range(0, TAU), d = CORE * R.range(0.15, 0.7); embers.push([Math.cos(a) * d, Math.sin(a) * d]); }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      ps.draw(p, "back");
      const grow = ease.outQuart(clamp(t / 0.1)), cool = clamp((t - 0.08) / 0.24);
      // 实心爆团：外缘按噪声起伏，芯往外由亮到暗；首帧只是小暖白芯
      const rr = t < 0.03 ? CORE * 0.4 : CORE * (0.75 + 0.25 * grow) * (1 - cool * 0.35);
      if (cool < 1) {
        const B = Math.ceil(rr * 1.15);
        for (let y = -B; y <= B; y++)
          for (let x = -B; x <= B; x++) {
            const a = Math.atan2(y, x), edge = rr * (0.9 + 0.12 * noise(a * 3, o.seed)) + 3 * noise(a * 11, o.seed + 3), d = Math.hypot(x, y);
            if (d > edge) continue;
            const q = d / edge;
            const qn = q + 0.22 * noise(x * 0.09, y * 0.09 + o.seed);   // 斑驳，免得色阶排成同心圈
            const ci = t < 0.03 ? (q < 0.6 ? 7 : 6) : clamp(Math.round(6 - qn * 3 - cool * 4.5 - (t < 0.06 ? 0 : 0.6)), 1, 7);
            if (cool > 0.55 && noise(x * 0.12, y * 0.12 + 5) < cool * 1.6 - 1.1) continue;   // 冷却后期碎成块散掉
            p.px(x, y, C[ci]);
          }
      }
      // 晶刺：从实心边刺出，冷却时从尖端往回碎
      if (t >= 0.03)
        for (const s of spikes) {
          const u = clamp((t - 0.03 - s.d) / 0.06);
          if (u <= 0) continue;
          const L = s.L * ease.outBack(u) * (1 - clamp((t - 0.2) / 0.15) * 0.7), base = rr * 0.7;
          if (L <= base + 2) continue;
          const ca = Math.cos(s.a), sa = Math.sin(s.a), nx = -sa, ny = ca;
          const tip = [ca * L, sa * L], b0 = [ca * base + nx * s.w, sa * base + ny * s.w], b1 = [ca * base - nx * s.w, sa * base - ny * s.w];
          const lit = clamp(Math.round(5 - cool * 3), 2, 6);
          p.tri(tip[0], tip[1], b0[0], b0[1], ca * base, sa * base, C[lit]);
          p.tri(tip[0], tip[1], b1[0], b1[1], ca * base, sa * base, C[Math.max(1, lit - 2)]);
          p.line(ca * base, sa * base, tip[0], tip[1], C[Math.min(7, lit + 1)]);
        }
      if (t > 0.22 && t < 0.36) for (const [x, y] of embers) if (noise(x, y + t * 30) > -0.2) p.px(x, y, C[t < 0.32 ? 5 : 4]);
      if (t < 0.1) p.glow(0, 0, CORE * 0.8, C[5], 0.25 * (1 - t / 0.1));
      ps.draw(p, "front");
    },
  };
}
