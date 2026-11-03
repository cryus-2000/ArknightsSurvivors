// 斯卡蒂「不加限制」大剑斩（claude/pixelfx-unleashed-skadi，开关 fx/px_unleashed）：俯视圆弧，圆心 = 斯卡蒂，正右为出手方向。
// span 选弧长：2.8（普攻 160°）/ 3.5（迅捷打击 200°）/ 6.28（涌潮悲歌全方向）；heavy = 跃浪击。
// 不设近白 / 色数 / 体积上限：两帧爆亮、强光、厚刀身、整条外缘甩浪、余韵（水雾 + 湿痕 + 浪沫慢慢沉下去）。
// 11-03 用户「放了技能等于没放」「看不出精英档」：
//   move = basic / s1 / s2 / s3 各有专属标志（s1 疾流水线朝前射出、s2 落点水冠 + 积水、s3 浪墙 + 浪峰），普攻保持克制；
//   elite = 0 / 1 / 2（docs/242 §10）：E0 克制（余韵短、光小、无白热大光）、E1 加浪尖白沫、E2 全量 + 潮刃脱出（docs/91 精二「涌潮」）。
//   fine = 1：变细样张 A（刀身薄、颗粒小而多、外缘 1 格亮线）；px2 = 1：样张 B（几何 ×2、像素图元不放大，游戏里按 @2x 缩回 = PX 1）。
// The crescent / echo / trace recipe is adapted from Sprite Fusion's open-source slash
// (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Skadi slash unleashed",
  desc: "Top-down greatsword sweep with nothing held back: a thick white-hot deep-sea crescent, brine flung off its whole rim, foam and mist that linger and settle.",
  tags: ["melee", "slash", "greatsword", "water", "topdown", "one-shot"],
  size: [260, 260],
  origin: [130, 130],
  duration: 1.25,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#040c1c", "#08224a", "#0f4280", "#1a6cb4", "#34a8dc", "#7fe0f4", "#d4fbff", "#ffffff"],
    radius: 80,
    span: 3.5,
    heavy: 0,
    quick: 0,         // 1 = 余韵短（队友版）
    move: "basic",    // basic / s1 / s2 / s3
    elite: 2,         // 0 / 1 / 2
    fine: 0,          // 变细样张 A
    px2: 0,           // 变细样张 B（几何 ×2）
    layer: "all",     // core / deco / all（分层导出时由 pixelfx_export.py 传）
    seed: 3,
  },
};

const onArc = (s, r, a) => [Math.cos(a) * r, Math.sin(a) * r];

function crescent(p, s, ta, L, W, age, hot, core, deco) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, dir = Math.sign(L), span = Math.abs(L), B = s.R + 4 * s.K;
  if (core) p.shade(-B, -B, B, B, (x, y, out) => {
    const r = Math.hypot(x, y), ang = Math.atan2(y, x);
    const jag = (2.6 * noise(ang * 8, s.seed) + 1.4 * noise(ang * 21, s.seed + 7)) * s.K;
    const Rr = s.R + jag * (0.5 + age * 1.5);
    if (r > Rr + 0.5 || r < s.R - W - 2) return;
    let u = (dir * (ang - ta)) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 2.2)), 0.5);
    if (w < 0.4) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    if (s.edge && Rr - r < 1.2 && age < 0.7) {   // 变细 A：外缘 1 格亮线
      out.c = R[hot > 1 ? n - 1 : n - 3];   // 白只在白热窗口里，之后用次亮阶（不连白 3 帧）
      out.a = 1;
      return;
    }
    const ci = q < 0.2 && age < 0.5 ? 0 : Math.round(q * (n - 1) * 0.75 + age * 2.8 - v * 1.1 + 0.3 - hot);
    out.c = R[n - 1 - clamp(ci, 0, n - 1)];
    out.a = q > 0.8 ? 0.7 : 1;   // 刀身内沿半透明（真透明，不抖动）
  });
  if (deco) for (let u = 0; u <= span; u += 0.18) {   // 刀身光晕归装饰层
    const [x, y] = onArc(s, s.R - W * 0.4, ta + dir * u);
    p.glow(x, y, (10 * s.K + W), R[n - 3], (0.28 * (1 - age) * (u / span) + 0.04 * hot) * s.GK);
  }
}

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), heavy = +o.heavy > 0, full = o.span > 6, quick = +o.quick > 0;
  const el = clamp(Math.round(+o.elite), 0, 2), mv = o.move || "basic", fine = +o.fine > 0, K = +o.px2 > 0 ? 2 : 1;
  // 分档（docs/242 §10）：DL 装饰余韵、GK 光晕、PM 颗粒量、HOT 白热；队友版余韵再减半
  const DL = [0.45, 0.75, 1][el] * (quick ? 0.5 : 1), GK = [0.5, 0.8, 1][el], PM = [0.55, 0.8, 1][el] * (fine ? 1.5 : 1), HOT = [0.8, 1.8, 3.0][el];
  const LQ = DL;
  const SZ = fine ? 0.6 : 1;   // 颗粒尺寸（变细 A 更小）
  // 分层（docs/242 §8）：core = 刀弧 / 白热 / 爆点 / 招式标志；deco = 光晕、甩出物、余韵
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[7], C[6], C[5]], haze: C[4] }), lights = new Lights();   // 火星偏亮两阶（颗粒感，11-03）
  const R0 = o.radius * K, span = full ? TAU * 1.04 : o.span, a0 = full ? -Math.PI : -span / 2, a1 = a0 + span;
  const SW = full ? 0.13 : heavy ? 0.09 : 0.07;
  const W = (heavy ? 30 : full ? (mv === "s3" ? 26 : 18) : mv === "basic" ? 18 : 22) * K * (fine ? 0.62 : 1);   // 普攻刀身克制、技能厚
  const A = { seed: o.seed, R: R0, W, ramp: C, full, K, GK, edge: fine };
  const E = { seed: o.seed + 9, R: R0 * 0.72, W: W * 0.4, ramp: C.slice(0, 7), K, GK, edge: false };
  let t = 0.02, passed = 0, landed = false;
  const tip = onArc(A, A.R - A.W * 0.3, a1);
  const sp2 = (v) => v * K;   // 速度 / 距离随几何放大

  // 招式标志（core，形状的一部分）
  const streaks = [];   // s1 疾流：贴着刀弧内外、顺挥砍方向追出去的细水流（弧段，长短 / 半径 / 起点都随机；不朝外放射）
  if (mv === "s1") for (let i = 0, m = Rg.int(6, 9); i < m; i++) {
    const out = Rg.chance(0.65), r = out ? A.R + Rg.range(3, 22) * K : A.R - W - Rg.range(3, 14) * K;
    streaks.push({ r, a: a0 + span * Rg.range(0.05, 0.75), L: Rg.range(0.45, 1.1), w: Rg.range(1.4, 2.6) * K * SZ, t0: SW * Rg.range(0.1, 1.3), v: Rg.range(5, 10) });
  }
  const crown = [];   // s2 水冠：落点往上炸起的不规则水柱（俯视里朝上 = -y），角度 / 长度 / 粗细都随机
  if (mv === "s2") for (let a = -Math.PI + Rg.range(0.1, 0.4); a < -0.1; a += Rg.range(0.22, 0.5)) {
    crown.push({ a, L: sp2(Rg.range(22, 58)), w: Rg.range(2.5, 5) * K, bend: Rg.range(-0.3, 0.3), d: Rg.range(0, 0.05) });
  }
  const wallH = (a) => Math.max(0, sp2(16) * (0.45 + 0.7 * noise(a * 2.3, o.seed + 41) + 0.35 * noise(a * 6.1, o.seed + 43)));   // s3 浪墙高度：连续起伏、有断口（不是等距尖峰）

  function drawArc(p, s, t0, hold, trail) {
    const u = t - t0;
    if (u < 0) return;
    const head = ease.outExpo(clamp(u / SW)), tail = smooth(SW + hold, SW + hold + trail, u), age = clamp(u / (SW + hold + trail));
    const hot = u < 0.09 ? HOT : u < 0.13 ? 0.3 : 0;   // 前 2 帧白热、第 3 帧起回落（docs/242 §9.3）；E0 / E1 白热轻
    if (tail < 1) crescent(p, s, a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.5), age, hot, core, deco);
  }
  return {
    update(dt) {
      t += dt;
      const head = ease.outExpo(clamp(t / SW));
      while (passed < head && passed < 1) {
        const a = a0 + span * passed, [x, y] = onArc(A, A.R - Rg.range(0, A.W * 0.5), a);
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a);
        const nm = Math.round((heavy ? 4 : 3) * PM + Rg.range(-0.4, 0.4));
        for (let k = 0; k < nm; k++) {
          const sp = sp2(Rg.range(80, 260));
          ps.spawn(P.MOTE, x, y, (tx * 0.6 + nx * 0.9) * sp, (ty * 0.6 + ny * 0.9) * sp, Rg.range(0.25, 0.55) * (0.6 + 0.4 * DL), C[6 + Rg.int(0, 1)], Rg.range(0.8, 1.4) * SZ);
        }
        if (Rg.chance(0.7 * PM)) ps.spawn(P.SPARK, x, y, nx * sp2(Rg.range(100, 260)), ny * sp2(Rg.range(100, 260)) - sp2(60), Rg.range(0.3, 0.65));
        if (deco && Rg.chance(0.3)) ps.spawn(P.VAPOUR, x + nx * 5 * K, y + ny * 5 * K, nx * sp2(40) + tx * sp2(25), ny * sp2(40) + ty * sp2(25), Rg.range(0.25, 0.45), C[5], Rg.range(2, 4) * K);
        passed += (full ? 0.025 : 0.035) * Rg.range(0.4, 1.8) / (fine ? 1.4 : 1);   // 步长随机：等距撒会排成一圈等距放射纹
      }
      if (!landed && t >= SW) {
        landed = true;
        lights.add(0, 0, R0 * 1.2, C[5], 0.15 * GK, 0.35);   // 圆心大光：量化出色带像同心圈，压低
        lights.add(tip[0], tip[1], 46 * K, C[6], 0.9 * GK, 0.3);
        // 余韵：整条弧外缘碎成浪沫与水雾，慢慢沉下去；E0 余韵短、量少
        for (let a = a0 + 0.1; a < a1; a += Rg.range(0.08, 0.2) / PM) {
          const [x, y] = onArc(A, A.R + Rg.range(-2, 5) * K, a), nx = Math.cos(a), ny = Math.sin(a), sp = sp2(Rg.range(15, 60));
          ps.spawn(P.VAPOUR, x, y, nx * sp, ny * sp, Rg.range(0.5, 0.85) * LQ, C[4 + Rg.int(0, 1)], Rg.range(2.5, 5.5) * K, Rg.range(0, 0.08));
          if (el >= 1 && Rg.chance(0.5)) ps.spawn(P.STAR, x + Rg.range(-4, 4) * K, y + Rg.range(-4, 4) * K, nx * 6, ny * 6 - 4, Rg.range(0.35, 0.7) * LQ, C[6 + Rg.int(0, 1)], Rg.range(1, 2) * SZ, Rg.range(0.05, 0.4) * LQ);   // 余韵水光（E1 起）
          if (Rg.chance(0.7)) ps.spawn(P.SPARK, x, y, nx * sp * 3, ny * sp * 3 - sp2(Rg.range(40, 140)), Rg.range(0.35, 0.7) * LQ);
        }
        if (!full) {
          const ta = Math.atan2(Math.cos(a1), -Math.sin(a1));
          for (let i = 0, m = Math.round(24 * PM); i < m; i++) {
            const a = ta + Rg.range(-0.8, 0.8), sp = sp2(Rg.range(120, 320));
            ps.spawn(P.SPARK, tip[0], tip[1], Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.45));
          }
        }
        if (heavy) {
          const fx = R0 * 0.6;
          lights.add(fx, 0, 70 * K, C[6], 1.0 * GK, 0.4);
          for (let i = 0, m = Math.round(46 * PM); i < m; i++) {
            const a = Rg.range(-Math.PI, Math.PI), sp = sp2(Rg.range(90, 300));
            ps.spawn(i % 3 ? P.MOTE : P.SPARK, fx, 0, Math.cos(a) * sp, Math.sin(a) * sp - sp2(40), Rg.range(0.3, 0.7), C[5 + Rg.int(0, 2)], Rg.range(0.8, 1.4) * SZ);
          }
          for (let i = 0; i < 14; i++) {
            const a = Rg.range(-Math.PI, Math.PI), d = Rg.range(2, 16) * K;
            ps.spawn(P.VAPOUR, fx + Math.cos(a) * d, Math.sin(a) * d, Math.cos(a) * sp2(40), Math.sin(a) * sp2(40), Rg.range(0.6, 1.0) * LQ, C[5], Rg.range(6, 10) * K);
          }
          if (mv === "s2") for (const c of crown) {   // 水冠顶端甩出的水珠
            const x = R0 * 0.6 + Math.cos(c.a) * c.L, y = Math.sin(c.a) * c.L;
            for (let i = 0, m = Rg.int(1, 3); i < m; i++) ps.spawn(P.MOTE, x, y, Math.cos(c.a + Rg.range(-0.5, 0.5)) * sp2(Rg.range(40, 120)), Math.sin(c.a) * sp2(Rg.range(60, 140)), Rg.range(0.4, 0.8), C[6 + Rg.int(0, 1)], Rg.range(0.9, 1.5) * SZ);
          }
        }
        if (mv === "s3") for (let a = Rg.range(0, 0.2); a < TAU; a += Rg.range(0.05, 0.22)) {   // 浪墙顶甩出的白沫（墙高的地方多）
          const h = wallH(a);
          if (h < sp2(9) || !Rg.chance(0.6)) continue;
          const [x, y] = onArc(A, A.R + h, a);
          ps.spawn(P.MOTE, x, y, Math.cos(a) * sp2(Rg.range(30, 90)), Math.sin(a) * sp2(Rg.range(30, 90)) - sp2(30), Rg.range(0.4, 0.75) * LQ, C[7], Rg.range(0.9, 1.6) * SZ);
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (core && mv === "s2" && t > SW) {   // 积水：落点一摊不规整的暗色水面，先涌开后退（不是圆环）
        const k = smooth(SW, SW + 0.1, t) * (1 - smooth(0.45, 0.9, t)), fx = R0 * 0.6, rr = sp2(34) * (0.7 + 0.5 * smooth(SW, SW + 0.25, t));
        if (k > 0) p.shade(fx - rr * 1.5, -rr, fx + rr * 1.5, rr, (x, y, out) => {
          const dx = (x - fx) / 1.35, a = Math.atan2(y, dx), r = Math.hypot(dx, y), edge = rr * (0.78 + 0.22 * noise(a * 3, o.seed + 5) + 0.1 * noise(a * 9, o.seed));
          if (r > edge) return;
          out.c = r > edge - 1.2 * K ? C[5] : C[2];
          out.a = (r > edge - 1.2 * K ? 0.9 : 0.45) * k;
        });
      }
    },
    draw(p) {
      if (!full) drawArc(p, E, 0.025, 0.04 * DL, 0.3 * DL);   // 全方向时不画内弧（两道同心圈是被否的形状）
      drawArc(p, A, 0, 0.07, 0.4 * (0.6 + 0.4 * DL));
      if (core && mv === "s3") {   // 浪墙：外缘立起一圈深色浪身 + 高低不一的浪峰（深海色，和普攻的亮刀身区分）
        const k = smooth(0.02, SW + 0.04, t) * (1 - smooth(0.32, 0.62, t));
        if (k > 0) for (let a = 0; a < TAU; a += 0.55 / (A.R + 10 * K)) {
          const hh = wallH(a) * k;
          if (hh < 2 * K) continue;   // 断口
          for (let d = 0; d < hh; d += 0.7) {
            const [x, y] = onArc(A, A.R + 1 + d, a), top = d > hh - 1.6 * K;
            p.px(x, y, top ? C[7] : C[clamp(Math.round(1 + 3 * d / Math.max(1, hh)), 1, 4)]);
          }
        }
      }
      if (core && mv === "s1") for (const s of streaks) {   // 疾流：一段弧沿挥砍方向追出去，头亮尾暗
        const u = t - s.t0, life = 0.36 * (0.6 + 0.4 * DL);
        if (u < 0 || u > life) continue;
        const h = s.a + s.v * u, L = s.L * (1 - u / life);
        for (let da = 0; da < L; da += 0.5 / s.r) {
          const v = da / Math.max(0.01, L);
          for (let w = -s.w / 2; w <= s.w / 2; w += 0.6) {
            const [x, y] = onArc(A, s.r + w, h - da);
            p.px(x, y, C[clamp(Math.round(7 - v * 3.5 - u * 5), 3, 7)]);
          }
        }
      }
      if (core && mv === "s2" && t > SW) for (const c of crown) {   // 水冠
        const u = t - SW - c.d;
        if (u < 0 || u > 0.4) continue;
        const L = c.L * ease.outExpo(clamp(u / 0.12)), tl = c.L * smooth(0.15, 0.4, u);
        for (let d = tl; d < L; d += 0.6) {
          const v = d / c.L, a = c.a + c.bend * v * v, half = Math.max(0.5, c.w * (1 - 0.85 * v) / 2);
          const x = R0 * 0.6 + Math.cos(a) * d, y = Math.sin(a) * d;
          for (let w = -half; w <= half; w += 0.6) p.px(x - Math.sin(a) * w, y + Math.cos(a) * w, C[clamp(Math.round(3.6 + v * 3 - w / half * 0.8 + (u < 0.05 ? 2 : 0)), 2, 7)]);
        }
      }
      if (core && el >= 1 && t > SW * 0.8 && t < 0.45 + 0.15 * el) {   // E1+ 浪尖白沫（留到余韵里，一眼能看到）
        const k = 1 - smooth(0.22, 0.45 + 0.15 * el, t);
        for (let a = a0; a < a1; a += 0.5 / A.R) {   // 沿外缘一条断断续续的白沫带（噪声决定有无和厚薄）
          const n = noise((a - a0) * 7, o.seed + 51) + 0.5 * noise((a - a0) * 19, o.seed + 53);
          if (n < -0.1) continue;
          const th = (1.2 + 2.2 * clamp(n)) * K * k;
          for (let d = 0; d < th; d += 0.6) {
            const [x, y] = onArc(A, A.R + 1 + d, a);
            p.px(x, y, C[7]);
          }
        }
      }
      if (core && el >= 2 && !full && t > SW) {   // E2 潮刃：一道薄新月从弧上脱出、往外飞出去再散（docs/91 精二「涌潮」）
        const u = t - SW, d = sp2(70) * ease.outCubic(clamp(u / 0.3)), k = 1 - smooth(0.12, 0.32, u);
        if (k > 0) {
          const TB = { seed: o.seed + 31, R: A.R + d, W: Math.max(2, W * 0.32) * k, ramp: C, K, GK, edge: false };
          crescent(p, TB, -span * 0.32, span * 0.64, TB.W, 0.15 + 0.5 * (1 - k), 0.6 * k, true, false);
        }
      }
      if (deco && t < 0.32) {
        const [x, y] = onArc(A, A.R - 6 * K, a0 + span * ease.outExpo(clamp(t / SW)));
        p.glow(x, y, 60 * K * (el === 0 ? 0.6 : 1), C[5], 0.6 * GK * (1 - t / 0.32));
      }
      const g = t - SW * 0.6;
      if (deco && el >= 1 && !full && g > 0 && g < 0.26) sparkle(p, tip[0], tip[1], (heavy ? 18 : 14) * K * ease.outBack(Math.min(1, g / 0.05)) * (1 - g / 0.26), C[7], C[5], 0.8);
      if (core && heavy && t > SW && t < SW + 0.14) {
        const k = 1 - (t - SW) / 0.14;
        p.disc(R0 * 0.6, 0, (16 * k + 5) * K, C[7], 0.9 * k);
      }
      if (deco) {
        lights.draw(p);   // 光先画、颗粒后画：反预乘后光更亮，盖在颗粒上会把水珠 / 火星淹掉（11-03）
        ps.draw(p, "front");
      }
    },
  };
}
