// 逻各斯 S3 墨柱（docs/229 技能档）：@2x，1 贴图像素 = 1 世界像素，原点 = 脚底，柱高 height。
// 一道墨从地面往上卷起：首帧整根白紫爆亮，之后墨身冷成深墨、两侧各一道紫亮的边，边按噪声扭动、粗细不一；
// 墨柱从顶上开始散成墨滴往下落，脚下洇开一小摊墨（透视 sy 0.55），最后按噪声干涸。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2 } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos ink pillar",
  desc: "A column of ink curls up from the floor, flashes pale violet, cools to deep ink with writhing violet edges, then frays from the top into falling drops.",
  tags: ["arcane", "ink", "pillar", "one-shot"],
  size: [80, 300],
  origin: [40, 150],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.logos, height: 130, seed: 3 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), H = o.height, S = o.seed, W = Math.max(5, H * 0.07);
  const ps = new Particles({ rng: Rg, ground: () => 2, sparks: [C[4], C[3], C[2], C[1]] });
  let t = 0, frayed = false;
  const sway = (y) => 3 * noise(y * 0.03 + t * 7, S) * (-y / H);
  return {
    update(dt) {
      t += dt;
      if (!frayed && t > 0.3) {
        frayed = true;
        for (let i = 0; i < 9; i++) {
          const y = -H * Rg.range(0.45, 0.95);
          ps.spawn(P.SPARK, sway(y) + Rg.range(-W, W), y, Rg.range(-30, 30), Rg.range(-20, 30), Rg.range(0.15, 0.25));
        }
      }
      ps.update(dt);
    },
    drawBack(p) {
      const k = 1 - smooth(0.3, 0.58, t), r = W * 3;
      if (k <= 0) return;
      p.shade(-r * 1.3, -r * SY * 1.3, r * 1.3, r * SY * 1.3, (x, y) => {
        const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (r * (1 + 0.25 * noise(a * 2.9, S + 1)) * (0.5 + 0.5 * ease.outQuart(clamp(t / 0.15))));
        if (d > 1) return;
        if (noise2(x * 0.25, y * 0.45, S + 2) * 0.5 + 0.5 > k + 0.25) return;
        p.blend(x, y, C[d > 0.85 ? 3 : 1], d > 0.85 ? 0.9 : 0.7);
      });
    },
    draw(p) {
      const top = -H * (0.6 + 0.4 * ease.outQuart(clamp(t / 0.1)));
      const fray = -H + H * ease.inCubic(smooth(0.28, 0.58, t));   // 顶上往下散
      const w0 = W * (1 - 0.35 * smooth(0.1, 0.5, t)) + (t < 0.04 ? 2 : 0);
      for (let y = Math.floor(Math.max(top, fray)); y < 0; y++) {
        const v = -y / H, cx = sway(y);
        const tip = Math.pow(clamp((y - top) / (H * 0.2)), 0.6);
        const wl = w0 * tip * (0.75 + 0.45 * (0.5 + 0.5 * noise(y * 0.09 + t * 11, S + 4)));
        const wr = w0 * tip * (0.75 + 0.45 * (0.5 + 0.5 * noise(y * 0.09 - t * 9, S + 6)));
        for (let x = Math.floor(cx - wl); x <= Math.ceil(cx + wr); x++) {
          const q = x < cx ? (cx - x) / wl : (x - cx) / wr;
          if (q > 1) continue;
          if (y < fray + 8 && noise2(x * 0.5, y * 0.5, S + 8) * 0.5 + 0.5 > (y - fray) / 8) continue;   // 散开的断口按噪声
          const edge = q > 0.72;
          const ci = t < 0.04 ? clamp(Math.round(6.6 - q * 1.6), 4, 6) : edge ? clamp(Math.round(5.2 - t / 0.05 * 0.45 - v * 0.6), 2, 5) : clamp(Math.round(1.6 - t / 0.2 + (1 - q) * 0.6), 0, 2);
          p.blend(x, y, C[ci], edge ? 0.95 : 0.85);
        }
      }
      if (t < 0.1) p.glow(0, -H * 0.4, W * 3, C[4], 0.28 * (1 - t / 0.1));
      ps.draw(p);
    },
  };
}
