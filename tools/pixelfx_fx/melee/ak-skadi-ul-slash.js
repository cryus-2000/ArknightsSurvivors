// 斯卡蒂「不加限制」大剑斩（claude/pixelfx-unleashed-skadi，开关 fx/px_unleashed）：俯视，原点 = 斯卡蒂，正右为出手方向。
// span 选弧长：2.8（普攻 160°）/ 3.5（迅捷打击 200°）/ 6.28（涌潮悲歌全方向）；heavy = 跃浪击。
// v3（11-03 用户定）：
//   变细用 A（PX 2 不变）：刀身薄、颗粒小而多、外缘 1 格亮线（白只在白热窗口里）。
//   move 各有主形：basic 单月牙（克制）/ s1 多段斩痕 + 朝前疾流（不画月牙）/ s2 斩击弧上立起水幕、往前卷倒拍落成飞溅 + 拉长积水（不是圆）/ s3 全方向 + 浪墙。
//   elite 拉开到不看 HUD 能分：E0 只有主形；E1 加内弧回声 + 浪尖白沫带；E2 再加二次浪峰（海绿色重点）+ 潮刃（docs/91 精二「涌潮」），S3 加水柱、S2 浪体更大。
// The crescent / echo / trace recipe is adapted from Sprite Fusion's open-source slash
// (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Skadi slash unleashed",
  desc: "Top-down greatsword strikes: a lean deep-sea crescent for basics, staggered cuts and forward jets, a rising water curtain that topples and splashes, a broken wave wall all around.",
  tags: ["melee", "slash", "greatsword", "water", "topdown", "one-shot"],
  size: [260, 260],
  origin: [130, 130],
  duration: 1.25,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#040c1c", "#08224a", "#0f4280", "#1a6cb4", "#34a8dc", "#7fe0f4", "#d4fbff", "#ffffff"],
    accent: "#5ff0cc",   // E2 专属颜色重点（海绿，和敌方红 / 品红危险色分开）
    radius: 80,
    span: 3.5,
    heavy: 0,
    quick: 0,         // 1 = 余韵短（队友版）
    move: "basic",    // basic / s1 / s2 / s3
    elite: 2,         // 0 / 1 / 2
    fine: 1,          // 变细 A（缺省开）
    layer: "all",     // core / deco / all（分层导出时由 pixelfx_export.py 传）
    seed: 3,
  },
};

const onArc = (s, r, a) => [Math.cos(a) * r, Math.sin(a) * r];

function crescent(p, s, ta, L, W, age, hot, core, deco) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, dir = Math.sign(L), span = Math.abs(L), B = s.R + 4;
  if (core) p.shade(-B, -B, B, B, (x, y, out) => {
    const r = Math.hypot(x, y), ang = Math.atan2(y, x);
    const jag = 2.6 * noise(ang * 8, s.seed) + 1.4 * noise(ang * 21, s.seed + 7);
    const Rr = s.R + jag * (0.5 + age * 1.5);
    if (r > Rr + 0.5 || r < s.R - W - 2) return;
    let u = (dir * (ang - ta)) % TAU;
    if (u < 0) u += TAU;
    if (u > span) return;
    const v = u / span, w = W * Math.pow(Math.sin(Math.PI * Math.pow(v, 2.2)), 0.5);
    if (w < 0.4) return;
    const q = (Rr - r) / w;
    if (q < 0 || q > 1) return;
    if (s.edge && Rr - r < 1.2 && age < 0.7) {   // 变细 A：外缘 1 格亮线；白只在白热窗口里
      out.c = R[hot > 1 ? n - 1 : n - 3];
      out.a = 1;
      return;
    }
    const ci = q < 0.2 && age < 0.5 ? 0 : Math.round(q * (n - 1) * 0.75 + age * 2.8 - v * 1.1 + 0.3 - hot);
    out.c = R[n - 1 - clamp(ci, s.minI || 0, n - 1)];
    out.a = q > 0.8 ? 0.7 : 1;   // 刀身内沿半透明
  });
  if (deco) for (let u = 0; u <= span; u += 0.18) {   // 刀身光晕归装饰层
    const [x, y] = onArc(s, s.R - W * 0.4, ta + dir * u);
    p.glow(x, y, 10 + W, R[n - 3], (0.28 * (1 - age) * (u / span) + 0.04 * hot) * s.GK);
  }
}

// 细长斩痕（S1 多段斩）：两端尖、中间宽的透镜形，从 a 端划到 b 端，头亮尾暗
function cut(p, C, c, t) {
  const u = t - c.t0;
  if (u < 0 || u > c.life) return;
  const head = ease.outExpo(clamp(u / 0.05)), tail = smooth(0.06, c.life, u);
  const dx = c.x1 - c.x0, dy = c.y1 - c.y0, L = Math.hypot(dx, dy), nx = -dy / L, ny = dx / L;
  for (let d = tail * L; d < head * L; d += 0.5) {
    const v = d / L, w = c.w * Math.pow(Math.sin(Math.PI * v), 0.6) * (1 - 0.6 * tail);
    const x = c.x0 + dx * v, y = c.y0 + dy * v;
    for (let s = -w; s <= w; s += 0.5) {
      const q = Math.abs(s) / Math.max(0.5, w);
      const ci = u < 0.05 && q < 0.35 ? 7 : clamp(Math.round(6.4 - q * 2.6 - u * 7 + (1 - v) * 0.6), 2, 6);
      p.px(x + nx * s, y + ny * s, C[ci]);
    }
  }
}

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), heavy = +o.heavy > 0, full = o.span > 6, quick = +o.quick > 0;
  const el = clamp(Math.round(+o.elite), 0, 2), mv = o.move || "basic", fine = +o.fine > 0, ACC = o.accent;
  // 分档（docs/242 §10）：DL 装饰余韵、GK 光晕、PM 颗粒量、HOT 白热；队友版余韵再减半
  const DL = [0.45, 0.75, 1][el] * (quick ? 0.5 : 1), GK = [0.5, 0.8, 1][el], PM = [0.55, 0.8, 1][el] * (fine ? 1.5 : 1), HOT = [0.8, 1.8, 3.0][el];
  const LQ = DL, SZ = fine ? 0.6 : 1;
  // 分层（docs/242 §8）：core = 主形 / 白热 / 招式标志 / 精英档元素；deco = 光晕、甩出物、余韵
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[4] }), lights = new Lights();
  const R0 = o.radius, span = full ? TAU * 1.04 : o.span, a0 = full ? -Math.PI : -span / 2, a1 = a0 + span;
  const SW = full ? 0.13 : heavy ? 0.09 : 0.07;
  const W = (heavy ? 30 : full ? 22 : 18) * (fine ? 0.62 : 1) * [0.8, 1, 1.12][el];
  const A = { seed: o.seed, R: R0, W, ramp: C, GK, edge: fine };
  const E = { seed: o.seed + 9, R: R0 * 0.72, W: W * 0.4, ramp: C.slice(0, 7), GK, edge: false };
  let t = 0.02, passed = 0, landed = false, crashed = false;
  const tip = onArc(A, A.R - A.W * 0.3, a1);
  const arcOn = mv !== "s1";   // S1 不画月牙，主形是斩痕

  // ---- S1：多段斩痕（时间、角度、长短都错开）+ 朝前疾流
  const cuts = [], jets = [];
  if (mv === "s1") {
    const n = el === 0 ? 2 : 3;
    for (let i = 0; i < n; i++) {
      const phi = Rg.range(-0.75, 0.75), rr = R0 * Rg.range(0.42, 0.78), hl = Math.sqrt(R0 * R0 - rr * rr) * Rg.range(0.88, 0.98);
      const cx = Math.cos(phi) * rr, cy = Math.sin(phi) * rr, tx = -Math.sin(phi), ty = Math.cos(phi), sk = Rg.range(-0.35, 0.35);
      const s1 = Rg.chance(0.5) ? 1 : -1;
      cuts.push({ x0: cx - (tx + sk * Math.cos(phi)) * hl * s1, y0: cy - (ty + sk * Math.sin(phi)) * hl * s1, x1: cx + (tx + sk * Math.cos(phi)) * hl * s1, y1: cy + (ty + sk * Math.sin(phi)) * hl * s1,
        w: W * Rg.range(0.75, 1.0), t0: i * 0.06 + Rg.range(0, 0.025), life: 0.28 * (0.6 + 0.4 * DL) });
    }
    for (let i = 0, m = el === 0 ? 2 : el === 1 ? 3 : 5; i < m; i++) {
      const y = Rg.range(-0.55, 0.55) * R0, x = Rg.range(0.15, 0.4) * R0;
      jets.push({ x, y, a: Rg.range(-0.12, 0.12) + y / R0 * 0.25, L: R0 * Rg.range(0.45, 0.85) * (el === 2 ? 1.15 : 1), w: Rg.range(1, 1.8), t0: Rg.range(0.03, 0.16) });
    }
  }
  // ---- S2：斩击弧上立起的水幕（各列高度起伏），往前卷倒拍落
  const S2H = R0 * [0.55, 0.7, 0.9][el], S2A = [0.5, 0.65, 0.85][el];
  const curtain = (a, k) => S2H * k * (0.55 + 0.45 * noise(a * 4, o.seed + 61) + 0.2 * noise(a * 11, o.seed + 67)) * Math.pow(Math.cos(clamp(a / S2A, -1, 1) * Math.PI / 2), 0.7);
  // ---- S3：浪墙高度（连续起伏、有断口）；E2 几根水柱
  const wallH = (a) => Math.max(0, 16 * [0.75, 1, 1.25][el] * (0.45 + 0.7 * noise(a * 2.3, o.seed + 41) + 0.35 * noise(a * 6.1, o.seed + 43)));
  const pillars = [];
  if (mv === "s3" && el >= 2) for (let a = Rg.range(0, 1.2); a < TAU - 0.4; a += Rg.range(1.1, 2.0)) pillars.push({ a, H: Rg.range(36, 54), d: Rg.range(0.02, 0.08) });

  function drawArc(p, s, t0, hold, trail) {
    const u = t - t0;
    if (u < 0) return;
    const head = ease.outExpo(clamp(u / SW)), tail = smooth(SW + hold, SW + hold + trail, u), age = clamp(u / (SW + hold + trail));
    const hot = u < (full ? 0.06 : 0.09) ? HOT : u < 0.13 ? 0.3 : 0;   // 白热 1–2 帧、第 3 帧起回落（docs/242 §9.3；全方向整圈面积大，只白 1 帧）
    if (tail < 1) crescent(p, s, a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.5), age, hot, core, deco);
  }
  function spray(x, y, nx, ny, n, sp, life) {
    for (let k = 0; k < n; k++) {
      const v = sp * Rg.range(0.5, 1.2), a = Math.atan2(ny, nx) + Rg.range(-0.6, 0.6);
      ps.spawn(k % 3 ? P.MOTE : P.SPARK, x, y, Math.cos(a) * v, Math.sin(a) * v - Rg.range(20, 70), life * Rg.range(0.6, 1.1), C[6 + Rg.int(0, 1)], Rg.range(0.7, 1.3) * SZ);
    }
  }
  return {
    update(dt) {
      t += dt;
      const head = ease.outExpo(clamp(t / SW));
      while (arcOn && passed < head && passed < 1) {
        const a = a0 + span * passed, [x, y] = onArc(A, A.R - Rg.range(0, A.W * 0.5), a);
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a);
        const nm = Math.round((heavy ? 4 : 3) * PM + Rg.range(-0.4, 0.4));
        for (let k = 0; k < nm; k++) {
          const sp = Rg.range(80, 260);
          ps.spawn(P.MOTE, x, y, (tx * 0.6 + nx * 0.9) * sp, (ty * 0.6 + ny * 0.9) * sp, Rg.range(0.25, 0.55) * (0.6 + 0.4 * DL), C[6 + Rg.int(0, 1)], Rg.range(0.8, 1.4) * SZ);
        }
        if (Rg.chance(0.7 * PM)) ps.spawn(P.SPARK, x, y, nx * Rg.range(100, 260), ny * Rg.range(100, 260) - 60, Rg.range(0.3, 0.65));
        if (deco && Rg.chance(0.3)) ps.spawn(P.VAPOUR, x + nx * 5, y + ny * 5, nx * 40 + tx * 25, ny * 40 + ty * 25, Rg.range(0.25, 0.45), C[5], Rg.range(2, 4));
        passed += (full ? 0.025 : 0.035) * Rg.range(0.4, 1.8) / (fine ? 1.4 : 1);   // 步长随机：等距撒会排成等距放射纹
      }
      if (mv === "s1") for (const c of cuts) if (!c.sp && t >= c.t0 + 0.04) {   // 每道斩痕划完沿刀路甩水
        c.sp = true;
        const L = Math.hypot(c.x1 - c.x0, c.y1 - c.y0), nx = -(c.y1 - c.y0) / L, ny = (c.x1 - c.x0) / L;
        for (let v = Rg.range(0.1, 0.2); v < 0.9; v += Rg.range(0.1, 0.25)) spray(c.x0 + (c.x1 - c.x0) * v, c.y0 + (c.y1 - c.y0) * v, nx * (Rg.chance(0.5) ? 1 : -1), ny, Math.round(2 * PM), 160, 0.45 * LQ);
      }
      if (!landed && t >= SW) {
        landed = true;
        lights.add(0, 0, R0 * 1.2, C[5], 0.15 * GK, 0.35);
        if (arcOn) lights.add(tip[0], tip[1], 46, C[6], 0.9 * GK, 0.3);
        if (arcOn) for (let a = a0 + 0.1; a < a1; a += Rg.range(0.08, 0.2) / PM) {   // 余韵：外缘碎成浪沫与水雾
          const [x, y] = onArc(A, A.R + Rg.range(-2, 5), a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(15, 60);
          ps.spawn(P.VAPOUR, x, y, nx * sp, ny * sp, Rg.range(0.5, 0.85) * LQ, C[4 + Rg.int(0, 1)], Rg.range(2.5, 5.5), Rg.range(0, 0.08));
          if (el >= 1 && Rg.chance(0.5)) ps.spawn(P.STAR, x + Rg.range(-4, 4), y + Rg.range(-4, 4), nx * 6, ny * 6 - 4, Rg.range(0.35, 0.7) * LQ, C[6 + Rg.int(0, 1)], Rg.range(1, 2) * SZ, Rg.range(0.05, 0.4) * LQ);
          if (Rg.chance(0.7)) ps.spawn(P.SPARK, x, y, nx * sp * 3, ny * sp * 3 - Rg.range(40, 140), Rg.range(0.35, 0.7) * LQ);
        }
        if (arcOn && !full) {
          const ta = Math.atan2(Math.cos(a1), -Math.sin(a1));
          for (let i = 0, m = Math.round(20 * PM); i < m; i++) {
            const a = ta + Rg.range(-0.8, 0.8), sp = Rg.range(120, 320);
            ps.spawn(P.SPARK, tip[0], tip[1], Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.45));
          }
        }
        if (mv === "s3") for (let a = Rg.range(0, 0.2); a < TAU; a += Rg.range(0.05, 0.22)) {   // 浪墙顶甩出白沫
          const h = wallH(a);
          if (h < 9 || !Rg.chance(0.6)) continue;
          const [x, y] = onArc(A, A.R + h, a);
          ps.spawn(P.MOTE, x, y, Math.cos(a) * Rg.range(30, 90), Math.sin(a) * Rg.range(30, 90) - 30, Rg.range(0.4, 0.75) * LQ, C[6], Rg.range(0.9, 1.6) * SZ);
        }
      }
      if (mv === "s2" && !crashed && t >= SW + 0.26) {   // 水幕拍落：沿前缘碎成不规则飞溅
        crashed = true;
        lights.add(R0 * 0.9, 0, 56, C[6], 0.7 * GK, 0.3);
        for (let a = -S2A + Rg.range(0, 0.08); a < S2A; a += Rg.range(0.05, 0.16)) {
          const h = curtain(a, 1);
          if (h < 4) continue;
          const [x, y] = onArc(A, A.R * 0.98, a);
          spray(x + h * 0.5, y - h * 0.3, Math.cos(a) + 0.6, Math.sin(a), Math.round((1 + h / 12) * PM), 150 + h * 3, 0.6 * LQ);
          if (deco) ps.spawn(P.VAPOUR, x + h * 0.4, y, Math.cos(a) * 50 + 30, Math.sin(a) * 30, Rg.range(0.5, 0.9) * LQ, C[5], Rg.range(4, 8));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (core && mv === "s2" && t > SW + 0.22) {   // 积水：拍落处一摊沿冲击方向拉长的不规整水面（边缘强噪声，不是圆 / 环）
        const k = smooth(SW + 0.22, SW + 0.34, t) * (1 - smooth(0.7 + 0.2 * el, 1.15, t)), cx = R0 * 0.78, L = R0 * [0.28, 0.34, 0.44][el];
        if (k > 0) p.shade(cx - L * 1.4, -L, cx + L * 1.6, L, (x, y, out) => {
          const dx = (x - cx) / 1.9, a = Math.atan2(y, dx), r = Math.hypot(dx, y);
          const edge = L * 0.55 * (0.6 + 0.45 * noise(a * 2.5, o.seed + 71) + 0.3 * noise(a * 7, o.seed + 73) + 0.15 * noise(a * 17, o.seed + 79)) * (0.7 + 0.3 * smooth(SW + 0.22, SW + 0.5, t));
          if (r > edge) return;
          const rim = r > edge - 1.2;
          out.c = rim ? C[5] : C[2];
          out.a = (rim ? 0.85 : 0.4) * k;
        });
      }
    },
    draw(p) {
      if (arcOn && el >= 1 && !full) drawArc(p, E, 0.025, 0.04 * DL, 0.3 * DL);   // E1+ 内弧回声（全方向不画：两道同心圈是被否的形状）
      if (arcOn) drawArc(p, A, 0, 0.07, 0.4 * (0.6 + 0.4 * DL));
      if (core && mv === "s1") {
        for (const c of cuts) cut(p, C, c, t);
      }
      if (deco && mv === "s1") for (const c of cuts) {   // 斩痕光晕（装饰层）
        const u = t - c.t0;
        if (u < 0 || u > c.life) continue;
        for (let v = 0.15; v < 0.9; v += 0.15) p.glow(c.x0 + (c.x1 - c.x0) * v, c.y0 + (c.y1 - c.y0) * v, 12 + c.w, C[5], 0.3 * GK * (1 - u / c.life));
      }
      if (core && mv === "s1") {
        for (const j of jets) {   // 疾流：朝前射出、头亮尾暗的细水线
          const u = t - j.t0;
          if (u < 0 || u > 0.3) continue;
          const L = j.L * ease.outExpo(clamp(u / 0.07)), tl = j.L * smooth(0.06, 0.3, u), dx = Math.cos(j.a), dy = Math.sin(j.a);
          for (let d = tl; d < L; d += 0.5) {
            const v = d / j.L;
            for (let w = -j.w / 2; w <= j.w / 2; w += 0.5) p.px(j.x + dx * d - dy * w, j.y + dy * d + dx * w, C[clamp(Math.round(6.5 - (1 - v) * 2.5 - u * 6), 3, 6)]);
          }
        }
      }
      if (core && mv === "s2" && t > SW * 0.6) {   // 浪：从斩击弧里涌起，沿冲击方向（+x）往前涌、浪头往上卷，到判定边附近收住；拍落时从根部往浪头退去
        const u = t - SW * 0.6, rise = ease.outCubic(clamp(u / 0.16)), fall = smooth(0.2, 0.34, u), curl = smooth(0.06, 0.24, u);
        if (rise > 0.02 && fall < 0.98) for (let a = -S2A; a <= S2A; a += 0.4 / A.R) {
          const env = curtain(a, 1) / S2H;   // 0–1：这一列浪的大小
          if (env < 0.08) continue;
          const [bx, by] = onArc(A, A.R * 0.5, a);
          const dir = a * 0.55, cx = Math.cos(dir), cy = Math.sin(dir);   // 顺冲击方向略微张开成扇面（不是平行的一块板）
          const jagL = 1 + 0.18 * noise(a * 23, o.seed + 89) + 0.1 * noise(a * 51, o.seed + 97);   // 前沿锯齿
          const Lm = (A.R * 1.04 - bx) * (0.35 + 0.65 * env) * jagL, L = Lm * rise, up = S2H * 0.45 * env;   // 往前涌的长度、浪头抬起的高度
          for (let d = Lm * fall; d < L; d += 0.6) {
            const v = d / Lm, back = curl * Math.pow(v, 4) * up * 0.6, lift = up * Math.sin(Math.PI * 0.5 * v) * (0.4 + 0.6 * curl);
            const x = bx + cx * (d - back), y = by + cy * (d - back) - lift;
            const tipz = d > L - 2.2, n = noise(a * 9 + v * 6, o.seed + 87) + 0.6 * noise(a * 31 + v * 17, o.seed + 93);   // 浪身打散：白沫纹 / 暗槽，不按距离分条
            p.px(x, y, tipz ? (el >= 2 ? ACC : C[6]) : C[clamp(Math.round(2.6 + 2.6 * v + 1.6 * n), 2, 6)]);
          }
          if (el >= 1 && env > 0.4 && noise(a * 9, o.seed + 83) > -0.2) {   // E1+ 浪头白沫
            const v = L / Lm, back = curl * Math.pow(v, 4) * up * 0.6, lift = up * Math.sin(Math.PI * 0.5 * v) * (0.4 + 0.6 * curl);
            const x = bx + cx * (L - back), y = by + cy * (L - back) - lift;
            p.px(x, y - 1, C[7]);
            p.px(x - 1, y - 1, C[6]);
          }
        }
      }
      if (core && mv === "s3") {   // 浪墙：外缘立起一圈深色浪身（高度连续起伏、有断口）
        const k = smooth(0.02, SW + 0.04, t) * (1 - smooth(0.32, 0.62, t));
        if (k > 0) for (let a = 0; a < TAU; a += 0.55 / (A.R + 10)) {
          const hh = wallH(a) * k;
          if (hh < 2) continue;
          for (let d = 0; d < hh; d += 0.7) {
            const [x, y] = onArc(A, A.R + 1 + d, a), top = d > hh - 1.4;
            p.px(x, y, top ? (el >= 1 && noise(a * 11, o.seed + 47) > 0.1 ? C[7] : C[5]) : C[clamp(Math.round(1 + 3 * d / Math.max(1, hh)), 1, 4)]);
          }
        }
        for (const pl of pillars) {   // E2 水柱：浪墙上几处冲起的水柱（屏幕上朝上）
          const u = t - SW - pl.d;
          if (u < 0 || u > 0.4) continue;
          const H = pl.H * ease.outCubic(clamp(u / 0.12)) * (1 - smooth(0.22, 0.4, u)), [bx, by] = onArc(A, A.R + wallH(pl.a) * 0.6, pl.a);
          for (let d = 0; d < H; d += 0.6) {
            const w = 3.6 * (1 - d / Math.max(1, H) * 0.7);
            for (let s = -w; s <= w; s += 0.6) p.px(bx + s, by - d, d > H - 2 ? ACC : C[clamp(Math.round(3 + 3 * d / Math.max(1, H) - Math.abs(s) / w), 2, 6)]);
          }
        }
      }
      if (core && el >= 1 && arcOn && t > SW * 0.8 && t < 0.45 + 0.15 * el) {   // E1+ 浪尖白沫带：沿外缘断断续续
        const k = 1 - smooth(0.22, 0.45 + 0.15 * el, t);
        for (let a = a0; a < a1; a += 0.5 / A.R) {
          const n = noise((a - a0) * 7, o.seed + 51) + 0.5 * noise((a - a0) * 19, o.seed + 53);
          if (n < -0.1) continue;
          const th = (1 + 1.8 * clamp(n)) * k;
          for (let d = 0; d < th; d += 0.6) {
            const [x, y] = onArc(A, A.R + 1 + d, a);
            p.px(x, y, C[6]);
          }
        }
      }
      if (core && el >= 2 && arcOn && !full && t > SW * 0.5) {   // E2 二次浪峰：外缘后面再涌起一道海绿色浪峰，比主弧短、慢半拍
        const u = t - SW * 0.5, k = smooth(0, 0.08, u) * (1 - smooth(0.2, 0.4, u));
        if (k > 0.02) for (let a = a0 + span * 0.25; a < a1 - span * 0.08; a += 0.5 / A.R) {
          const v = (a - a0 - span * 0.25) / (span * 0.67), h = (4 + 8 * Math.sin(Math.PI * v)) * k * (0.7 + 0.5 * noise(a * 6, o.seed + 91));
          for (let d = 0; d < h; d += 0.6) {
            const [x, y] = onArc(A, A.R + 3 + d, a);
            p.px(x, y, d > h * 0.55 ? ACC : C[clamp(Math.round(3 + 2 * d / Math.max(1, h)), 3, 5)]);
          }
        }
      }
      if (core && el >= 2 && arcOn && !full && t > SW) {   // E2 潮刃：一道薄新月从弧上脱出、往外飞（docs/91 精二「涌潮」）
        const u = t - SW, d = 70 * ease.outCubic(clamp(u / 0.3)), k = 1 - smooth(0.12, 0.32, u);
        if (k > 0) {
          const TB = { seed: o.seed + 31, R: A.R + d, W: Math.max(2, W * 0.4) * k, ramp: C, GK, edge: false, minI: 1 };
          crescent(p, TB, -span * 0.32, span * 0.64, TB.W, 0.15 + 0.5 * (1 - k), 0, true, false);
        }
      }
      if (deco && arcOn && t < 0.32) {
        const [x, y] = onArc(A, A.R - 6, a0 + span * ease.outExpo(clamp(t / SW)));
        p.glow(x, y, 60 * (el === 0 ? 0.6 : 1), C[5], 0.6 * GK * (1 - t / 0.32));
      }
      const g = t - SW * 0.6;
      if (deco && arcOn && el >= 1 && !full && g > 0 && g < 0.26) sparkle(p, tip[0], tip[1], (heavy ? 16 : 12) * ease.outBack(Math.min(1, g / 0.05)) * (1 - g / 0.26), C[7], C[5], 0.8);
      if (deco) {
        lights.draw(p);   // 光先画、颗粒后画（反预乘后光更亮，盖在颗粒上会把水珠火星淹掉，11-03）
        ps.draw(p, "front");
      }
    },
  };
}
