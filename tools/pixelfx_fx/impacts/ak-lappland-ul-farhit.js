// 拉普兰德刀波命中（远掷 / 双生刃 / 日晷·反斩共用，docs/242 放开版，用户 11-03 定第 1 条「命中出白爆星」）：原点 = 命中点，正右 = 刀波飞行方向。
// 原作 whitew_attack_02_hit：一下白色爆星（star_19 / star_02），几道细刺迸出。本作写成不规则的星：5–7 根长短不一的细刺，
// 多数顺着飞行方向往前、少数往回，中心 1 帧白芯（只 1 帧，§1 爆亮帧口径），之后刺尖先收、根部最后暗掉。不是圆点、不是同心圈（§12.3）。
// 分层：core = 刺、白芯；deco = 两三粒往前溅的亮屑。11-04 用户否决发散光晕：刺根淡光删掉。
import { Rng, fit, clamp } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Lappland blade hit star",
  desc: "An irregular white burst star: five to seven thin uneven spikes mostly thrown forward along the blade's travel, a one-frame white core, tips retract first.",
  tags: ["impact", "star", "topdown", "one-shot"],
  size: [48, 40],
  origin: [20, 20],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 21,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const n = 5 + el;
  const spikes = jitterAngles(Rg, n, -1.2, 1.2, 0.5).map((a, i) => ({ a: i % 4 === 3 ? a + Math.PI : a, L: Rg.range(7, 13) * (Math.abs(a) < 0.5 ? 1.35 : 1) * (i % 4 === 3 ? 0.6 : 1) }));
  const flecks = Array.from({ length: quick ? 1 : 2 + el }, () => ({ a: Rg.range(-0.6, 0.6), sp: Rg.range(50, 90) }));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const u = clamp(t / 0.3);
      if (core) {
        if (t < 0.05) { p.dot(0, 0, C[6]); p.dot(1, 0, C[6]); p.dot(0, -1, C[6]); p.dot(0, 1, C[5]); p.dot(-1, 0, C[5]); }
        for (const s of spikes) {
          const grow = clamp(t / 0.06), tip = s.L * grow * (1 - clamp((t - 0.08) / 0.18));   // 刺尖先长出、再从外往里收
          const root = 1 + s.L * 0.35 * clamp((t - 0.14) / 0.14);
          if (tip <= root) continue;
          const ca = Math.cos(s.a), sa = Math.sin(s.a);
          p.line(Math.round(ca * root), Math.round(sa * root), Math.round(ca * tip), Math.round(sa * tip), C[t < 0.1 ? 6 : t < 0.18 ? 5 : 3]);
        }
      }
      if (deco) for (const f of flecks) {
        const d = f.sp * t;
        if (u < 0.85) p.blend(Math.round(Math.cos(f.a) * d), Math.round(Math.sin(f.a) * d), C[5], 1 - u);
      }
    },
  };
}
