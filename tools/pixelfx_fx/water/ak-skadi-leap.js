// 斯卡蒂精一「破浪下劈」落点水花（docs/229 §7 第 2 批，替 fx_skadi_leap_splash 的同心水纹 + 棋盘格）。
// 俯视地面透视（sy 0.55），原点 = 落点。大剑砸进水面：首帧白闪，一圈外缘按噪声起伏的水冠只推一道，
// 冠上甩起高矮不一的水柱和水珠（落回地面），中间留一摊逐级变深、碎成斑块后消失的积水。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";

export const meta = {
  name: "Skadi leap splash",
  desc: "Top-down slam splash on the floor: a white flash, one ragged crown of water pushed outward with uneven spouts and droplets falling back, and a puddle that darkens and breaks apart.",
  tags: ["water", "splash", "impact", "floor", "topdown", "one-shot"],
  size: [96, 72],
  origin: [48, 44],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    radius: 32,
    seed: 4,
  },
};

const SY = 0.55, OUT = 0.2;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 3, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  const jag = (a) => 1 + 0.13 * noise(a * 2.7, o.seed) + 0.07 * noise(a * 7.9, o.seed + 5);
  const crest = (t) => R * (0.15 + 0.85 * ease.outQuart(clamp(t / OUT)));
  lights.add(0, 0, 30, C[6], 0.8, 0.22);
  // 水柱：角度不等距、高矮早晚各异
  const spouts = [];
  for (let a = Rg.range(0, 0.5); a < TAU; a += Rg.range(0.35, 0.8)) spouts.push({ a, h: Rg.range(4, 14) * (Rg.chance(0.25) ? 1.4 : 1), w: Rg.range(0.8, 2), lean: Rg.range(0.1, 0.5), d: Rg.range(0, 0.06) });
  // 起手：落点往上和往外甩的水珠
  for (let i = 0; i < 26; i++) {
    const a = Rg.range(0, TAU), sp = Rg.range(40, 120);
    ps.spawn(P.SPARK, Math.cos(a) * 3, Math.sin(a) * 2, Math.cos(a) * sp, Math.sin(a) * sp * SY - Rg.range(60, 150), Rg.range(0.3, 0.5), C[5 + Rg.int(0, 2)], 1);
  }
  let t = 0;

  function puddle(p) {
    const life = 1 - smooth(0.25, 0.55, t), rc = crest(t) * 0.92;
    if (life <= 0) return;
    for (let y = -R * SY - 2.5; y <= R * SY + 2.5; y++)
      for (let x = -R - 2.5; x <= R + 2.5; x++) {
        const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / jag(a);
        if (r > rc) continue;
        const brk = 0.5 + 0.5 * noise2(x * 0.22, y * 0.4, o.seed + 8);   // 碎成斑块：二维噪声阈值随时间抬高
        if (brk < (1 - life) * 1.1) continue;
        const q = r / Math.max(rc, 1);
        if (q < 0.55 && brk < 0.55) continue;                // 中间是水被砸开的空心，只留零碎水面
        const ci = clamp(Math.round(1 + q * 2.6 + life - (y < 0 ? 0.6 : 0)), 1, 4);
        p.blend(x, y, C[ci], (0.18 + 0.3 * q) * life + 0.08);
      }
  }
  function crown(p, far) {
    const fade = 1 - smooth(0.22, 0.42, t), rc = crest(t), W = 4.5 * (1 - 0.4 * clamp(t / 0.3));
    if (fade <= 0) return;
    const step = 0.5 / rc;
    for (let a = 0; a < TAU; a += step) {
      const sn = Math.sin(a);
      if ((sn < 0) !== far) continue;
      const k = jag(a);
      for (let d = 0; d < W; d += 0.6) {
        const rr = (rc - d) * k, x = Math.cos(a) * rr, y = sn * rr * SY;
        const ci = clamp(Math.round(7 - d * 1.1 - (t < 0.05 ? -1 : clamp(t / 0.15) * 1.5) - (far ? 1 : 0)), 2, 7);
        p.blend(x, y, C[ci], d < 1.2 ? fade : 0.7 * fade);
      }
    }
    // 水柱：冠上竖起，顶白下深
    for (const s of spouts) {
      if ((Math.sin(s.a) < 0) !== far) continue;
      const u = t - s.d, rise = ease.outQuart(clamp(u / 0.1)) * (1 - smooth(0.16, 0.32, u));
      if (rise <= 0.03) continue;
      const k = jag(s.a), x = Math.cos(s.a) * rc * k, y = Math.sin(s.a) * rc * k * SY, h = s.h * rise;
      for (let d = 0; d <= h; d += 0.5) {
        const v = d / h, hw = s.w * (1 - v * 0.8);            // 底粗顶细，顶上一颗水珠
        for (let e = -hw; e <= hw; e += 0.7)
          p.blend(x + Math.cos(s.a) * d * s.lean + e, y - d, C[clamp(Math.round(3 + v * 4.3 - (far ? 1 : 0) - Math.abs(e) * 0.6), 2, 7)], v > 0.8 ? 0.95 : 0.7);
      }
      p.disc(x + Math.cos(s.a) * h * s.lean, y - h - 1, 0.9, C[7], 0.9 * rise);
    }
  }

  return {
    update(dt) {
      t += dt;
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      puddle(p);
      crown(p, true);
    },
    draw(p) {
      if (t < 0.1) {   // 首帧爆亮：落点白闪（局部，不是整屏冲击帧）
        const k = 1 - t / 0.1;
        p.disc(0, 0, 3 + 5 * (1 - k), C[7], 0.85 * k);
        p.glow(0, 0, 20, C[5], 0.3 * k);
      }
      crown(p, false);
      ps.draw(p);
      lights.draw(p);
    },
  };
}
