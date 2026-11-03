// 塞雷娅「急救 / 药物配置」治疗（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 被治疗者脚底。
// 脚下一记暖光 → 一道窄的琥珀光柱升起又收 → 琥珀晶屑和光十字从脚下螺旋着往上飘、一闪一闪（位置 / 先后 / 大小都不等）。
// 分层（docs/242 §8）：core = 光柱 + 首帧暖白闪 + 上升的光十字；deco = 光晕、晶屑颗粒、闪烁。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, sparkle, TAU } from "../../core/index.js";

export const meta = {
  name: "Saria heal unleashed",
  desc: "An amber heal: warm light blooms at the feet, a narrow pillar rises and folds away, amber flakes and little light crosses spiral upward and twinkle out.",
  tags: ["holy", "heal", "amber", "one-shot"],
  size: [96, 136],
  origin: [48, 120],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#241004", "#52260a", "#8e4510", "#cc7418", "#f2aa3c", "#ffd77e", "#fff2cf", "#ffffff"], layer: "all", seed: 5 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, haze: C[4] }), lights = new Lights();
  lights.add(0, -10, 36, C[5], 0.8, 0.4);
  // 上升的光十字：起点、速度、出现先后、大小都随机（不等距）
  const crosses = [];
  for (let i = 0, n = Rg.int(5, 7); i < n; i++)
    crosses.push({ a: Rg.range(0, TAU), r: Rg.range(6, 16), v: Rg.range(50, 90), d: Rg.range(0, 0.3), s: Rg.range(2, 4), w: Rg.range(3, 6) });
  for (let i = 0; i < 18; i++) {
    const a = Rg.range(0, TAU), r = Rg.range(4, 18);
    ps.spawn(i % 3 ? P.EMBER : P.STAR, Math.cos(a) * r, Math.sin(a) * r * 0.5 - 2, Rg.range(-8, 8), Rg.range(-70, -30), Rg.range(0.5, 0.95), C[5 + Rg.int(0, 2)], Rg.range(1, 2), Rg.range(0, 0.35));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    drawBack(p) {
      if (deco) p.glow(0, -6, 30, C[4], 0.4 * (1 - smooth(0.2, 0.9, t)));
    },
    draw(p) {
      if (core) {
        // 光柱：升起 0.12 s，停一会儿，往中间收窄消失；中间白、两侧琥珀
        const up = ease.outQuart(clamp(t / 0.12)), fold = smooth(0.25, 0.6, t), H = 96 * up, W = 7 * (1 - fold);
        if (W > 0.4)
          for (let y = 0; y <= H; y += 1) {
            const v = y / Math.max(H, 1), w = W * (1 - 0.6 * v);
            for (let x = -w; x <= w; x += 0.5) {
              const q = Math.abs(x) / Math.max(w, 0.5), ci = clamp(Math.round(7 - q * 3 - v * 2 - fold * 2), 2, 7);
              p.px(x, -y, C[ci]);
            }
          }
        if (t < 0.08) p.disc(0, -4, 10 * (1 - t / 0.08) + 4, C[7], 0.9);
        for (const c of crosses) {
          const u = t - c.d;
          if (u <= 0 || u > 0.7) continue;
          const k = Math.sin((u / 0.7) * Math.PI), a = c.a + u * 3;
          const x = Math.cos(a) * c.r, y = -u * c.v - 8 + Math.sin(a) * c.r * 0.4, L = Math.round(c.s * k);
          for (let d = -L; d <= L; d++) (p.px(x + d, y, C[Math.abs(d) < 1 ? 7 : 5]), p.px(x, y + d, C[Math.abs(d) < 1 ? 7 : 5]));
        }
      }
      if (deco) {
        for (const c of crosses) {
          const u = t - c.d;
          if (u > 0.2 && u < 0.5) sparkle(p, Math.cos(c.a + u * 3) * c.r, -u * c.v - 8, c.w * Math.sin(((u - 0.2) / 0.3) * Math.PI), C[7], C[5], 0.5);
        }
        ps.draw(p, "front");
        lights.draw(p);
      }
    },
  };
}
