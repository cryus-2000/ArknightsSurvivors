// 流明光弹命中（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 命中点，弹道从左往右（mirror 用 dir 选项）。
// 照原作 lumen_attack_01_hit（尖刺水花 star_18 爆开 → 十字星 shizi 浮起 → 水点散落）：
// 首帧白热的不规则水花：7–10 根细水刺，角度抖动、长短用 noise，顺着弹道方向往前多甩一点；随后水刺缩回、往下垂成水珠落下；
// 一两颗细十字星从水花里浮起。不画圆盘、不画外扩光环（用户 11-04）。
// 分档：E0 水花 + 1 颗十字星；E1 加一道斜穿水花的折光细线（精一折光）；E2 加一截从命中点竖直往上照的细光（精二灯塔），十字星 2 颗、水珠多一些。
// 分层：core = 水刺、十字星、折光线、竖光；deco = 光晕、落下的水珠、闪烁。颜色只用钢蓝 7 阶。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, jitterAngles } from "../house.js";

export const meta = {
  name: "Lumen bolt hit unleashed",
  desc: "An irregular water splash with thin spikes that fold back into falling drops while a thin glint rises out of it.",
  tags: ["impact", "water", "one-shot"],
  size: [72, 80],
  origin: [36, 48],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", elite: 2, quick: 0, seed: 4, scale: 1 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), E = o.elite, K = o.scale, Rg = new Rng(o.seed + 31 * E);
  const tail = (E === 0 ? 0.6 : E === 1 ? 0.8 : 1) * (o.quick ? 0.6 : 1);
  const n = E === 2 ? 10 : E === 1 ? 8 : 7;
  const spikes = jitterAngles(Rg, n, -Math.PI, Math.PI, 0.42).map((a, i) => {
    const fwd = Math.max(0, Math.cos(a));   // 顺弹道（+x）方向甩得更远
    return { a, L: (5 + 7 * noise(i * 1.7, o.seed) + 5 * fwd) * K * (E === 2 ? 1.15 : 1), w: Rg.next() < 0.4 ? 2 : 1 };
  });
  const glints = [];
  for (let i = 0, m = E === 2 ? 2 : 1; i < m; i++) glints.push({ x: Rg.range(-6, 8) * K, d: 0.08 + i * 0.1, v: Rg.range(30, 46), s: Rg.range(2.5, 3.5) });
  const refr = { a: Rg.range(-0.7, -0.35) * (Rg.next() < 0.5 ? 1 : -1), L: 16 * K };
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  // 往外甩的水珠去掉（用户 11-04，§14.7）：水刺缩回、尖端下垂就收
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); ps.list.forEach((q) => (q.vy += 160 * dt)); },
    drawBack(p) {
      if (deco && t < 0.25) p.glow(0, 0, 10 * K, C[4], 0.35 * (1 - t / 0.25));
    },
    draw(p) {
      if (core) {
        // 水刺：0.05 s 甩到全长，之后往回缩、尖端往下垂；首帧白，第 2 帧降一档
        const out = 0.55 + 0.45 * ease.outCubic(clamp(t / 0.05)), back = smooth(0.1, 0.32 * (0.6 + 0.4 * tail), t);
        if (back < 1)
          for (const s of spikes) {
            const L = s.L * out * (1 - 0.7 * back), ca = Math.cos(s.a), sa = Math.sin(s.a);
            for (let d = 1.5; d <= L; d += 0.5) {
              const v = d / Math.max(L, 1), droop = back * 6 * v * v;
              const ci = t < 0.05 ? 6 : t < 0.1 ? (v < 0.5 ? 6 : 5) : v < 0.4 ? 5 : 4;
              p.dot(ca * d, sa * d + droop, C[ci], 1 - back * 0.6);
              if (s.w === 2 && v < 0.5) p.dot(ca * d - sa * 0.7, sa * d + ca * 0.7 + droop, C[Math.max(3, ci - 1)], 1 - back);
            }
          }
        // 十字星：浮起、长一下再缩没
        for (const g of glints) {
          const a = t - g.d, life = 0.3 * (0.7 + 0.3 * tail);
          if (a <= 0 || a > life) continue;
          const k = Math.sin((a / life) * Math.PI), x = g.x, y = -4 - a * g.v, m = Math.round(g.s * k);
          p.px(x, y, C[6]);
          for (let d = 1; d <= m; d++) { const c = d <= 1 ? C[6] : C[5]; p.px(x + d, y, c); p.px(x - d, y, c); p.px(x, y + d, c); p.px(x, y - d, c); }
        }
        // E1+：折光——一道斜穿水花的细光，0.04–0.2 s
        if (E >= 1 && t > 0.04 && t < 0.2) {
          const u = (t - 0.04) / 0.16, ca = Math.cos(refr.a), sa = Math.sin(refr.a);
          for (let s = -refr.L; s <= refr.L; s += 0.5) p.dot(ca * s, sa * s, Math.abs(s) < refr.L * 0.4 && u < 0.4 ? C[6] : C[5], (1 - u) * (1 - 0.6 * Math.abs(s) / refr.L));
        }
        // E2：灯塔——从命中点竖直往上照的一截细光，0.25 s 往上收
        if (E === 2 && t < 0.25) {
          const u = t / 0.25, H = 26 * K;
          for (let y = H * u * 0.6; y <= H; y += 1) { const v = y / H; p.blend(0, -y, v < 0.5 && u < 0.3 ? C[6] : C[5], (1 - u) * (1 - v * 0.6)); }
        }
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
