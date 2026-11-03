// 流明 S3「灯火不灭」结束光爆（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 光圈中心。
// 判定：半径 r = s3_r（1x = s3_r / 2），范围伤害 + 击退 + 眩晕。照原作 lumen_skill_03_hit_02（大四芒爆光 star_06 / 十字火星 shizi / 光柱 trail_15）。
// 灯塔最后一闪：灯高处一颗大四芒爆光（横芒最长）+ 中心一道竖直白光柱冲上去再收；判定半径上 5 段弧同时亮一下再熄（原地闪，不外扩）；
// 中心水冠溅起，成组的水珠往外甩到圈边附近；3 颗十字星浮起。不画外扩光环（用户 11-04）、不画实心圆。只有 E2。
// 分层：core = 爆光、光柱、边弧、水冠、十字星；deco = 中心淡光、水珠。只用钢蓝 7 阶。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Lumen lantern burst unleashed",
  desc: "The lighthouse's last flash: a huge four-pointed flare and a white shaft at the centre while broken arcs flash once on the zone's edge.",
  tags: ["water", "light", "impact", "one-shot"],
  size: [240, 210],
  origin: [120, 140],
  duration: 0.85,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", r: 110, seed: 8 },
};

const SY = 0.5;

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, Rg = new Rng(o.seed), LY = -46;
  const segs = jitterAngles(Rg, 5, 0, TAU, 0.3).map((c) => ({ c, half: Rg.range(0.24, 0.38), s: Rg.next() * 9 }));
  const crown = jitterAngles(Rg, 12, 0, TAU, 0.4).map((a, i) => ({ a, h: 8 + 12 * noise(i * 1.3, o.seed), r: 8 + 5 * noise(i * 2.1, o.seed + 2) }));
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  for (let g = 0; g < 7; g++) {
    const a = Rg.range(0, TAU), v = Rg.range(110, 170);
    for (let k = 0, n = Rg.int(2, 4); k < n; k++)
      ps.spawn(P.FLAKE, Math.cos(a) * 8, Math.sin(a) * 4 - 4, Math.cos(a) * v * (1 - 0.12 * k), Math.sin(a) * v * SY - 50 + 6 * k, Rg.range(0.35, 0.5), C[5 - (k > 1 ? 1 : 0)], 1, 0.04 + 0.015 * k);
  }
  const glints = [0, 1, 2].map((i) => ({ x: Rg.range(-30, 30), y: Rg.range(-8, 8), d: 0.15 + i * 0.1, v: Rg.range(25, 40) }));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); ps.list.forEach((q) => (q.vy += 200 * dt)); },
    drawBack(p) {
      if (deco && t < 0.4) p.glow(0, LY * 0.6, 26, C[4], 0.4 * (1 - t / 0.4));
    },
    draw(p) {
      if (core) {
        // 大四芒爆光：0.45 s 收，首帧白、第 2 帧降一档
        const u = clamp(t / 0.45);
        if (u < 1) {
          const k = 1 - ease.inQuad(u), rays = [[1, 0, 90], [-1, 0, 90], [0, -1, 48], [0, 1, 30], [0.7, 0.7, 14], [-0.7, 0.7, 14], [0.7, -0.7, 18], [-0.7, -0.7, 18]];
          for (const [dx, dy, L] of rays) {
            const len = L * k;
            for (let s = 0; s <= len; s += 0.5) {
              const v = s / Math.max(len, 1), w = dy === 0 && v < 0.4 ? 1 : 0;
              const c = t < 0.05 ? (v < 0.7 ? C[6] : C[5]) : t < 0.1 ? (v < 0.15 ? C[6] : C[5]) : v < 0.1 ? C[6] : v < 0.6 ? C[5] : C[4];
              p.blend(dx * s, LY + dy * s, c, 1 - v * 0.6);
              if (w) { p.blend(dx * s, LY + 1, C[5], 1 - v); p.blend(dx * s, LY - 1, C[5], 1 - v); }
            }
          }
        }
        // 竖直白光柱：冲上去 0.08 s，0.35 s 往中线收
        if (t < 0.35) {
          const up = ease.outCubic(clamp(t / 0.08)), W = 3 * (1 - smooth(0.08, 0.35, t)), H = 130 * up;
          for (let y = 0; y <= H; y += 1) for (let x = -W; x <= W; x += 0.5) p.blend(x, -y, Math.abs(x) < W * 0.45 && t < 0.06 ? C[6] : C[5], clamp(1.2 - y / H) * 0.95);
        }
        // 边弧：判定半径上原地闪一下（0.04 亮 → 0.4 熄），不外扩
        const ea = t < 0.04 ? t / 0.04 : 1 - smooth(0.12, 0.45, t);
        if (ea > 0)
          for (const sg of segs)
            for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.4 / R) {
              const e = 1 - Math.abs(an - sg.c) / sg.half, n = noise(an * 2.8 + sg.s, o.seed + 1);
              p.dot(Math.cos(an) * R, Math.sin(an) * R * SY, t < 0.05 ? C[6] : n > 0.7 ? C[6] : C[5], ea * smooth(0, 0.3, e));
            }
        // 水冠
        const cu = (t - 0.03) / 0.4;
        if (cu > 0 && cu < 1)
          for (const c of crown) {
            const bx = Math.cos(c.a) * c.r * (0.6 + 0.4 * cu), by = Math.sin(c.a) * c.r * SY, hh = c.h * Math.sin(Math.min(1, cu * 1.6) * Math.PI * 0.5) * (1 - cu * cu);
            for (let s = 0; s <= hh; s += 0.5) p.dot(bx + Math.cos(c.a) * s * 0.4, by - s, s > hh * 0.75 && cu < 0.4 ? C[6] : C[5], 1 - cu * 0.5);
          }
        for (const g of glints) {
          const a = t - g.d, life = 0.35;
          if (a <= 0 || a > life) continue;
          const k = Math.sin((a / life) * Math.PI), y = g.y - 10 - a * g.v, m = Math.round(3.5 * k);
          p.px(g.x, y, C[6]);
          for (let d = 1; d <= m; d++) { const c = d <= 1 ? C[6] : C[5]; p.px(g.x + d, y, c); p.px(g.x - d, y, c); p.px(g.x, y + d, c); p.px(g.x, y - d, c); }
        }
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
