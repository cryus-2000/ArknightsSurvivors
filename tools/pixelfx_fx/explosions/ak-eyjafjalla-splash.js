// 艾雅法拉熔岩弹落地溅射（docs/229 技能档）：@2x，1 贴图像素 = 1 世界像素，原点 = 落点（地面），地面透视 sy 0.55。
// 熔岩团砸在地上先白热摊开，边上掀起几条高矮不一、角度不等距的熔岩舌，舌尖断成熔滴落回地面；
// 地上那摊按色阶冷却后按噪声溶解（不用棋盘格）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla lava splash",
  desc: "A lava blob lands: a white-hot splat spreads on the floor, uneven tongues of lava jump up from its rim and break into drops that fall back, the puddle cools and dissolves.",
  tags: ["explosion", "lava", "splash", "ground", "one-shot"],
  size: [96, 72],
  origin: [48, 44],
  duration: 0.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.eyjafjalla, radius: 26, seed: 8 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), R = o.radius, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 3, sparks: [C[6], C[5], C[4], C[2]] });
  const tongues = [];
  for (let a = Rg.range(0, 0.8); a < TAU - 0.4; a += Rg.range(0.6, 1.4))
    tongues.push({ a, h: Rg.range(8, 20) * (Math.sin(a) < 0 ? 0.8 : 1), w: Rg.range(1.5, 3), lean: Rg.range(0.3, 0.8), d: Rg.range(0, 0.04), broke: false });
  let t = 0;
  const spread = () => R * (0.35 + 0.65 * ease.outQuart(clamp(t / 0.08)));
  function puddle(p, far) {
    const k = 1 - smooth(0.18, 0.38, t), rs = spread() * (1 - 0.3 * smooth(0.12, 0.38, t));   // 冷却时往里收
    if (k <= 0) return;
    p.shade(-rs * 1.3, -rs * SY * 1.3, rs * 1.3, rs * SY * 1.3, (x, y) => {
      if ((y < 0) !== far) return;
      const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (rs * (1 + 0.25 * noise(a * 2.9, S) + 0.1 * noise(a * 7.3, S + 2)));
      if (d > 1) return;
      if (noise2(x * 0.3, y * 0.5, S + 9) * 0.5 + 0.5 > k + 0.25) return;
      // 冷却时留几道发亮的熔岩纹（噪声，不规整）
      const vein = Math.max(0, noise2(x * 0.22 + 3, y * 0.4, S + 5)) * 2.2;
      const ci = t < 0.04 ? clamp(Math.round(6.8 - d * 1.4), 5, 6) : clamp(Math.round(5.6 - t / 0.05 * 0.9 - d * 2 + vein), 1, 6);
      p.blend(x, y, C[ci], ci <= 2 ? 0.7 : 1);
    });
  }
  function tongue(p, s) {
    const tt = t - s.d, rise = ease.outCubic(clamp(tt / 0.1)), fall = smooth(0.1, 0.2, tt);
    if (tt < 0.02 || fall >= 1) return;
    const rs = spread() * 0.85, bx = Math.cos(s.a) * rs, by = Math.sin(s.a) * rs * SY, h = s.h * rise * (1 - fall);
    for (let d = 0; d <= h; d += 0.5) {
      const v = d / Math.max(1, h), w = s.w * (1 - v * 0.8);
      const x = bx + Math.cos(s.a) * d * s.lean, y = by - d;
      const ci = clamp(Math.round(6 - tt / 0.05 * 0.8 - (1 - v) * 1.5), 2, 6);
      for (let q = -w; q <= w; q += 1) p.px(x + q * 0.6, y, C[ci]);
    }
  }
  return {
    update(dt) {
      t += dt;
      for (const s of tongues)
        if (!s.broke && t - s.d > 0.1) {
          s.broke = true;
          const rs = spread() * 0.85, x = Math.cos(s.a) * rs + Math.cos(s.a) * s.h * s.lean, y = Math.sin(s.a) * rs * SY - s.h;
          for (let i = 0; i < 2; i++) ps.spawn(P.SPARK, x, y, Math.cos(s.a) * Rg.range(20, 70), -Rg.range(20, 90), Rg.range(0.15, 0.25));
        }
      ps.update(dt);
    },
    drawBack(p) {
      puddle(p, true);
      for (const s of tongues) if (Math.sin(s.a) < 0) tongue(p, s);
      ps.draw(p, "back");
    },
    draw(p) {
      puddle(p, false);
      for (const s of tongues) if (Math.sin(s.a) >= 0) tongue(p, s);
      p.glow(0, 0, R * 0.6, C[4], 0.25 * clamp(t / 0.04) * (1 - clamp(t / 0.2)));
      ps.draw(p, "front");
    },
  };
}
