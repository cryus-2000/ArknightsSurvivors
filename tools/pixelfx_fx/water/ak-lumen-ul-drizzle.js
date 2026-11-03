// 流明 S1「沐雨」（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底。
// 照原作 lumen_skill_01（细雨落下 → 脚下水面荡开 → 白蓝十字星浮起、气泡上飘）：
// 一阵斜细雨落在队长身上 → 每滴落地溅一个小水花 → 脚下一道带缺口的透视水纹荡开 → 几颗细十字星从水面浮起闪灭。
// 分档（docs/242 §10，对应 docs/91 流明）：E0 细雨 + 水纹 + 十字星；E1 加「折光」——雨幕里斜着闪过两三道细光（精一折光）；
// E2 加「灯塔」——一道细窄的灯火光柱从上方照下来，落点溅起几颗灯火色火星（精二灯塔光柱），雨更密、余韵更长。
// 分层（docs/242 §8）：core = 雨丝、落点水花、主水纹、十字星、折光细线、光柱；deco = 光晕、水雾、气泡、甩出的水珠、灯火火星、闪烁。
// 颜色：雨 = 流明挑染钢蓝（PRTS #4285AD 往白），比敌弹青 #33ceff 暗、偏蓝、低饱和；灯火 = 我方灯火橙（optical_col_lamp h .075），
// 不用淡金（经验结晶 h .13 s .25）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Lumen drizzle unleashed",
  desc: "A slanted drizzle falls on the leader: each drop splashes, a broken ripple spreads at the feet and thin glints rise from the water.",
  tags: ["water", "heal", "rain", "one-shot"],
  size: [136, 168],
  origin: [68, 148],
  duration: 1.05,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"],
    lamp: ["#4a200c", "#a8471a", "#ff9640", "#ffc48a", "#fff0e0"],
    layer: "all", elite: 2, quick: 0, seed: 3,
  },
};

const SY = 0.5;   // 地面透视压扁

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), L = fit(o.lamp, 5), E = o.elite, Rg = new Rng(o.seed + 17 * E);
  const tail = (E === 0 ? 0.55 : E === 1 ? 0.75 : 1.0) * (o.quick ? 0.6 : 1);   // 余韵：E0 短、E2 长；队友版再减
  const ps = new Particles({ rng: Rg, ground: () => 1e9, haze: C[3] });
  // 雨丝：同一个风向（斜 ~12°），落点在脚下一块不规则的椭圆里；出现先后、长短、落点都随机
  const wind = 0.22, nRain = E === 0 ? 16 : E === 1 ? 22 : 30, RX = E === 2 ? 40 : 32;
  const rain = [];
  for (let i = 0; i < nRain; i++) {
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.next()) * RX * (0.8 + 0.4 * noise(a * 2, o.seed));
    rain.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, t: Rg.range(0, E === 2 ? 0.32 : 0.24), len: Rg.range(10, 18), fall: Rg.range(0.11, 0.16), h: Rg.range(90, 130) });
  }
  // 十字星：从水面浮起
  const glints = [];
  for (let i = 0, n = E === 0 ? 3 : E === 1 ? 4 : 5; i < n; i++)
    glints.push({ x: Rg.range(-22, 22), y: Rg.range(-4, 4), v: Rg.range(28, 52), d: 0.16 + Rg.range(0, 0.3), s: Rg.range(2, 3.6), life: Rg.range(0.35, 0.55) * (0.8 + 0.3 * tail) });
  // 折光（E1+）：雨幕里斜着闪过的细光线，角度和位置都不等
  const refr = [];
  if (E >= 1) for (let i = 0, n = E === 1 ? 2 : 3; i < n; i++)
    refr.push({ x: Rg.range(-26, 26), y: Rg.range(-90, -36), a: Rg.range(-1.1, -0.5) * (i % 2 ? 1 : -1), len: Rg.range(30, 46), t: 0.1 + i * 0.07 + Rg.range(0, 0.06) });
  // 落点水花甩出的水珠 + 气泡（装饰）
  for (const d of rain) {
    const tl = d.t + d.fall;
    for (let k = 0, n = Rg.int(1, 3); k < n; k++)
      ps.spawn(P.FLAKE, d.x, d.y - 1, Rg.range(-30, 30), Rg.range(-60, -25), Rg.range(0.18, 0.32), C[4 + Rg.int(0, 2)], 1, tl);
  }
  for (let i = 0, n = E === 0 ? 5 : 9; i < n; i++)
    ps.spawn(P.MOTE, Rg.range(-24, 24), Rg.range(-6, 4), Rg.range(-6, 6), Rg.range(-40, -18), Rg.range(0.4, 0.75) * tail + 0.1, C[4], 0.6, 0.2 + Rg.range(0, 0.3));
  if (E === 2) for (let i = 0; i < 7; i++)   // 灯火火星：光柱落点往上飘，个数少、走向不等
    ps.spawn(P.EMBER, Rg.range(-6, 6), Rg.range(-4, 0), Rg.range(-26, 26), Rg.range(-70, -30), Rg.range(0.35, 0.6), L[3], Rg.range(1, 1.8), 0.1 + Rg.range(0, 0.12));
  ps.sparks = [L[4], L[3], L[2], L[1]];
  let t = 0;
  // 主水纹：一道透视椭圆，外缘用 noise 断开成几段（不是整环，不出同心圈）
  const ripple = (p, R, w, cHi, cLo, a, seed) => {
    for (let an = 0; an < TAU; an += 0.6 / Math.max(R, 4)) {
      const n = noise(an * 2.3 + seed, seed);
      if (n < 0.32) continue;
      const rr = R * (0.94 + 0.12 * noise(an * 5, seed + 3));
      for (let k = 0; k < w; k += 0.5) {
        const x = Math.cos(an) * (rr - k), y = Math.sin(an) * (rr - k) * SY;
        p.dot(x, y, k < 1 ? cHi : cLo, a * (n > 0.6 ? 1 : 0.6));
      }
    }
  };
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {
      if (!deco) return;
      const k = E === 0 ? 0.2 : E === 1 ? 0.28 : 0.4;
      const gk = k * (1 - smooth(0.15, 0.4 + 0.5 * tail, t)), gr = 30 + 8 * E;
      if (gk > 0.01)   // 脚下水面的光：透视压扁的椭圆，外缘用 noise 打散，不是圆盘
        for (let y = -gr * SY; y <= gr * SY; y += 1)
          for (let x = -gr; x <= gr; x += 1) {
            const q = Math.hypot(x / gr, y / (gr * SY)) * (0.9 + 0.2 * noise(Math.atan2(y, x) * 1.6, o.seed + 5));
            if (q < 1) p.blend(x, y, C[3], gk * 0.8 * (1 - q) * (1 - q));
          }
      ps.draw(p, "back");
    },
    draw(p) {
      // ---- 光柱（E2）：上方照下来的一道细窄灯光，0.05 s 落地，停一下往中间收；白芯 + 灯火橙边
      if (E === 2 && core) {
        const up = ease.outCubic(clamp(t / 0.07)), fold = smooth(0.12, 0.32, t), H = 140 * up, W = 2.8 * (1 - fold);
        if (W > 0.3)
          for (let y = 0; y <= H; y += 1) {
            const v = y / 140, w = W * (0.35 + 0.65 * v), a = clamp(v * 1.6) * (1 - 0.6 * fold);   // 上端淡入，落点最亮
            for (let x = -w; x <= w; x += 0.5) {
              const q = Math.abs(x) / Math.max(w, 0.5);
              p.blend(x, -140 + y, q < 0.5 ? L[4] : L[3], clamp(a * (q < 0.5 ? 1.2 : 0.75)));
            }
          }
      }
      if (core) {
        // ---- 雨丝：1 像素细线，尾巴暗、头亮；落地后消失
        for (const d of rain) {
          const u = (t - d.t) / d.fall;
          if (u < 0 || u > 1) continue;
          const yh = d.y - d.h * (1 - u), xh = d.x - wind * d.h * (1 - u);
          for (let s = 0; s <= d.len; s += 0.5) {
            const c = s < 1.5 ? C[6] : s < d.len * 0.5 ? C[5] : C[4];
            p.dot(xh - wind * s, yh - s, c, s < d.len * 0.5 ? 1 : 1.3 - s / d.len);
          }
        }
        // ---- 落点水花：一个小冠（2–3 根短刺往上翘）+ 一小段弧，0.15 s
        for (const d of rain) {
          const u = (t - d.t - d.fall) / 0.16;
          if (u < 0 || u > 1) continue;
          const hh = 3 * Math.sin(u * Math.PI), r = 2 + u * 4;
          p.dot(d.x - 1.5, d.y - hh, C[6], 1 - u); p.dot(d.x + 1.5, d.y - hh * 0.8, C[5], 1 - u);
          for (let an = 0.3; an < Math.PI - 0.3; an += 0.35) p.dot(d.x + Math.cos(an) * r, d.y + Math.sin(an) * r * SY, u < 0.4 ? C[5] : C[4], 1 - u);
        }
        // ---- 主水纹：第一批雨落地时荡开，首帧白
        const t0 = 0.14, u = (t - t0) / (0.5 + 0.25 * tail);
        if (u > 0 && u < 1) {
          const R = 6 + (RX + 6 - 6) * ease.outCubic(u), hot = u < 0.08;
          ripple(p, R, 2.5, hot ? C[6] : C[5], C[4], 1 - u * u, o.seed + E);
        }
        if (t >= 0.13 && t < 0.18) {   // 首帧白热：脚下一记不规则的水冠，不是圆盘
          for (let an = 0; an < TAU; an += 0.22) {
            const n = noise(an * 3, o.seed + 9), r = 4 + 6 * n;
            p.dot(Math.cos(an) * r, Math.sin(an) * r * SY - n * 5, C[6]);
          }
        }
        // ---- 十字星（原作 shizi）：细十字，浮起、长一下再缩没
        for (const g of glints) {
          const a = t - g.d;
          if (a <= 0 || a > g.life) continue;
          const k = Math.sin((a / g.life) * Math.PI), x = g.x, y = g.y - a * g.v, n = Math.round(g.s * k);
          p.px(x, y, C[6]);
          for (let d = 1; d <= n; d++) {
            const c = d <= 1 ? C[6] : C[5];
            p.px(x + d, y, c); p.px(x - d, y, c); p.px(x, y + d, c); p.px(x, y - d, c);
          }
        }
        // ---- 折光（E1+）：一闪而过的细光线，中段白、两头钢蓝
        for (const r of refr) {
          const a = (t - r.t) / 0.18;
          if (a < 0 || a > 1) continue;
          const ca = Math.cos(r.a), sa = Math.sin(r.a), L2 = r.len * (0.4 + 0.6 * ease.outCubic(a));
          for (let s = -L2 / 2; s <= L2 / 2; s += 0.5) {
            const q = Math.abs(s) / (L2 / 2);
            p.dot(r.x + ca * s, r.y + sa * s, q < 0.4 ? C[6] : C[5], (1 - a * a) * (1 - 0.6 * q));
            if (q < 0.25) p.dot(r.x + ca * s - sa, r.y + sa * s + ca, C[5], (1 - a) * 0.6);
          }
        }
      }
      if (deco) {
        ps.draw(p, "front");
        for (const g of glints) {   // 十字星出现时一小团光
          const a = t - g.d;
          if (a > 0 && a < g.life) p.glow(g.x, g.y - a * g.v, 5, C[4], 0.35 * Math.sin((a / g.life) * Math.PI));
        }
        if (E === 2 && t < 0.3) p.glowLine(0, -70, 0, 0, 6, L[2], 0.2 * (1 - smooth(0.1, 0.3, t)));
      }
    },
  };
}
