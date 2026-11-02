// 斯卡蒂「跃浪」浪墙（docs/229 §7 第 2 批）：俯视，原点 = 浪墙中心，正右为推进方向，游戏里按方向旋转、帧号跟推进进度走。
// 整幅一道浪墙（替代旧版三块同样的浪并排）：前缘是一条噪声起伏的白色浪头，身后是逐级变深的水体和拖出的水痕，
// 两端比中间靠后（同判定 -dir × u² × 16）；走到后段浪头碎成浪沫和水珠。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";

export const meta = {
  name: "Skadi wave wall",
  desc: "Top-down advancing wave wall: one ragged white crest across the whole width, deep-sea water body and wake behind it, breaking into foam and droplets at the end.",
  tags: ["water", "wave", "wall", "topdown", "one-shot"],
  size: [96, 96],
  origin: [56, 48],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    half: 35,        // 半宽（1x 像素）：判定宽 140 世界像素 / 2 / 2
    seed: 5,
  },
};

const BREAK = 0.3;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), HW = o.half;
  const W = C[C.length - 1]; for (let i = 6; i < C.length; i++) C[i] = C[5];   // 近白 ≤ 12%（docs/229 §2.4）：本体只到第 5 阶，白只留核心（W）
  const ps = new Particles({ rng: Rg, ground: () => 1e9, haze: C[4] }), lights = new Lights();
  // 浪墙沿 y 方向；s = y / HW ∈ [-1, 1]。前缘 x：两端靠后，按噪声起伏（不等距）
  const lip = (s, t) => -8 * s * s + 2.0 * noise(s * 3.9 + t * 3, o.seed) + 0.8 * noise(s * 9.1 - t * 5, o.seed + 9);
  // 水体厚度：中间厚、两端薄，也带噪声
  const thick = (s) => (13 + 4 * noise(s * 3.3, o.seed + 4)) * (1 - 0.5 * s * s);
  lights.add(0, 0, 34, C[5], 0.6, 0.25);
  let t = 0, broke = false, sprayAcc = 0;

  function wall(p) {
    const fade = 1 - smooth(BREAK, 0.46, t), hot = t < 0.05 ? 2 : t < 0.1 ? 1 : 0, cool = clamp(t / 0.2) * 1.5;
    if (fade <= 0) return;
    const lim = HW * (1 - 0.15 * smooth(BREAK, 0.46, t));
    const out = { c: 0, a: 1 };
    const put = (x, y) => { if (out.c) out.a >= 0.98 ? p.px(x, y, out.c) : p.blend(x, y, out.c, out.a); };   // 半透明一律真半透明，不用抖动
    for (let y = -HW - 1.5; y <= HW + 1.5; y++) for (let x = -30.5; x <= 6.5; x++) { out.c = 0; out.a = 1; cell(x, y); put(x, y); }
    function cell(x, y) {
      const s = y / HW;
      if (Math.abs(y) > lim + 0.5 * noise(y * 0.7, o.seed + 2) * 3) return;
      const lx = lip(s, t), d = lx - x;                   // 到浪头的距离（往后为正）
      const th = thick(s) * (0.6 + 0.4 * ease.outQuart(clamp(t / 0.1)));
      if (d < -0.5 || d > th * 1.9) return;
      if (d <= 1.6) {                                      // 浪头：白，首帧爆亮
        out.c = C[clamp(7 - Math.round(cool * 0.5), 6, 7)];
        out.a = fade < 0.5 ? fade * 2 : 1;
        return;
      }
      const q = d / th;                                    // 0 浪头 → 1 水体尾 → 1.9 水痕
      if (q > 1) {                                         // 水痕：断续的拖尾，噪声挖洞
        if (noise2ish(x, y, o.seed) < (q - 1) * 1.2) return;
        out.c = C[2];
        out.a = 0.45 * fade * (1.9 - q);
        return;
      }
      const ci = clamp(Math.round(6 - q * 4.6 + hot - cool - (1 - fade) * 2 + 0.6 * noise(y * 0.5 + x * 0.2, o.seed + 6)), 1, 7);
      out.c = C[ci];
      out.a = (q < 0.45 ? 1 : 0.85 - (q - 0.45) * 0.6) * Math.min(1, fade * 1.5);   // 往后是半透明的水体
    }
    // 浪头上的碎白沫：沿浪头不等距的小团
    for (const f of foam) {
      const y = f.s * HW;
      if (Math.abs(y) > lim) continue;
      const x = lip(f.s, t) - f.d, k = fade * (t < f.t0 ? 0 : 1);
      if (k > 0) p.disc(x, y, f.r * (0.7 + 0.5 * clamp(t / 0.25)), C[7], 0.7 * k);
    }
  }
  const noise2ish = (x, y, sd) => 0.5 + 0.5 * noise(x * 0.9 + noise(y * 0.6, sd + 1) * 3, sd + 3);
  const foam = [];
  for (let s = -0.95; s < 0.95; s += Rg.range(0.12, 0.3)) foam.push({ s: s + Rg.range(-0.04, 0.04), d: Rg.range(0.5, 3), r: Rg.range(0.8, 2.2), t0: Rg.range(0, 0.12) });

  return {
    update(dt) {
      t += dt;
      // 推进中：浪头前方甩出水珠（俯视下沿推进方向 + 侧向散开）
      sprayAcc += dt;
      while (t < BREAK && sprayAcc > 0.012) {
        sprayAcc -= 0.012;
        const s = Rg.range(-0.9, 0.9), y = s * HW, x = lip(s, t);
        const sp = Rg.range(60, 150);
        ps.spawn(P.MOTE, x, y, sp, Rg.range(-25, 25) + s * 30, Rg.range(0.12, 0.28), C[5 + Rg.int(0, 2)], Rg.range(0.5, 0.9));
      }
      if (!broke && t >= BREAK) {
        broke = true;
        // 浪头碎开：浪沫团 + 水珠，不等距
        for (let s = -0.9; s < 0.9; s += Rg.range(0.1, 0.26)) {
          const y = s * HW, x = lip(s, t);
          ps.spawn(P.VAPOUR, x - Rg.range(0, 4), y, Rg.range(10, 40), Rg.range(-15, 15), Rg.range(0.18, 0.3), C[5], Rg.range(2, 4));
          if (Rg.chance(0.7)) ps.spawn(P.MOTE, x, y, Rg.range(50, 130), Rg.range(-40, 40), Rg.range(0.12, 0.22), C[6 + Rg.int(0, 1)], Rg.range(0.6, 1));
        }
        lights.add(lip(0, t), 0, 28, C[5], 0.4, 0.15);
      }
      ps.update(dt);
      lights.update(dt);
    },
    draw(p) {
      ps.draw(p, "back");
      wall(p);
      ps.draw(p, "front");
      lights.draw(p);
    },
  };
}
