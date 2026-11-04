// 流明光弹命中（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 命中点，弹道从左往右（mirror 用 dir 选项）。
// 照原作 lumen_attack_01_hit（尖刺水花 star_18 爆开 → 十字星 shizi 浮起 → 水点散落）：
// §0 收拢（用户 11-04）：实心水团 + 5–7 根粗水刺 + 两三颗会落地弹一下的水珠，十字星去掉；以下为旧描述——首帧白热的不规则水花：7–10 根细水刺，角度抖动、长短用 noise，顺着弹道方向往前多甩一点；随后水刺缩回、往下垂成水珠落下；
// 一两颗细十字星从水花里浮起。不画圆盘、不画外扩光环（用户 11-04）。
// 分档见 create 里的注释（组长 B 11-04 硬标准）。
// 分层：core = 水刺、十字星、折光线、竖光；deco = 光晕、落下的水珠、闪烁。颜色只用钢蓝 7 阶。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, LAMP, jitterAngles } from "../house.js";

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
  const C = fit(o.palette, 7), E = o.elite, Rg = new Rng(o.seed + 31 * E);
  // 分档（组长 B 11-04 硬标准）：E1 体量 ×1.25、水刺加厚一档、命中多一拍爆亮；E2 质变——一团变三团（主团 + 两小团往前溅），体量 ×1.5，
  // 主团芯一点灯火橙（E2 专属点缀），余韵更长。加码只加在主形上
  const ES = [1, 1.25, 1.5][E], K = o.scale * ES * 1.3, AC = fit([LAMP], 1)[0];   // 组长 B 11-04：整体偏小，基础体量 ×1.3
  const blobs = E === 2 ? [[0, 0, 1], [6, -3, 0.6], [4, 4, 0.5]] : [[0, 0, 1]];
  const tail = (E === 0 ? 0.6 : E === 1 ? 0.8 : 1) * (o.quick ? 0.6 : 1);
  const n = E === 2 ? 7 : E === 1 ? 6 : 5;   // §0 不碎：水刺少而粗
  const spikes = jitterAngles(Rg, n, -Math.PI, Math.PI, 0.42).map((a, i) => {
    const fwd = Math.max(0, Math.cos(a));   // 顺弹道（+x）方向甩得更远
    return { a, L: (5 + 7 * noise(i * 1.7, o.seed) + 5 * fwd) * K, w: Rg.next() < 0.4 ? 2 : 1 };
  });
  const glints = [];
  for (let i = 0, m = E === 2 ? 2 : 1; i < m; i++) glints.push({ x: Rg.range(-6, 8) * K, d: 0.08 + i * 0.1, v: Rg.range(30, 46), s: Rg.range(2.5, 3.5) });
  const refr = { a: Rg.range(-0.7, -0.35) * (Rg.next() < 0.5 ? 1 : -1), L: 16 * K };
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  // 往外甩的水珠去掉（用户 11-04，§14.7）：水刺缩回、尖端下垂就收
  // 有重量的水珠（§0 Noita）：从两三根水刺尖掉下来，落地（y = 8）弹一下就停，数量少、只往下落不往外甩
  const drops = spikes.filter((q, i) => i % 3 === 0).slice(0, E === 0 ? 2 : 3).map((q) => ({ x: Math.cos(q.a) * q.L * 0.8, y: Math.sin(q.a) * q.L * 0.8, vx: Math.cos(q.a) * 6, vy: -10, b: 0 }));
  let t = 0;
  return {
    update(dt) {
      t += dt;
      if (t > 0.08) for (const d of drops) { d.vy += 260 * dt; d.x += d.vx * dt; d.y += d.vy * dt; if (d.y > 8 && d.vy > 0) { d.y = 8; d.vy *= -0.35; d.vx *= 0.5; d.b++; } }
    },
    drawBack(p) {
      if (deco && t < 0.3) p.glow(0, 6, 9 * K, C[3], 0.3 * (1 - t / 0.3));   // 命中处照亮脚下地面（§0）
    },
    draw(p) {
      if (core) {
        // 水刺：0.05 s 甩到全长，之后往回缩、尖端往下垂；首帧白，第 2 帧降一档
        const out = 0.55 + 0.45 * ease.outCubic(clamp(t / 0.05)), back = smooth(0.1, 0.32 * (0.6 + 0.4 * tail), t);
        // 实心水团（§0 主形）：命中那一下一团不规则的水，0.1 s 内缩掉
        const beat2 = E >= 1 && t > 0.08 && t < 0.12;   // E1+：第二拍爆亮
        const blob = beat2 ? 0.8 : 1 - smooth(0.04, 0.14 + 0.06 * E, t);
        if (blob > 0)
          for (const [bx, by, bk] of blobs)
            for (let an = 0; an < TAU; an += 0.2) {
              const rr = (3 + 2.5 * noise(an * 1.7 + bx, o.seed)) * K * bk * (0.6 + 0.4 * blob);
              for (let r = 0; r <= rr; r += 0.5) p.px(bx * K + Math.cos(an) * r, by * K + Math.sin(an) * r * 0.8, t < 0.05 || beat2 ? C[6] : r < rr * 0.5 ? C[5] : C[4]);
            }
        if (E === 2 && t < 0.16) for (let y = -1; y <= 1; y++) for (let x = -1; x <= 1; x++) if (Math.abs(x) + Math.abs(y) <= 1) p.px(x, y, AC);   // E2 专属：主团芯一点灯火橙
        // 水刺：粗的楔形（根部 2.5 像素往尖端收），甩到全长后往回缩、尖端下垂
        if (back < 1)
          for (const s of spikes) {
            const L = s.L * out * (1 - 0.7 * back), ca = Math.cos(s.a), sa = Math.sin(s.a);
            for (let d = 1.5; d <= L; d += 0.5) {
              const v = d / Math.max(L, 1), droop = back * 6 * v * v, w = (1.3 + 0.5 * E) * (1 - v) * (1 - 0.5 * back);
              const ci = t < 0.05 ? 6 : t < 0.1 ? (v < 0.5 ? 6 : 5) : v < 0.4 ? 5 : 4;
              for (let q = -w; q <= w; q += 0.5) p.px(ca * d - sa * q, sa * d + ca * q + droop, Math.abs(q) > w - 0.5 && w > 0.6 ? C[Math.max(3, ci - 1)] : C[ci]);
            }
          }
        // 精英档加码只加在主形上（组长 B 11-04）：旧的 E1 折光细线、E2 竖光去掉
      }
      if (core && t > 0.08)
        for (const d of drops) if (d.b < 3 && t < 0.55) { p.px(d.x, d.y, C[5]); p.px(d.x + 1, d.y, C[4]); p.px(d.x, d.y - 1, C[6]); }
    },
  };
}
