// 塞雷娅「钙质化」琥珀晶簇（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 晶簇脚底。
// phase: grow（0.4 s，从地里一根根顶出来）/ idle（1.6 s 循环，光沿刻面扫过、琥珀微光上飘）/ break（0.6 s，裂开爆亮、碎片翻滚落地）。
// 琥珀：深棕 → 橙 → 蜜黄 → 白；刻面有明暗、顶端白，半透明的是光晕不是晶体（晶体不透明，读得清）。
import { Particles, Lights, Bits, B, P, Rng, fit, clamp, smooth, ease, crystal, sparkle, hex, TAU } from "../../core/index.js";

export const meta = {
  name: "Saria calcite unleashed",
  desc: "An amber calcite cluster: faceted crystals punch up from the ground one after another, glints sweep their faces while honey motes rise, then it cracks, flashes and bursts into tumbling shards.",
  tags: ["nature", "crystal", "amber", "calcite", "one-shot"],
  size: [128, 112],
  origin: [64, 88],
  duration: 0.4,   // 各段时长见 DUR；导出用 ak-saria-ul-calcite-{grow,idle,break}.js 包一层改 meta
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#241004", "#52260a", "#8e4510", "#cc7418", "#f2aa3c", "#ffd77e", "#fff2cf", "#ffffff"],
    phase: "grow",
    seed: 4,
  },
};

const DUR = { grow: 0.4, idle: 1.6, break: 0.6 };

export function create(o) {
  const C = fit(o.palette, 8), R = o.palette, Rg = new Rng(o.seed), phase = o.phase;
  const ps = new Particles({ rng: Rg, ground: () => 2, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  const bits = new Bits({ ground: () => 2 });
  // 晶体：中间高、两边矮，往外倾；位置 / 高矮 / 粗细 / 先后都不一样（不等距）
  const xs = [];
  for (let k = 0, n = Rg.int(5, 7); k < n; k++) xs.push(Rg.range(-15, 15));
  xs.sort((a, b) => Math.abs(b) - Math.abs(a));                       // 外圈先画（在后）
  const cr = xs.map((x) => {
    const mid = 1 - Math.min(1, Math.abs(x) / 17);
    return { x, base: Rg.range(-2, 3), h: (12 + 22 * mid) * Rg.range(0.85, 1.15), w: Rg.range(12, 18) * (0.75 + 0.35 * mid), lean: x * Rg.range(0.15, 0.3), d: (1 - mid) * 0.12 + Rg.range(0, 0.06) };
  });
  const dur = DUR[phase] ?? 0.4;
  let t = 0, fired = false;

  if (phase === "grow") {
    lights.add(0, -6, 40, C[5], 0.8, 0.25);
    for (let i = 0; i < 16; i++) ps.spawn(P.GRIT, Rg.range(-20, 20), 0, Rg.range(-60, 60), Rg.range(-140, -40), Rg.range(0.3, 0.5), C[2], 1);
    for (let i = 0; i < 6; i++) ps.spawn(P.DUST, Rg.range(-24, 24), 0, Rg.range(-30, 30), Rg.range(-10, 0), Rg.range(0.3, 0.4), C[1], Rg.range(3, 5));
  }
  return {
    update(dt) {
      t += dt;
      if (phase === "idle" && Rg.chance(dt * 9)) {
        const c = cr[Rg.int(0, cr.length - 1)];
        ps.spawn(P.EMBER, c.x + c.lean * 0.6, c.base - c.h * Rg.range(0.3, 0.9), Rg.range(-6, 6), Rg.range(-30, -12), Rg.range(0.5, 0.9), C[6], 1);
      }
      if (phase === "break" && !fired && t >= 0.05) {
        fired = true;
        lights.add(0, -18, 60, C[6], 1.0, 0.3);
        for (const c of cr) {
          const n = Math.round(2 + c.h / 9);
          for (let i = 0; i < n; i++) {
            const y = c.base - c.h * Rg.range(0.1, 0.9), a = Math.atan2(y + 10, c.x || 0.1) + Rg.range(-0.6, 0.6), sp = Rg.range(60, 180);
            bits.add({ kind: B.SHARD, x: c.x + c.lean * 0.5, y, vx: Math.cos(a) * sp + c.x * 2, vy: -Math.abs(Math.sin(a) * sp) - 40, a: Rg.range(0, TAU), va: Rg.range(-14, 14),
              s: Rg.range(2, 4.5), c: hex(R[Rg.int(3, 6)]), g: 1, drag: 0.6, bounce: 0.3, life: Rg.range(0.4, 0.55) });
          }
        }
        for (let i = 0; i < 24; i++) {
          const a = Rg.range(-Math.PI, 0), sp = Rg.range(80, 240);
          ps.spawn(P.SPARK, Rg.range(-10, 10), -16, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.45));
        }
        for (let i = 0; i < 7; i++) ps.spawn(P.DUST, Rg.range(-22, 22), Rg.range(-4, 0), Rg.range(-40, 40), Rg.range(-20, 0), Rg.range(0.35, 0.5), C[2], Rg.range(4, 7));
      }
      ps.update(dt);
      bits.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      ps.draw(p, "back");
    },
    draw(p) {
      // 脚下一片琥珀色的微光
      const glowK = phase === "break" ? 1 - smooth(0.05, 0.4, t) : 1;
      p.glow(0, -8, 34, C[4], 0.28 * glowK);
      if (phase !== "break" || t < 0.05) {
        const crack = phase === "break" ? 1 : 0;
        for (const c of cr) {
          let k = 1;
          if (phase === "grow") k = ease.outBack(clamp((t - c.d) / 0.18));
          const h = c.h * k;
          if (h < 1.5) continue;
          const glint = phase === "idle" ? ((t / dur + c.x * 0.013) % 1) * 1.4 - 0.2 : phase === "grow" ? 0.95 : -1;
          crystal(p, c.x, c.base, h, c.w, c.lean * k, R, { glint, white: (phase === "grow" && t - c.d < 0.05 && t - c.d > 0) || crack > 0 });
        }
      }
      if (phase === "grow" && t < 0.1) p.disc(0, -2, 8 * (1 - t / 0.1) + 3, C[7], 0.8);
      if (phase === "break" && t < 0.12) p.disc(0, -14, 16 * (1 - t / 0.12) + 5, C[7], 0.85);
      if (phase === "idle") {
        const c = cr[Math.floor((t / dur) * cr.length) % cr.length], g = (t * cr.length / dur) % 1;
        if (g < 0.35) sparkle(p, c.x + c.lean * 0.9, c.base - c.h * 0.92, 6 * Math.sin((g / 0.35) * Math.PI), C[7], C[5], 0.6);
      }
      bits.draw(p);
      ps.draw(p, "front");
      lights.draw(p);
    },
  };
}
