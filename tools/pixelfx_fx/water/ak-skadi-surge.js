// 斯卡蒂「涌潮」水环（docs/228 §8）：俯视地面透视（sy 0.55，同游戏地面圈），原点 = 脚底，水环外沿半径 radius。
// 一道不规整的水冠从脚下推到外沿，冠上水柱高低不一，到边碎成水珠和浪沫；不画等距同心圈。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Skadi surge",
  desc: "Top-down floor surge: a ragged crest of deep-sea water bursts out from the feet, spouts of uneven height ride it, then it breaks into droplets and foam.",
  tags: ["water", "ring", "surge", "wave", "floor", "topdown", "one-shot"],
  size: [180, 148],
  origin: [90, 90],
  duration: 0.8,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    radius: 62,
    seed: 3,
  },
};

const SY = 0.55, OUT = 0.22, BREAK = 0.3;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  // 水柱：成簇分布——簇内间距 0.1–0.3 rad、簇间空 0.5–0.95 rad（间距变化远超 ±30%，数量随种子变），高矮 5–20 并偶有高柱，出现早晚不一（docs/229 §2.6）
  const spouts = [];
  for (let a = Rg.range(0, 0.6); a < TAU - 0.15; a += Rg.chance(0.3) ? Rg.range(0.5, 0.95) : Rg.range(0.1, 0.3))
    spouts.push({ a, h: Rg.range(5, 20) * (Rg.chance(0.2) ? 1.5 : 1), w: Rg.range(1.5, 4.5), lean: Rg.range(0.2, 0.6), d: Rg.range(0, 0.09) });
  const crest = (t) => R * (0.18 + 0.8 * ease.outQuart(clamp(t / OUT)) + 0.1 * clamp((t - OUT) / 0.4));   // 到边后仍缓缓外推
  const jag = (a) => 1 + 0.09 * noise(a * 3.1, o.seed) + 0.05 * noise(a * 9.7, o.seed + 5);
  lights.add(0, 0, 22, C[5], 0.3, 0.25);   // 帧条里只烤小光晕（docs/229 §2.7）
  let t = 0, broke = false;

  // 水冠带：外缘白、往里逐级变深，前缘越往后越薄；keep 选远半圈 / 近半圈
  function band(p, keep) {
    const rc = crest(t), fade = 1 - smooth(BREAK, 0.62, t), W = 11 * (1 - 0.45 * clamp(t / 0.5));
    if (fade <= 0) return;
    const B = rc * 1.15 + 2;
    p.shade(-B, -B * SY - 2, B, B * SY + 2, (x, y, out) => {
      if (!keep(y)) return;
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / jag(a);
      const q = (rc - r) / W;
      if (q < -0.15 || q > 1) return;
      const ci = clamp(Math.round(7 - Math.max(0, q) * 6 - (1 - fade) * 3 - (y < 0 ? 1 : 0)), 1, 7);
      out.c = C[ci];
      out.a = (q > 0.45 ? 0.75 - (q - 0.45) : 1) * Math.min(1, fade * 1.6);   // 往里是半透明的水体
    });
  }
  // 水幕：沿水冠一整道，高度随噪声起伏（不等距），下深上白，顶上碎沫；到边后塌落
  const H = 15;
  const hAt = (a) => H * (0.3 + 0.7 * (0.5 + 0.5 * noise(a * 4.3, o.seed + 11))) * (0.8 + 0.4 * (0.5 + 0.5 * noise(a * 13, o.seed + 3)));
  function curtain(p, far) {
    const u = t, rise = ease.outQuart(clamp(u / 0.12)) * (1 - smooth(BREAK - 0.05, BREAK + 0.12, u));
    if (rise <= 0.02) return;
    const rc = crest(t), step = 0.6 / rc;
    for (let a = 0; a < TAU; a += step) {
      const sn = Math.sin(a);
      if ((sn < 0) !== far) continue;
      const k = jag(a), x = Math.cos(a) * rc * k, y = sn * rc * k * SY, h = hAt(a) * rise;
      for (let d = 0; d <= h; d += 0.5) {
        const v = d / h, top = v > 0.86;
        const ci = clamp(Math.round(3 + v * 4.2 - (far ? 1.5 : 0)), 1, 7);
        p.blend(x + Math.cos(a) * d * 0.2, y - d, C[ci], top ? 0.9 : v < 0.25 ? 0.95 : 0.6);   // 真半透明，不用抖动棋盘格
      }
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!broke && t >= BREAK) {
        broke = true;
        // 水柱折断：水珠向外上方抛出，浪沫沿外沿铺开
        const rc = crest(t);
        for (const s of spouts) {
          const k = jag(s.a), x = Math.cos(s.a) * rc * k, y = Math.sin(s.a) * rc * k * SY, h = hAt(s.a);
          for (let i = 0, nd = Rg.int(1, 4); i < nd; i++) {   // 每柱折断甩出的水珠数不固定
            const out = Rg.range(25, 100);
            ps.spawn(P.SPARK, x, y - h * Rg.range(0.5, 1), Math.cos(s.a) * out, Math.sin(s.a) * out * SY - Rg.range(40, 120), Rg.range(0.2, 0.38));
          }
          ps.spawn(P.VAPOUR, x, y, Math.cos(s.a) * 18, Math.sin(s.a) * 18 * SY - 4, Rg.range(0.25, 0.4), C[4], Rg.range(2.5, 4.5), Rg.range(0, 0.06));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      // 脚下一片暗水先涌起
      const g = 1 - smooth(0.05, 0.5, t);
      if (g > 0) p.disc(0, 0, crest(t) * 0.9, C[1], 0.35 * g);
      band(p, (y) => y < 0);
      curtain(p, true);
      ps.draw(p, "back");
    },
    draw(p) {
      band(p, (y) => y >= 0);
      curtain(p, false);
      if (t < 0.08) p.disc(0, 0, 5 * (1 - t / 0.08) + 2, C[7], 0.8);
      ps.draw(p, "front");
      lights.draw(p);
    },
  };
}
