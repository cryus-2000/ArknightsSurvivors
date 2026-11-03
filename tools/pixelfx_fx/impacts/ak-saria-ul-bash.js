// 塞雷娅盾击（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：俯视，原点 = 塞雷娅，正右为出拳方向，游戏里按方向旋转。
// 一记钝重的琥珀冲击：盾面爆亮 → 一道厚的弧形冲击波往前推（中间厚、两头薄、外缘按噪声起伏）→ 琥珀碎屑朝前甩 → 尘土 + 余光慢慢散。
import { Particles, Lights, Bits, B, P, Rng, fit, clamp, smooth, ease, noise, hex, sparkle } from "../../core/index.js";

export const meta = {
  name: "Saria shield bash unleashed",
  desc: "A heavy amber shield bash seen from above: the shield face flashes, a thick ragged shock front shoves forward, amber chips and grit spray ahead and dust settles.",
  tags: ["impact", "bash", "shield", "amber", "topdown", "one-shot"],
  size: [200, 160],
  origin: [56, 80],
  duration: 0.75,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#241004", "#52260a", "#8e4510", "#cc7418", "#f2aa3c", "#ffd77e", "#fff2cf", "#ffffff"],
    layer: "all", reach: 62,
    seed: 6,
  },
};

const PUSH = 0.12, SPAN = 1.25;

export function create(o) {
  const C = fit(o.palette, 8), R = o.palette, Rg = new Rng(o.seed), L = o.reach;
  const core = o.layer !== "deco", deco = o.layer !== "core";   // 分层（docs/242 §8）
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  const bits = new Bits({ ground: () => 1e9 });
  lights.add(10, 0, 50, C[6], 1.0, 0.25);
  for (let i = 0; i < 18; i++) {
    const a = Rg.range(-0.7, 0.7), sp = Rg.range(140, 360);
    ps.spawn(P.SPARK, 14, Rg.range(-6, 6), Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.15, 0.4));
  }
  for (let i = 0; i < 10; i++) {
    const a = Rg.range(-0.6, 0.6), sp = Rg.range(90, 220);
    bits.add({ kind: B.SHARD, x: 16, y: Rg.range(-8, 8), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, a: Rg.range(0, 6.28), va: Rg.range(-16, 16), s: Rg.range(2.5, 4.5),
      c: hex(R[Rg.int(3, 6)]), g: 0, drag: 2.2, bounce: 0, life: Rg.range(0.35, 0.6) });
  }
  for (let i = 0; i < 9; i++) {
    const a = Rg.range(-0.9, 0.9), d = Rg.range(10, 30);
    ps.spawn(P.DUST, Math.cos(a) * d + 8, Math.sin(a) * d, Math.cos(a) * Rg.range(30, 70), Math.sin(a) * Rg.range(30, 70), Rg.range(0.45, 0.7), C[2], Rg.range(4, 8), Rg.range(0.02, 0.08));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); bits.update(dt); lights.update(dt); },
    drawBack(p) { if (deco) ps.draw(p, "back"); },
    draw(p) {
      // 冲击波：半径从 12 推到 L，厚度中间最厚；第 1 帧白热，之后外缘白、里面逐级变深，推完散掉
      const r = 12 + (L - 12) * ease.outQuart(clamp(t / PUSH)), fade = 1 - smooth(PUSH, 0.42, t), W = 22 * (1 - 0.5 * clamp(t / 0.4));
      if (core && fade > 0) p.shade(0, -L - 6, L + 8, L + 6, (x, y, out) => {
        const a = Math.atan2(y, x);
        if (Math.abs(a) > SPAN / 2) return;
        const v = Math.abs(a) / (SPAN / 2), jag = 3 * noise(a * 7 + t * 4, o.seed);
        const w = W * Math.pow(1 - v * v, 0.6) * fade;
        const q = (r + jag - Math.hypot(x, y)) / Math.max(w, 0.5);
        if (q < 0 || q > 1) return;
        const hot = t < 0.05 ? 3 : t < 0.1 ? 1 : 0;
        out.c = C[clamp(Math.round(7 - q * 4.5 - (1 - fade) * 3 - v * 1.5 + hot), 1, 7)];
      });
      if (deco) p.glow(r * 0.7, 0, 30 + r * 0.3, C[5], 0.45 * fade);
      // 盾面爆亮
      if (t < 0.1) {
        const k = 1 - t / 0.1;
        if (core) p.disc(10, 0, 12 * k + 4, C[7], 0.9);
        if (deco) sparkle(p, 14, 0, 18 * k, C[7], C[5], 0.8);
      }
      if (deco) {
        bits.draw(p);
        ps.draw(p, "front");
        lights.draw(p);
      }
    },
  };
}
