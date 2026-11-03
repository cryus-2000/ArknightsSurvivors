// 星熊技能起手提示（docs/242 §12.1；px_ul.json cast，技能开启那一刻在脚下播）：原点 = 星熊脚底，俯视 sy 0.55，0.5 s。
// kind：1 = S1 战意（盾面钢色印 + 几道往盾心聚拢的短亮线）；2 = S2 荆棘（脚边一圈高矮不一、间距不等的钢刺扎出又缩回）；
//       3 = S3 力之锯（脚下一圈青绿鬼火窜起，盾形印由白转翠绿）。精英档：E1 起印边带暗红细线（反击架势），E2 起印 / 刺尖转翠绿（般若）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Hoshiguma skill cast cue",
  desc: "Skill cast cue at her feet: a steel shield sigil with gathering glints (S1), a ring of uneven steel thorns (S2), or teal ghost flames igniting round a shield sigil (S3).",
  tags: ["holy", "cast", "one-shot"],
  size: [112, 96],
  origin: [56, 66],
  duration: 0.55,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // 钢色（PRTS 黑钢盾），不用金（§12.6）
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    kind: 1,
    elite: 2,
    layer: "all",
    seed: 5,
  },
};

const SY = 0.55, V = [[-15, -11], [15, -11], [1, 14]];

export function create(o) {
  const C = fit(o.palette, 7), J = fit(o.jade, 5), E = fit(o.ember, 5), Rg = new Rng(o.seed);
  const kind = +o.kind, el = +o.elite, core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  const thorns = jitterAngles(Rg, Rg.int(8, 11), 0, Math.PI * 2, 0.45).map((a) => ({ a, r: Rg.range(22, 34), h: Rg.range(7, 16), w: Rg.range(1.2, 2.4), d: Rg.range(0, 0.08), lean: Rg.range(0.15, 0.5) }));
  const flames = jitterAngles(Rg, Rg.int(7, 10), 0, Math.PI * 2, 0.45).map((a) => ({ a, r: Rg.range(14, 30), h: Rg.range(8, 20), d: Rg.range(0, 0.12), ph: Rg.range(0, 6) }));
  let t = 0, fired = false;
  const sigil = (p, k, y0) => {   // 般若倒三角印：白热 → 钢色（E2 / S3 转翠绿），E1 起外缘暗红
    for (let i = 0; i < 3; i++) {
      const [x0, ya] = V[i], [x1, yb] = V[(i + 1) % 3];
      const c = t < 0.06 ? C[6] : (kind === 3 || el >= 2) ? J[clamp(Math.round(4 - t * 5), 2, 4)] : C[clamp(Math.round(5 - t * 6), 2, 5)];
      p.line(x0, ya * SY + y0, x1, yb * SY + y0, c, k);
      if (el >= 1) p.line(x0 * 1.12, ya * SY * 1.12 + y0, x1 * 1.12, yb * SY * 1.12 + y0, E[3], 0.7 * k);
    }
  };
  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        if (deco) for (let i = 0; i < 8; i++) { const a = Rg.range(0, Math.PI * 2), sp = Rg.range(40, 110); ps.spawn(P.SPARK, Math.cos(a) * 10, Math.sin(a) * 6, Math.cos(a) * sp, Math.sin(a) * sp * SY - 50, Rg.range(0.12, 0.25), 0, 1, Rg.range(0, 0.06)); }
      }
      ps.update(dt);
    },
    draw(p) {
      const fade = 1 - smooth(0.25, 0.5, t);
      if (kind === 1 && core) {   // 往盾心聚拢的短亮线（蓄势），长短 / 角度不等
        const g = clamp(t / 0.15);
        for (const a of [0.4, 1.3, 2.1, 3.3, 4.5, 5.4]) {
          const r0 = 34 * (1 - g * 0.6) + 4 * Math.sin(a * 2.7), r1 = r0 * 0.55;
          if (t < 0.2) p.line(Math.cos(a) * r0, Math.sin(a) * r0 * SY - 10, Math.cos(a) * r1, Math.sin(a) * r1 * SY - 10, C[5], 0.85);
        }
      }
      if (kind === 2 && core) for (const s of thorns) {   // 一圈钢刺：扎出 → 停 → 缩回
        const u = t + 0.03 - s.d, up = ease.outBack(clamp(u / 0.07)) * (1 - smooth(0.2, 0.4, u)), H = s.h * up;
        if (u < 0 || H < 1) continue;
        const bx = Math.cos(s.a) * s.r, by = Math.sin(s.a) * s.r * SY;
        for (let d = 0; d <= H; d += 0.5) {
          const v = d / H, hw = s.w * (1 - v);
          for (let e = -hw; e <= hw; e += 0.6) {
            const c = el >= 2 && v > 0.65 ? J[clamp(Math.round(2 + v * 2.5), 1, 4)] : C[clamp(Math.round(2 + v * 3 + (u < 0.05 && v > 0.7 ? 1 : 0)), 1, 5)];
            p.blend(bx + Math.cos(s.a) * d * s.lean + e, by - d, c, 1);
          }
        }
      }
      if (kind === 3 && deco) for (const f of flames) {   // 脚下一圈青绿鬼火窜起
        const u = t - f.d, life = clamp(u / 0.06) * (1 - smooth(0.15, 0.45, u)), H = f.h * life;
        if (u < 0 || H < 1) continue;
        const bx = Math.cos(f.a) * f.r, by = Math.sin(f.a) * f.r * SY;
        for (let d = 0; d < H; d += 0.5) {
          const v = d / H, sway = 2 * noise(f.ph + d * 0.2 + u * 9, o.seed) * v;
          for (let e = -(1.4 - 1.1 * v); e <= 1.4 - 1.1 * v; e += 0.7) p.blend(bx + sway + e, by - d, J[clamp(Math.round(4 - v * 2.6 - Math.abs(e) * 0.6), 1, 4)], (0.85 - v * 0.5) * life);
        }
      }
      if (core && fade > 0 && (kind === 1 || kind === 3)) sigil(p, fade, kind === 1 ? -10 : 0);
      if (deco) { p.glow(0, -6, 26, kind === 3 ? J[3] : C[4], 0.25 * fade); ps.draw(p); }
    },
  };
}
