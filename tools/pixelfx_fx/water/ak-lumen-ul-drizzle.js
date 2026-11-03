// 流明 S1「沐雨」（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底。
// 照原作 lumen_skill_01（目标脚下铺开一圈水面法阵 → 细雨落进法阵 → 白蓝十字星浮起）：
// 脚下法阵从中心推开，边缘是一道细亮线（判定半径 r = 光雨范围 rain_r，1x 像素 = rain_r / 2），边内贴着一层沿边流动的颗粒；
// 斜细雨落进法阵，落点溅起 2–4 颗连着的水珠（顺着离心方向）；十字星浮起，同一时间最多 3 颗。
// 分档（docs/242 §10，对应 docs/91 流明）：E0 法阵 + 细雨 + 十字星；E1 加「折光」——一到两道斜光贯穿法阵，停 0.25 s（精一折光）；
// E2 加「灯塔」——一道细窄的钢蓝白光柱从上方照进法阵中心（精二灯塔光柱），雨更密、法阵停得更久。
// 分层（docs/242 §8）：core = 法阵边线、雨丝、落点水珠、十字星、折光、光柱；deco = 法阵内的流动颗粒、边内光、上飘光点。
// 颜色（组长 11-04）：只用 PRTS 挑染 #4285AD 钢蓝 7 阶，高光段 #c4e0f2 → #ffffff，不留暖色（避开经验结晶暖金）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Lumen drizzle unleashed",
  desc: "A water sigil spreads under the leader, a slanted drizzle falls into it and thin glints rise from the surface.",
  tags: ["water", "heal", "rain", "one-shot"],
  size: [176, 200],
  origin: [88, 160],
  duration: 1.15,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"],
    layer: "all", elite: 2, quick: 0, seed: 3, r: 70,
  },
};

const SY = 0.5;   // 地面透视压扁

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), E = o.elite, R = o.r, Rg = new Rng(o.seed + 17 * E);
  const tail = (E === 0 ? 0.6 : E === 1 ? 0.8 : 1.0) * (o.quick ? 0.6 : 1);   // 余韵：E0 短、E2 长；队友版再减
  const T_OPEN = 0.16, T_HOLD = 0.35 + 0.35 * tail, T_END = T_HOLD + 0.25;      // 法阵：推开 → 停 → 淡出
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  const wind = 0.22, nRain = E === 0 ? 12 : E === 1 ? 16 : 22;
  const rain = [];
  for (let i = 0; i < nRain; i++) {
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.range(0.04, 1)) * R * 0.86;
    rain.push({ a, x: Math.cos(a) * r, y: Math.sin(a) * r * SY, t: 0.04 + Rg.range(0, E === 2 ? 0.34 : 0.26), len: Rg.range(10, 18), fall: Rg.range(0.11, 0.16), h: Rg.range(100, 140), sp: Rg.next() < 0.5 });
  }
  // 十字星：错开出现，同一时间最多 3 颗
  const glints = [];
  for (let i = 0, n = E === 0 ? 3 : E === 1 ? 4 : 5; i < n; i++) {
    const a = Rg.range(0, TAU), r = Rg.range(0.15, 0.6) * R;
    glints.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, v: Rg.range(26, 46), d: 0.18 + i * 0.13 + Rg.range(0, 0.05), s: Rg.range(2.4, 3.8), life: 0.36 });
  }
  // 折光（E1+）：贯穿法阵的斜光，E1 两道、E2 一道（E2 另有光柱），方向不等
  const refr = [];
  if (E >= 1) for (let i = 0, n = E === 1 ? 2 : 1; i < n; i++) {
    const a = Rg.range(0.35, 0.7) * (i % 2 ? -1 : 1);
    refr.push({ a, off: Rg.range(-0.25, 0.25) * R, t: 0.2 + i * 0.12 });
  }
  // 法阵里沿边流动的颗粒（装饰）：贴着边线内侧，角度随机、慢慢走
  const grains = [];
  for (let i = 0, n = 16 + 6 * E; i < n; i++) grains.push({ a: Rg.range(0, TAU), k: Rg.range(0.8, 0.97), w: Rg.range(0.5, 1.1) * (Rg.next() < 0.5 ? 1 : -1), b: Rg.next() });
  // 上飘的光点（装饰，少量）
  for (let i = 0, n = 3 + 2 * E; i < n; i++) {
    const a = Rg.range(0, TAU), r = Rg.range(0.1, 0.7) * R;
    ps.spawn(P.MOTE, Math.cos(a) * r, Math.sin(a) * r * SY, Rg.range(-4, 4), Rg.range(-36, -18), Rg.range(0.4, 0.7) * tail + 0.15, C[5], 0.6, 0.22 + Rg.range(0, 0.3));
  }
  let t = 0;
  const open = () => ease.outCubic(clamp((t - 0.04) / (T_OPEN - 0.04)));
  const fadeA = () => 1 - smooth(T_HOLD, T_END, t);
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {
      if (!deco || t < 0.04) return;
      const rr = R * (0.3 + 0.7 * open()), a = fadeA();
      // 水面光：贴着边线内侧的一圈淡光（越近边越亮），中心空着，不是实心圆盘
      for (let y = -rr * SY; y <= rr * SY; y += 1)
        for (let x = -rr; x <= rr; x += 1) {
          const q = Math.hypot(x / rr, y / (rr * SY));
          if (q < 1 && q > 0.55) p.blend(x, y, C[3], a * (E === 0 ? 0.14 : 0.2) * smooth(0.55, 0.97, q) * (0.75 + 0.25 * noise(Math.atan2(y, x) * 2 + t * 2, o.seed)));
        }
    },
    draw(p) {
      const op = open(), fa = fadeA(), rr = R * (0.3 + 0.7 * op);
      if (core && t >= 0.04 && fa > 0) {
        // ---- 法阵边线：一道细线，亮度沿边用 noise 起伏（不断成等距碎段），推开时首帧白
        const hot = t < T_OPEN;
        for (let an = 0; an < TAU; an += 0.5 / rr) {
          const n = noise(an * 2.2 + t * 3, o.seed + 7), x = Math.cos(an) * rr, y = Math.sin(an) * rr * SY;
          const c = hot ? C[6] : n > 0.62 ? C[6] : n > 0.3 ? C[5] : C[4];
          p.dot(x, y, c, fa * (n > 0.18 ? 1 : 0.55));
        }
      }
      if (core) {
        // ---- 光柱（E2）：上方照进法阵中心的一道细窄光，白芯 + 钢蓝高光边，上端淡入
        if (E === 2) {
          const up = ease.outCubic(clamp(t / 0.07)), fold = smooth(0.14, 0.36, t), H = 150 * up, W = 2.6 * (1 - fold);
          if (W > 0.3)
            for (let y = 0; y <= H; y += 1) {
              const v = y / 150, w = W * (0.35 + 0.65 * v), a = clamp(v * 1.6) * (1 - 0.5 * fold);
              for (let x = -w; x <= w; x += 0.5) {
                const q = Math.abs(x) / Math.max(w, 0.5);
                p.blend(x, -150 + y, q < 0.5 && t < 0.1 ? C[6] : q < 0.5 ? C[5] : C[4], clamp(a * (q < 0.5 ? 1.2 : 0.8)));   // 白芯只留前 2 帧，之后降一档
              }
            }
        }
        // ---- 雨丝：1 像素细线，头亮尾暗；落地即消失
        for (const d of rain) {
          const u = (t - d.t) / d.fall;
          if (u < 0 || u > 1) continue;
          const yh = d.y - d.h * (1 - u), xh = d.x - wind * d.h * (1 - u);
          for (let s = 0; s <= d.len; s += 0.5)
            p.dot(xh - wind * s, yh - s, s < 1.5 ? C[6] : s < d.len * 0.5 ? C[5] : C[4], s < d.len * 0.5 ? 1 : 1.3 - s / d.len);
        }
        // ---- 落点水珠：一半的雨滴溅起 2–4 颗连着的水珠，顺着离心方向甩出一小段弧
        for (const d of rain) {
          if (!d.sp) continue;
          const u = (t - d.t - d.fall) / 0.2;
          if (u < 0 || u > 1) continue;
          const ux = Math.cos(d.a), uy = Math.sin(d.a) * SY, n = 2 + ((d.len * 7) | 0) % 3;
          for (let k = 0; k < n; k++) {
            const s = (1.5 + k * 1.2) * (0.6 + u * 1.4), hh = (4 - k) * Math.sin(u * Math.PI);
            p.dot(d.x + ux * s, d.y + uy * s - hh, k === 0 ? C[6] : C[5], 1 - u * u);
          }
        }
        // ---- 十字星（原作 shizi）：细十字，浮起、长一下再缩没
        for (const g of glints) {
          const a = t - g.d;
          if (a <= 0 || a > g.life) continue;
          const k = Math.sin((a / g.life) * Math.PI), x = g.x, y = g.y - 6 - a * g.v, n = Math.round(g.s * k);
          p.px(x, y, C[6]);
          for (let d = 1; d <= n; d++) {
            const c = d <= 1 ? C[6] : C[5];
            p.px(x + d, y, c); p.px(x - d, y, c); p.px(x, y + d, c); p.px(x, y - d, c);
          }
        }
        // ---- 折光（E1+）：斜光贯穿法阵，从一头扫到另一头再停住，2 像素宽白芯 + 钢蓝边，共 0.3 s
        for (const r of refr) {
          const a = (t - r.t) / 0.3;
          if (a < 0 || a > 1) continue;
          const ca = Math.cos(r.a), sa = Math.sin(r.a), L2 = R * 1.05, head = -L2 + 2 * L2 * ease.outCubic(clamp(a / 0.3)), fade = 1 - smooth(0.75, 1, a);
          for (let s = -L2; s <= head; s += 0.5) {
            const q = Math.abs(s) / L2, x = -sa * r.off + ca * s, y = (ca * r.off + sa * s) * SY - 8;
            p.dot(x, y, q < 0.6 ? C[6] : C[5], fade * (1 - 0.7 * q * q));
            p.dot(x - sa * 0.8, y + 1, C[5], fade * (1 - q) * 0.8);
          }
        }
      }
      if (deco) {
        // 法阵内沿边流动的颗粒
        if (t >= 0.04 && fa > 0)
          for (const g of grains) {
            const an = g.a + t * g.w, k = g.k * rr, tw = 0.5 + 0.5 * Math.sin(t * 9 + g.b * 20);
            p.dot(Math.cos(an) * k, Math.sin(an) * k * SY, tw > 0.7 ? C[6] : C[5], fa * (0.45 + 0.55 * tw));
          }
        ps.draw(p, "front");
        for (const g of glints) {
          const a = t - g.d;
          if (a > 0 && a < g.life) p.glow(g.x, g.y - 6 - a * g.v, 4, C[4], 0.3 * Math.sin((a / g.life) * Math.PI));
        }
        if (E === 2 && t < 0.3) p.glowLine(0, -70, 0, 0, 5, C[4], 0.22 * (1 - smooth(0.1, 0.3, t)));
      }
    },
  };
}
