// 斯卡蒂「不加限制」大剑斩（claude/pixelfx-unleashed-skadi，开关 fx/px_unleashed）：俯视，原点 = 斯卡蒂，正右为出手方向。
// span 选弧长：2.8（普攻 160°）/ 3.5（迅捷打击 200°）/ 6.28（涌潮悲歌全方向）；heavy = 跃浪击。
// v3（11-03 用户定）：
//   变细用 A（PX 2 不变）：刀身薄、颗粒小而多、外缘 1 格亮线（白只在白热窗口里）。
//   move 各有主形：basic 单月牙（克制）/ s1 快速连斩：2–3 道正反手交替的大剑斩弧（间隔约 0.05 s，带纤维拖尾纹理、剑身残影、成团水花；11-03 用户嫌斩痕版抽象）/ s2 斩击弧上立起水幕、往前卷倒拍落成飞溅 + 拉长积水（不是圆）/ s3 全方向：几段不等长、高低起伏的浪身朝各自方向拍出去、中间留缺口（11-04 用户「太像画圆圈」，不再画整圈）；普攻 E1+ / S1 最后一刀改为浪从斩痕里往前涌（不再画同心回声弧 / 外飞新月）。
//   elite 拉开到不看 HUD 能分：E0 只有主形；E1 加内弧回声 + 浪尖白沫带；E2 再加二次浪峰（海绿色重点）+ 潮刃（docs/91 精二「涌潮」），S3 加水柱、S2 浪体更大。
// The crescent / echo / trace recipe is adapted from Sprite Fusion's open-source slash
// (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skadi slash unleashed",
  desc: "Top-down greatsword strikes: a lean deep-sea crescent for basics, a fast two-to-three-swing combo with blade afterimages, a rising water curtain that topples and splashes, a broken wave wall all around.",
  tags: ["melee", "slash", "greatsword", "water", "topdown", "one-shot"],
  size: [260, 260],
  origin: [130, 130],
  duration: 1.25,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#0b1529", ...OP.skadi],   // 11-03 §12.6：改用 house.js OP.skadi 7 阶（原水青 #34a8dc / #7fe0f4 和敌方青弹 #33ceff 色差仅 15–18），最暗一阶为压暗底色
    accent: "#5ff0cc",   // E2 专属颜色重点（海绿，和敌方红 / 品红危险色分开）
    radius: 80,
    span: 3.5,
    heavy: 0,
    quick: 0,         // 1 = 余韵短（队友版）
    move: "basic",    // basic / s1 / s2 / s3
    elite: 2,         // 0 / 1 / 2
    fine: 1,          // 变细 A（缺省开）
    spray: 0,         // 往外甩的水珠 / 火星（1 = 甩；11-04 用户取消「洒水出去」，缺省 0；水雾 VAPOUR、浪沫 STAR、成团水花不受影响）
    layer: "all",     // core / deco / all（分层导出时由 pixelfx_export.py 传）
    seed: 3,
  },
};

const onArc = (s, r, a) => [(s.ox || 0) + Math.cos(a) * r, (s.oy || 0) + Math.sin(a) * r];   // ox / oy：弧心偏移（S1 连斩每刀不同）

function crescent(p, s, ta, L, W, age, hot, core, deco) {
  if (Math.abs(L) < 0.02 || W < 0.3) return;
  const R = s.ramp, n = R.length, dir = Math.sign(L), span = Math.abs(L), B = s.R + 4, ox = s.ox || 0, oy = s.oy || 0;
  if (core) p.shade(ox - B, oy - B, ox + B, oy + B, (x, y, out) => {
    const r = Math.hypot(x - ox, y - oy), ang = Math.atan2(y - oy, x - ox);
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
    let ci = q < 0.2 && age < 0.5 ? 0 : Math.round(q * (n - 1) * 0.75 + age * 2.8 - v * 1.1 + 0.3 - hot);
    if (s.streak && ci > 0) ci -= Math.max(0, Math.round(1.3 * noise(r * 1.15, s.seed + 101)));   // 纤维拖尾纹理：沿弧方向的亮细纹（借原作普攻刀光 trail_46 的竖纹；只提亮不压暗）
    out.c = R[n - 1 - clamp(ci, s.minI || 0, n - 1)];
    out.a = q > 0.8 ? 0.7 : 1;   // 刀身内沿半透明
  });
  if (deco) for (let u = 0; u <= span; u += 0.18) {   // 刀身光晕归装饰层
    const [x, y] = onArc(s, s.R - W * 0.4, ta + dir * u);
    p.glow(x, y, 10 + W, R[n - 3], (0.28 * (1 - age) * (u / span) + 0.04 * hot) * s.GK);
  }
}

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), heavy = +o.heavy > 0, full = o.span > 6, quick = +o.quick > 0;
  const el = clamp(Math.round(+o.elite), 0, 2), mv = o.move || "basic", fine = +o.fine > 0, ACC = o.accent;
  const SPRAY = +o.spray > 0;
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
  const arcOn = mv !== "s1";   // S1 不画单月牙，主形是连斩

  // ---- S1：快速连斩。2–3 道大剑斩弧，正反手交替、中心角 / 弧长 / 半径各不同，前后间隔约 0.05 s
  const sls = [];
  if (mv === "s1") {
    const sg = Rg.chance(0.5) ? 1 : -1, n = el === 0 ? 2 : 3, cs = [Rg.range(-0.1, 0.1), Rg.range(0.25, 0.42) * sg, -Rg.range(0.22, 0.4) * sg];   // 三刀都落在正前方扇区（11-04 用户「太像画圆圈」：不再左右铺开绕身）
    let dir = Rg.chance(0.5) ? 1 : -1;
    for (let i = 0; i < n; i++) {
      // 每刀弧心各自偏一点（前后 / 左右），半径不同：几道弧互相交叉，不叠成一道、也不排成同心圈；外缘不出判定半径
      const oa = Rg.range(-Math.PI, Math.PI), od = R0 * Rg.range(0.06, 0.2), ox = Math.cos(oa) * od, oy = Math.sin(oa) * od;
      const R = (R0 - od) * [Rg.range(0.9, 1.0), Rg.range(0.66, 0.76), Rg.range(0.8, 0.88)][i], sp = (Rg.range(1.1, 1.6) + (el === 0 ? 0.35 : 0)) * (i ? 0.92 : 1);   // E0 只有两刀，每刀长一点
      sls.push({ c: cs[i], sp, dir, t0: i * 0.05 + Rg.range(0, 0.012), last: i === n - 1,
        S: { seed: o.seed + 13 * i, R, W: W * [1.3, 1.2, 1.15][el] * Rg.range(1.0, 1.1), ramp: C, GK, edge: fine, streak: true, ox, oy },   // 每刀比同档普攻粗一点（弧短，宽度补回醒目度；E0 也要和普攻一样醒目）
        ghosts: el === 0 ? [] : el === 1 ? [Rg.range(0.2, 0.28)] : [Rg.range(0.16, 0.22), Rg.range(0.36, 0.46)],   // 剑身残影落后的角度（不等距；E0 不画）
        clumps: [] });
      dir = -dir;
    }
  }
  const SWS = 0.05;   // 连斩每刀的挥砍时长（比普攻快）
  const slHead = (sl, u) => sl.c - sl.dir * sl.sp / 2 + sl.dir * sl.sp * ease.outExpo(clamp(u / SWS));
  // ---- S2：斩击弧上立起的水幕（各列高度起伏），往前卷倒拍落
  const S2H = R0 * [0.55, 0.7, 0.9][el], S2A = [0.5, 0.65, 0.85][el];
  const curtain = (a, k) => S2H * k * (0.55 + 0.45 * noise(a * 4, o.seed + 61) + 0.2 * noise(a * 11, o.seed + 67)) * Math.pow(Math.cos(clamp(a / S2A, -1, 1) * Math.PI / 2), 0.7);
  // ---- S3：浪墙高度（连续起伏、有断口）；E2 几根水柱
  const wallH = (a) => Math.max(0, 16 * [0.75, 1, 1.25][el] * (0.45 + 0.7 * noise(a * 2.3, o.seed + 41) + 0.35 * noise(a * 6.1, o.seed + 43)));
  const pillars = [];
  // 11-04 用户「太像画圆圈」：S3 不再画一整圈，改成几段不等长、高低起伏的浪身，朝各自方向拍出去，中间留缺口
  const segs = [];
  if (full) {   // 总组长 11-04 审：朝向方向（帧条正右）一段主浪，体量约两倍、推得最远；两侧各 1–2 段小浪，长度 / 半径 / 出现时间错开、不按 90° 对称；背后留空（只有碎沫）
    const mk = (c, h, rk, hk, push, d) => segs.push({ c, h, rk, hk, push, d, dir: Rg.chance(0.5) ? 1 : -1, seed: o.seed + 200 + segs.length * 7 });
    mk(Rg.range(-0.08, 0.08), Rg.range(0.62, 0.75), Rg.range(0.92, 1.0), Rg.range(1.9, 2.2), Rg.range(0.4, 0.5), 0);   // 主浪
    const nl = Rg.chance(0.5) ? 1 : 2, nr = 3 - nl;   // 一侧 1 段、另一侧 2 段
    let a = Rg.range(0.95, 1.25);
    // 侧浪约主浪一半（总组长 11-04：原来只剩几块白三角像碎点）：带浪身、浪尖和碎沫，长度 / 时间仍错开
    for (let q = 0; q < nl; q++) { const h = Rg.range(0.3, 0.42); mk(a + h, h, Rg.range(0.74, 0.92), Rg.range(0.95, 1.15), Rg.range(0.14, 0.26), Rg.range(0.03, 0.11)); a += 2 * h + Rg.range(0.25, 0.45); }
    a = -Rg.range(0.8, 1.1);
    for (let q = 0; q < nr; q++) { const h = Rg.range(0.26, 0.38); mk(a - h, h, Rg.range(0.7, 0.9), Rg.range(0.9, 1.1), Rg.range(0.12, 0.24), Rg.range(0.04, 0.12)); a -= 2 * h + Rg.range(0.28, 0.5); }
    if (mv === "s3" && el >= 2) for (const sg of segs) if (sg.hk > 1.5) pillars.push({ a: sg.c + Rg.range(-0.3, 0.3) * sg.h, H: Rg.range(36, 54), d: sg.d + Rg.range(0.02, 0.06) });
  }
  const inSeg = (a) => segs.some((sg) => Math.abs(Math.atan2(Math.sin(a - sg.c), Math.cos(a - sg.c))) < sg.h);
  // 浪舌：从斩痕里涌起、沿方向往前推进、浪头往上卷再碎开（S2 水幕的通用版；c = 中心角，hA = 半张角，H = 浪高，u = 起涌后秒数）
  function waveFront(p, c, hA, Rb, H, u, sd, crest) {
    const rise = ease.outCubic(clamp(u / 0.16)), fall = smooth(0.2, 0.34, u), curl = smooth(0.06, 0.24, u);
    if (rise <= 0.02 || fall >= 0.98) return;
    for (let a = -hA; a <= hA; a += 0.4 / Rb) {
      const env = (0.55 + 0.45 * noise(a * 4, sd + 61) + 0.2 * noise(a * 11, sd + 67)) * Math.pow(Math.cos(clamp(a / hA, -1, 1) * Math.PI / 2), 0.7);
      if (env < 0.08) continue;
      const [bx, by] = onArc(A, Rb, c + a);
      const dir = c + a * 0.55, cx = Math.cos(dir), cy = Math.sin(dir);
      const jagL = 1 + 0.18 * noise(a * 23, sd + 89) + 0.1 * noise(a * 51, sd + 97);
      const Lm = R0 * 0.5 * (0.35 + 0.65 * env) * jagL * clamp(H / (R0 * 0.36), 0.7, 1.6), L = Lm * rise, up = H * 0.45 * env;   // 浪越大推得越远（S3 主浪）
      for (let d = Lm * fall; d < L; d += 0.6) {
        const v = d / Lm, back = curl * Math.pow(v, 4) * up * 0.6, lift = up * Math.sin(Math.PI * 0.5 * v) * (0.4 + 0.6 * curl);
        const x = bx + cx * (d - back), y = by + cy * (d - back) - lift;
        const tipz = d > L - 2.2, n = noise(a * 9 + v * 6, sd + 87) + 0.6 * noise(a * 31 + v * 17, sd + 93);
        p.px(x, y, tipz ? (crest ? ACC : C[6]) : C[clamp(Math.round(2.6 + 2.6 * v + 1.6 * n), 2, 6)]);
      }
    }
  }

  function drawArc(p, s, t0, hold, trail) {
    const u = t - t0;
    if (u < 0) return;
    const head = ease.outExpo(clamp(u / SW)), tail = smooth(SW + hold, SW + hold + trail, u), age = clamp(u / (SW + hold + trail));
    const hot = u < (full ? 0.06 : 0.09) ? HOT : u < 0.13 ? 0.3 : 0;   // 白热 1–2 帧、第 3 帧起回落（docs/242 §9.3；全方向整圈面积大，只白 1 帧）
    if (tail < 1) crescent(p, s, a0 + span * tail, span * (head - tail), s.W * (1 - tail * 0.5), age, hot, core, deco);
  }
  function spray(x, y, nx, ny, n, sp, life) {
    if (!SPRAY) return;   // 11-04 用户：「斯卡蒂洒水出去的特效是不是可以取消」
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
          if (SPRAY) ps.spawn(P.MOTE, x, y, (tx * 0.6 + nx * 0.9) * sp, (ty * 0.6 + ny * 0.9) * sp, Rg.range(0.25, 0.55) * (0.6 + 0.4 * DL), C[6 + Rg.int(0, 1)], Rg.range(0.8, 1.4) * SZ);
        }
        if (SPRAY && Rg.chance(0.7 * PM)) ps.spawn(P.SPARK, x, y, nx * Rg.range(100, 260), ny * Rg.range(100, 260) - 60, Rg.range(0.3, 0.65));
        if (deco && Rg.chance(0.3) && (!full || inSeg(a))) ps.spawn(P.VAPOUR, x + nx * 5, y + ny * 5, nx * 40 + tx * 25, ny * 40 + ty * 25, Rg.range(0.25, 0.45), C[5], Rg.range(2, 4));
        passed += (full ? 0.025 : 0.035) * Rg.range(0.4, 1.8) / (fine ? 1.4 : 1);   // 步长随机：等距撒会排成等距放射纹
      }
      if (mv === "s1") for (const sl of sls) {   // 连斩甩水：挥砍途中沿外缘顺挥剑方向甩；挥到底炸出成团水花
        const u = t - sl.t0;
        if (u < 0) continue;
        if (u < SWS + dt) {
          const a = slHead(sl, u), tx = -Math.sin(a) * sl.dir, ty = Math.cos(a) * sl.dir, [x, y] = onArc(sl.S, sl.S.R + Rg.range(-2, 2), a);
          for (let k = 0, m = Math.round(2 * PM); k < m; k++) {   // 三刀叠起来颗粒很密，每刀每帧少甩一点（颗粒光晕叠多了会过「持续白」）
            const v = Rg.range(120, 280);
            if (SPRAY) ps.spawn(k % 4 ? P.MOTE : P.SPARK, x, y, (tx * 0.85 + Math.cos(a) * 0.5) * v, (ty * 0.85 + Math.sin(a) * 0.5) * v, Rg.range(0.25, 0.5) * (0.6 + 0.4 * DL), C[Rg.chance(0.25) ? 7 : 6], Rg.range(0.7, 1.2) * SZ);   // 冰蓝为主、纯白少（连斩颗粒密，纯白多了过「持续白」）
          }
        }
        if (!sl.done && u >= SWS) {
          sl.done = true;
          const ae = sl.c + sl.dir * sl.sp / 2;
          for (let i = 0, m = el === 0 ? 2 : 3; i < m; i++) {
            const a = ae - sl.dir * Rg.range(0, 0.5), [x, y] = onArc(sl.S, sl.S.R + Rg.range(0, 5), a), b = [];
            for (let j = 0, q = Rg.int(3, 6); j < q; j++) b.push([Rg.range(-4, 4), Rg.range(-4, 4), Rg.range(1, 2.4) * SZ / 0.6 * 0.8, Rg.chance(0.3) ? 1 : 0]);
            sl.clumps.push({ x, y, vx: (-Math.sin(a) * sl.dir * 0.7 + Math.cos(a) * 0.4) * 60, vy: (Math.cos(a) * sl.dir * 0.7 + Math.sin(a) * 0.4) * 60, t0: t, b });
          }
        }
      }
      if (!landed && t >= SW) {
        landed = true;
        if (!full) lights.add(0, 0, R0 * 1.2, C[5], 0.15 * GK, 0.35);
        else for (const sg of segs) { const [lx, ly] = onArc(A, A.R * sg.rk, sg.c); lights.add(lx, ly, R0 * 0.5, C[5], 0.18 * GK, 0.35); }   // S3：光跟着各段浪身，不在中心铺一盏圆光
        if (arcOn) lights.add(tip[0], tip[1], 46, C[6], 0.9 * GK, 0.3);
        if (arcOn) for (let a = a0 + 0.1; a < a1; a += Rg.range(0.08, 0.2) / PM) {   // 余韵：外缘碎成浪沫与水雾（S3 只在各段浪身上，缺口里不放）
          if (full && !inSeg(a)) continue;
          const [x, y] = onArc(A, A.R + Rg.range(-2, 5), a), nx = Math.cos(a), ny = Math.sin(a), sp = Rg.range(15, 60);
          ps.spawn(P.VAPOUR, x, y, nx * sp, ny * sp, Rg.range(0.5, 0.85) * LQ, C[4 + Rg.int(0, 1)], Rg.range(2.5, 5.5), Rg.range(0, 0.08));
          if (el >= 1 && Rg.chance(0.5)) ps.spawn(P.STAR, x + Rg.range(-4, 4), y + Rg.range(-4, 4), nx * 6, ny * 6 - 4, Rg.range(0.35, 0.7) * LQ, C[6 + Rg.int(0, 1)], Rg.range(1, 2) * SZ, Rg.range(0.05, 0.4) * LQ);
          if (SPRAY && Rg.chance(0.7)) ps.spawn(P.SPARK, x, y, nx * sp * 3, ny * sp * 3 - Rg.range(40, 140), Rg.range(0.35, 0.7) * LQ);
        }
        if (arcOn && !full) {
          const ta = Math.atan2(Math.cos(a1), -Math.sin(a1));
          for (let i = 0, m = Math.round(20 * PM); i < m; i++) {
            const a = ta + Rg.range(-0.8, 0.8), sp = Rg.range(120, 320);
            if (SPRAY) ps.spawn(P.SPARK, tip[0], tip[1], Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.45));
          }
        }
        if (mv === "s3") for (let a = Rg.range(0, 0.2); a < TAU; a += Rg.range(0.05, 0.22)) {   // 浪墙顶甩出白沫
          const h = wallH(a);
          if (h < 9 || !Rg.chance(0.6)) continue;
          const [x, y] = onArc(A, A.R + h, a);
          if (SPRAY) ps.spawn(P.MOTE, x, y, Math.cos(a) * Rg.range(30, 90), Math.sin(a) * Rg.range(30, 90) - 30, Rg.range(0.4, 0.75) * LQ, C[6], Rg.range(0.9, 1.6) * SZ);
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
      if (arcOn && el >= 1 && mv === "s2") drawArc(p, E, 0.025, 0.04 * DL, 0.3 * DL);   // S2 内弧回声（普攻 / S3 不画：同心弧读成圈，11-04）
      if (arcOn && !full) drawArc(p, A, 0, 0.07, 0.4 * (0.6 + 0.4 * DL));
      if (full) for (const sg of segs) {   // S3：一段段浪身弧刃（各自半径 / 起手先后不同、正反向交替），不连成整圈
        const u = t - sg.d;
        if (u < 0) continue;
        const sp = sg.h * 2, head = ease.outExpo(clamp(u / SW)), tail = smooth(SW + 0.07, SW + 0.07 + 0.4 * (0.6 + 0.4 * DL), u), age = clamp(u / (SW + 0.07 + 0.4 * (0.6 + 0.4 * DL)));
        const pr = 1 + sg.push * ease.outCubic(clamp(u / 0.35));   // 每段各自往外拍出去（推进距离不同），不停在同一圈上
        const S = { seed: sg.seed, R: A.R * sg.rk * pr, W: A.W * (0.85 + 0.45 * sg.hk), ramp: C, GK, edge: fine, minI: sg.hk < 1.5 ? 1 : 0 };   // 侧浪不出纯白（minI：免得只剩白色小三角）
        const ta = sg.c - sg.dir * sg.h;
        if (tail < 1) crescent(p, S, ta + sg.dir * sp * tail, sg.dir * sp * (head - tail), S.W * (1 - tail * 0.5), age, u < 0.06 && sg.hk >= 1.5 ? HOT : 0, core, deco);   // 白热只给主浪
        if (core) waveFront(p, sg.c, sg.h * 0.9, A.R * sg.rk * 0.75 * pr, R0 * 0.36 * sg.hk * [0.75, 1, 1.2][el], u - SW * 0.5, sg.seed, el >= 2);   // 浪从这段斩痕里往外拍出去再碎开
      }
      if (core && mv === "basic" && el >= 1 && t > SW * 0.7) waveFront(p, 0, span * (el >= 2 ? 0.36 : 0.26), A.R * 0.55, R0 * (el >= 2 ? 0.42 : 0.28), t - SW * 0.7, o.seed + 300, el >= 2);   // 普攻 E1+：浪从斩痕里往前涌、卷起再碎开（E2 更大、浪头海绿）
      if (mv === "s1") for (const sl of sls) {   // 连斩：斩弧 + 剑身残影 + 成团水花
        const u = t - sl.t0;
        if (u < 0) continue;
        const ta0 = sl.c - sl.dir * sl.sp / 2, head = ease.outExpo(clamp(u / SWS)), trail = 0.3 * (0.7 + 0.3 * DL);
        const tail = smooth(SWS + 0.03, SWS + 0.03 + trail, u), age = clamp(u / (SWS + 0.03 + trail));
        const hot = u < 0.05 ? (sl === sls[0] ? Math.max(HOT, 1.2) : Math.max(1.0, HOT * 0.6)) : 0;   // 第一刀白热最强（不低于普攻），后两刀弱一些（三刀连着全白会过「持续白」）
        if (tail < 1) crescent(p, sl.S, ta0 + sl.dir * sl.sp * tail, sl.dir * sl.sp * (head - tail), sl.S.W * (1 - tail * 0.5), age * 0.85, hot, core, deco);
        if (core && u < SWS + 0.07) for (let gi = 0; gi < sl.ghosts.length; gi++) {   // 剑身残影：挥砍头后面一两把淡淡的大剑轮廓
          const ga = slHead(sl, u) - sl.dir * sl.ghosts[gi], k = (1 - clamp(u / (SWS + 0.07))) * (gi ? 0.45 : 0.75);
          if (Math.abs(ga - ta0) > sl.sp || k <= 0.02) continue;
          // 大剑剪影：剑柄 → 护手 → 宽剑身 → 收尖剑尖；1 格亮描边 + 半透明淡填充；剑身顺挥剑方向往后斜一点（拖在挥砍头后面）
          const hx = sl.S.ox + Math.cos(ga) * sl.S.R * 0.28, hy = sl.S.oy + Math.sin(ga) * sl.S.R * 0.28;   // 握把处
          const ba = ga - sl.dir * 0.22, ux = Math.cos(ba), uy = Math.sin(ba), vx = -uy, vy = ux;
          const L = sl.S.R * 0.7, GR = 7, BW = 4.2, GRIP = 9;   // 剑尖落在判定半径以内
          const shape = (al, ac) => {   // 剑的局部坐标（al 沿剑、ac 横向）→ 0 外 / 1 填充 / 2 描边
            const aa = Math.abs(ac);
            let hw;
            if (al < -GRIP - 2 || al > L) return 0;
            if (al < -GRIP) hw = 2.2;                                   // 剑首
            else if (al < 0) hw = 1.3;                                  // 剑柄
            else if (al < 2.2) hw = GR;                                 // 护手
            else if (al < L * 0.82) hw = BW;                            // 剑身
            else hw = BW * (L - al) / (L * 0.18);                       // 收尖
            if (aa > hw) return 0;
            const edge = aa > hw - 1.1 || al < -GRIP - 0.9 || (al > 0 && al < 2.2 && (al < 0.9 || al > 1.3)) || al > L - 1.5;
            return edge ? 2 : 1;
          };
          const ex = L + 2, bb = [hx - ux * (GRIP + 3), hy - uy * (GRIP + 3), hx + ux * ex, hy + uy * ex];
          const pad = GR + 2;
          p.each(Math.min(bb[0], bb[2]) - pad, Math.min(bb[1], bb[3]) - pad, Math.max(bb[0], bb[2]) + pad, Math.max(bb[1], bb[3]) + pad, (x, y, sx, sy) => {   // 真半透明（blendPx），不用抖动（抖动会碎成点阵）
            const dx = x - hx, dy = y - hy, al = dx * ux + dy * uy, ac = dx * vx + dy * vy, m = shape(al, ac);
            if (!m) return;
            p.blendPx(sx, sy, m === 2 ? C[6] : (al > 2.2 && Math.abs(ac) < 0.8 ? C[5] : C[3]), (m === 2 ? 0.85 : 0.4) * k);   // 剑身中脊亮一阶
          });
        }
        if (core && sl === sls[0] && u < 0.04) {   // 起手剑身一闪（借原作 trail_08 的细长闪光）
          const cx = Math.cos(ta0), cy = Math.sin(ta0);
          for (let r = sl.S.R * 0.5; r < sl.S.R; r += 0.6) p.px(sl.S.ox + cx * r, sl.S.oy + cy * r, C[7]);
        }
        if (core) for (const cl of sl.clumps) {   // 成团水花（借原作 water_08 的卷曲水团）：挥到底处炸出几团，慢慢散
          const v = t - cl.t0;
          if (v < 0 || v > 0.22 * (0.6 + 0.4 * DL)) continue;
          const k = 1 - v / (0.22 * (0.6 + 0.4 * DL));
          for (const b of cl.b) p.disc(cl.x + b[0] + cl.vx * v, cl.y + b[1] + cl.vy * v, b[2] * (0.5 + 0.5 * k), b[3] && el >= 2 ? ACC : C[b[3] ? 7 : 6], 0.95 * k);
        }
        if (core && el >= 2 && sl.last && u > SWS) {   // E2 潮刃：最后一刀甩出一道薄新月往外飞（docs/91 精二「涌潮」）
          const w = u - SWS, d = 64 * ease.outCubic(clamp(w / 0.3)), k = 1 - smooth(0.12, 0.32, w);
          if (k > 0) {
            const TB = { seed: o.seed + 31, R: sl.S.R + d, W: Math.max(2, sl.S.W * 0.5) * k, ramp: C, GK, edge: false, minI: 1, ox: sl.S.ox, oy: sl.S.oy };
            crescent(p, TB, sl.c - sl.dir * sl.sp * 0.3, sl.dir * sl.sp * 0.6, TB.W, 0.15 + 0.5 * (1 - k), 0, true, false);
          }
        }
        if (core && el >= 1 && sl.last && u > SWS) waveFront(p, sl.c, sl.sp * (el >= 2 ? 0.4 : 0.3), sl.S.R * 0.55, R0 * (el >= 2 ? 0.4 : 0.28), u - SWS, sl.S.seed + 300, el >= 2);   // E1+ 最后一刀后浪从斩痕里往前涌（11-04）
        if (core && el >= 1 && u > SWS * 0.8 && u < 0.4) {   // E1+ 每刀外缘白沫（断续）
          const k = 1 - smooth(0.15, 0.4, u);
          for (let a = 0; a < sl.sp * head; a += 0.6 / sl.S.R) {
            const n = noise(a * 8, sl.S.seed + 51) + 0.5 * noise(a * 21, sl.S.seed + 53);
            if (n < 0) continue;
            const th = (0.8 + 1.4 * clamp(n)) * k, aa = ta0 + sl.dir * a;
            for (let d = 0; d < th; d += 0.6) p.px(sl.S.ox + Math.cos(aa) * (sl.S.R + 1 + d), sl.S.oy + Math.sin(aa) * (sl.S.R + 1 + d), C[6]);
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
      if (core && mv === "s3" && !full) {   // （旧）浪墙：外缘立起一圈深色浪身；11-04 起 S3 走上面的段状浪身，这里只在非全方向时画
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
          const H = pl.H * ease.outCubic(clamp(u / 0.12)) * (1 - smooth(0.22, 0.4, u)), [bx, by] = onArc(A, A.R * 0.95, pl.a);
          for (let d = 0; d < H; d += 0.6) {
            const w = 3.6 * (1 - d / Math.max(1, H) * 0.7);
            for (let s = -w; s <= w; s += 0.6) p.px(bx + s, by - d, d > H - 2 ? ACC : C[clamp(Math.round(3 + 3 * d / Math.max(1, H) - Math.abs(s) / w), 2, 6)]);
          }
        }
      }
      if (core && el >= 1 && arcOn && !full && t > SW * 0.8 && t < 0.45 + 0.15 * el) {   // E1+ 浪尖白沫带：沿外缘断断续续
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
      if (core && el >= 2 && arcOn && !full && mv === "s2" && t > SW * 0.5) {   // E2 二次浪峰（只给 S2；普攻改浪舌，11-04）：外缘后面再涌起一道海绿色浪峰，比主弧短、慢半拍
        const u = t - SW * 0.5, k = smooth(0, 0.08, u) * (1 - smooth(0.2, 0.4, u));
        if (k > 0.02) for (let a = a0 + span * 0.25; a < a1 - span * 0.08; a += 0.5 / A.R) {
          const v = (a - a0 - span * 0.25) / (span * 0.67), h = (4 + 8 * Math.sin(Math.PI * v)) * k * (0.7 + 0.5 * noise(a * 6, o.seed + 91));
          for (let d = 0; d < h; d += 0.6) {
            const [x, y] = onArc(A, A.R + 3 + d, a);
            p.px(x, y, d > h * 0.55 ? ACC : C[clamp(Math.round(3 + 2 * d / Math.max(1, h)), 3, 5)]);
          }
        }
      }
      if (core && el >= 2 && arcOn && !full && mv === "s2" && t > SW) {   // E2 潮刃：一道薄新月从弧上脱出、往外飞（docs/91 精二「涌潮」；普攻不再飞同心新月，11-04）
        const u = t - SW, d = 70 * ease.outCubic(clamp(u / 0.3)), k = 1 - smooth(0.12, 0.32, u);
        if (k > 0) {
          const TB = { seed: o.seed + 31, R: A.R + d, W: Math.max(2, W * 0.4) * k, ramp: C, GK, edge: false, minI: 1 };
          crescent(p, TB, -span * 0.32, span * 0.64, TB.W, 0.15 + 0.5 * (1 - k), 0, true, false);
        }
      }
      if (deco && arcOn && t < 0.32) {
        const [x, y] = full ? onArc(A, A.R * 0.9, segs[0].c) : onArc(A, A.R - 6, a0 + span * ease.outExpo(clamp(t / SW)));   // S3：光只跟主浪，背后不亮
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
