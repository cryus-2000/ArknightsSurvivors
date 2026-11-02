// 安洁莉娜「引力」收束（docs/229 技能档，地面层）：@2x，画布与旧 fx_angelina_pull 同为 128×64（同 fit 30 不改缩放），原点 = 中心，透视 sy 0.5。
// 首帧外沿一道不规整的紫圈爆亮，随即碎成长短不一的弧线，沿螺旋往中心卷（角度、半径、速度都随机，不等距），
// 越近越亮；卷到中心挤成一个小亮点，再散成几粒光尘。不画同心圈。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Angelina pull",
  desc: "A ragged violet ring flares on the floor, breaks into arcs of uneven length that spiral in, brightening as they close, and squeeze into a spark.",
  tags: ["arcane", "gravity", "pull", "floor", "one-shot"],
  size: [128, 64],
  origin: [64, 32],
  duration: 0.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.angelina, radius: 54, seed: 7 },
};

const SY = 0.5;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), R = o.radius, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  const arcs = [];
  for (let a = Rg.range(0, 0.4); a < TAU - 0.2; a += Rg.range(0.35, 0.95))
    arcs.push({ a, len: Rg.range(0.25, 0.7), r0: R * Rg.range(0.82, 1.02), sp: Rg.range(0.75, 1.0), twist: Rg.range(1.2, 2.2), d: Rg.range(0, 0.06) });
  let t = 0, popped = false;
  return {
    update(dt) {
      t += dt;
      if (!popped && t > 0.29) {
        popped = true;
        for (let i = 0; i < 6; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(25, 70);
          ps.spawn(P.FLAKE, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp * SY - 15, Rg.range(0.05, 0.08), Rg.pick([C[6], C[5], C[4]]), 1);
        }
      }
      ps.update(dt);
    },
    draw(p) {
      // 首帧：外沿一整道不规整的圈
      if (t < 0.04)
        for (let a = 0; a < TAU; a += 0.6 / R) {
          const r = R * (1 + 0.06 * noise(a * 4.3, S) + 0.04 * noise(a * 11, S + 2));
          p.px(Math.cos(a) * r, Math.sin(a) * r * SY, C[5]);
          p.px(Math.cos(a) * (r - 1.5), Math.sin(a) * (r - 1.5) * SY, C[3]);
        }
      // 弧线沿螺旋往里卷：u 0 → 1 收到中心
      for (const s of arcs) {
        const u = ease.inQuad(clamp((t - 0.03 - s.d) / (0.27 * s.sp)));
        if (u >= 1 || t < 0.03) continue;
        const r = s.r0 * (1 - u), rot = s.twist * u, L = s.len * (1 - 0.6 * u);
        for (let k = 0; k <= 1; k += 0.6 / Math.max(8, r * L)) {
          const a = s.a + rot + k * L, rr = r * (1 + 0.15 * k);
          // 头亮尾暗，越靠中心越亮
          const ci = clamp(Math.round(2.5 + u * 2 - k * 2.5), 1, 4);
          p.px(Math.cos(a) * rr, Math.sin(a) * rr * SY, C[ci]);
          if (k < 0.5) p.px(Math.cos(a) * (rr - 1.2), Math.sin(a) * (rr - 1.2) * SY, C[Math.max(1, ci - 1)]);   // 弧头加粗一像素
        }
      }
      // 中心亮点：收拢时变亮，0.3 s 后散掉
      const g = smooth(0.12, 0.28, t) * (1 - smooth(0.3, 0.36, t));
      if (g > 0) {
        const r = 1 + 3 * g;
        p.ellipse(0, 0, r, r * SY + 0.5, C[g > 0.6 ? 6 : 5]);
        p.glow(0, 0, 10, C[4], 0.28 * g);
      }
      ps.draw(p);
    },
  };
}
