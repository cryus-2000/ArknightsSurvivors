// 萨米结局 Boss 招牌招特效方向样张（11-25，只出样张不实装）：每个 Boss 两个方向 A / B，整屏 640×360 纹素（1 纹素 = 2 世界像素），原点 = 屏幕中心。
// 口径：pixelfx 实心主形 + Noita 颗粒；同招 ≤3 种元素；不画平涂半透明盘 / 细环；每招有出现过程（预兆 → 成形 → 爆发 → 散掉）。
// 配色：Boss 弹按 docs/393 §1.2 专属色（白芯 + 色环）；特效主形先取原作预制体颜色（F:/sami_enemy_fx_ref digest），两者冲突的在 B 方向换成专属色对照。
// layer：under = 贴地件（影子 / 地裂 / 眼纹 / 场格子，画在 Boss 本体下面）；over = 其余（画在本体上面）。本体与残影由合成脚本画。
// 位置 / 时间轴与 tools/sami_final_fx_mock.py 的 TIMELINE 一一对应，改一边要同步另一边。
import { Rng, clamp, ease, TAU, WHITE, hex, mix } from "../../core/index.js";

const H = (a) => a.map(hex);
const WILL = H(["#120822", "#2c1450", "#4e2a86", "#7b55c0", "#b49cec", "#e4dcff", "#ffffff"]);   // 意志：淡紫白 → 虹光紫 → 深紫（392 §6.0）
const ICE = H(["#0a2a4a", "#2a6aa8", "#68b4ec", "#aee2ff"]);                                       // 原作 xueli / baoshan 冰蓝
const CRACK = H(["#0c141c", "#24323e", "#40505e"]);                                                // 原作 dilie 灰蓝地裂
const TEAL = H(["#000a06", "#00261c", "#0b4a35", "#1a7050", "#4aa37a", "#bfe8d2"]);                // 木裂原作 smlead_buff 深青绿
const RED = H(["#080000", "#260404", "#551010", "#8c1c1c", "#c8301e", "#f0a088", "#ffffff"]);      // 木裂 B / 哈兰：黑红
const INDIGO = H(["#020210", "#0b0b3a", "#1c1f78", "#3a46c8", "#6b78ff", "#c8ccff"]);              // 克雷松原作闪现：黑 + 靛蓝
const ORANGE = hex("#ff9a3a");
const YG = H(["#141a04", "#2e3a08", "#52660e", "#7f9a1e", "#b4d040", "#e8f5a0"]);                  // 克雷松专属：病黄绿
const SLATE = H(["#0e141c", "#2c3a4c", "#5a6e88", "#8fa4c0", "#c8d6e8", "#f2f6fc"]);              // 空间稳定设施 / 稳定场：冷白石板
const GOLD = H(["#1a0e00", "#4a2a00", "#8a5208", "#d08a18", "#f5c040", "#fff0c0"]);                // 路加原作：金橙（smlion）
const PURP = H(["#0c0820", "#241a58", "#3d2c9a", "#6a58f0", "#a898ff", "#e4e0ff"]);                // 路加专属：紫蓝 250°

export const meta = {
  name: "AK Sami final boss fx directions",
  desc: "Direction samples for the four Sami final bosses: icicles and a sighing gap ring, a self-destroying sprint, a blink with a stabilising field, and two kings' big slam circles.",
  tags: ["boss", "mock"],
  size: [640, 360],
  origin: [320, 180],
  duration: 7.4,
  loop: false,
  fps: 15,
  bg: "ground",
  options: { part: "willA", layer: "over", seed: 1 },
};

// 共用坐标（纹素）
export const POS = {
  will: [-150, 20],
  lead: [[-150, 30], [-60, -25], [30, 30], [125, -20]],
  cresFrom: [-130, 20], cresTo: [110, 10], device: [70, 40],
  khan: [-110, 15], lion: [110, 15],
};
export const DURS = { willA: 6.0, willB: 6.0, leadA: 6.4, leadB: 6.4, cresA: 6.5, cresB: 6.5, kingsA: 7.4, kingsB: 7.4 };

// 木裂路线：0–0.8 剥离起势；第 i 段 0.8+1.6i 起 0.6 秒站定（通用直线预警），再 1.0 秒冲
export function leadPos(t) {
  const P = POS.lead;
  for (let i = 0; i < 3; i++) {
    const d0 = 1.4 + 1.6 * i;
    if (t < d0) return { x: P[i][0], y: P[i][1], dash: -1, seg: i };
    if (t < d0 + 1.0) {
      const u = ease.inOutQuad((t - d0) / 1.0);
      return { x: P[i][0] + (P[i + 1][0] - P[i][0]) * u, y: P[i][1] + (P[i + 1][1] - P[i][1]) * u, dash: i, seg: i };
    }
  }
  return { x: P[3][0], y: P[3][1], dash: -1, seg: 3 };
}

export function create(o) {
  const P = o.part, U = o.layer === "under", Rn = new Rng(o.seed || 1);
  const R = (a, b) => Rn.range(a, b);
  let t = 0;

  // ---------- 小件 ----------
  function shard(p, x, y, ang, len, wid, body, edge) {   // 菱形冰凌 / 碎片：尖朝 ang
    const c = Math.cos(ang), s = Math.sin(ang), nx = -s, ny = c;
    const tip = [x + c * len, y + s * len], back = [x - c * len * 0.35, y - s * len * 0.35];
    const l = [x + nx * wid / 2, y + ny * wid / 2], r = [x - nx * wid / 2, y - ny * wid / 2];
    p.poly([tip, l, back, r], body);
    if (edge != null) p.poly([tip, l, [x, y]], edge);
  }
  function star4(p, x, y, L, w, c, core = WHITE) {
    for (const [dx, dy, k] of [[1, 0, 1], [-1, 0, 1], [0, 1, 0.7], [0, -1, 0.7]]) {
      const l = L * k;
      p.poly([[x + dx * l, y + dy * l], [x - dy * w, y + dx * w], [x - dx * w, y - dy * w], [x + dy * w, y - dx * w]], c);
    }
    p.circle(x, y, Math.max(1, w), core);
  }
  function bullet(p, x, y, r, ring) {   // Boss 弹：白芯 + 专属色环（docs/393 §1.2）
    p.circle(x, y, r, ring);
    p.circle(x, y, r * 0.55, WHITE);
  }
  function jagPts(x0, y0, x1, y1, n, amp) {
    const pts = [[x0, y0]], dx = x1 - x0, dy = y1 - y0, L = Math.hypot(dx, dy) || 1, nx = -dy / L, ny = dx / L;
    for (let i = 1; i < n; i++) { const u = i / n, j = R(-amp, amp); pts.push([x0 + dx * u + nx * j, y0 + dy * u + ny * j]); }
    pts.push([x1, y1]);
    return pts;
  }
  function drawJag(p, pts, q, w, c, inner) {   // 画到 q（0–1）为止的折线裂纹
    const n = pts.length - 1, upto = q * n;
    for (let i = 0; i < n; i++) {
      if (i >= upto) break;
      const f = Math.min(1, upto - i), a = pts[i], b = pts[i + 1];
      const bx = a[0] + (b[0] - a[0]) * f, by = a[1] + (b[1] - a[1]) * f;
      if (w <= 1) p.line(a[0], a[1], bx, by, c);
      else p.beam(a[0], a[1], bx, by, w, c);
      if (inner != null) p.line(a[0], a[1], bx, by, inner);
    }
  }
  // 解析颗粒（按出生时间算位置，确定性）
  function mkParts(n, fn) { return Array.from({ length: n }, (_, i) => fn(i)); }
  function drawPart(p, q, now) {
    const a = now - q.t0;
    if (a < 0 || a > q.life) return;
    const x = q.x + q.vx * a, y = q.y + q.vy * a + 0.5 * (q.g || 0) * a * a;
    const s = q.s * (q.shrink ? 1 - a / q.life * 0.6 : 1);
    if (q.kind === "chip") {
      const ang = q.rot + q.spin * a;
      p.tri(x + Math.cos(ang) * s, y + Math.sin(ang) * s, x + Math.cos(ang + 2.3) * s, y + Math.sin(ang + 2.3) * s, x + Math.cos(ang + 4.0) * s * 0.7, y + Math.sin(ang + 4.0) * s * 0.7, q.c);
    } else if (q.kind === "streak") {
      p.beam(x, y, x - q.vx * 0.05, y - q.vy * 0.05, Math.max(1, s), q.c);
    } else if (s >= 1.5) p.rect(Math.round(x - s / 2), Math.round(y - s / 2), Math.round(s), Math.round(s), q.c);
    else p.dot(x, y, q.c);
  }

  // ---------- 预生成 ----------
  const [WX, WY] = POS.will, WCH = [WX, WY - 30];   // 意志胸口
  const cols = [10, 90], rows = [-120, -72, -24, 24, 72, 120];
  const icicles = [];
  cols.forEach((cx, ci) => rows.forEach((ry, ri) => icicles.push({ x: cx + R(-3, 3), y: ry, t0: ci * 0.6 + ri * 0.07, cr: Array.from({ length: 4 }, (_, k) => jagPts(cx, ry, cx + Math.cos(k * 1.57 + R(-0.4, 0.4)) * R(9, 14), ry + Math.sin(k * 1.57 + R(-0.4, 0.4)) * R(5, 8), 3, 1.5)) })));
  const icChips = icicles.map((ic) => mkParts(7, (i) => ({ kind: "chip", x: ic.x, y: ic.y - 6, vx: R(-55, 55), vy: R(-70, -10), g: 240, t0: ic.t0 + (P === "willA" ? 0.8 : 1.25) + R(0, 0.04), life: R(0.35, 0.55), s: R(2, 3.5), rot: R(0, TAU), spin: R(-12, 12), c: [WILL[2], WILL[3], WILL[4], ICE[2]][i % 4] })));
  const colCrack = cols.map((cx) => jagPts(cx, -140, cx, 140, 28, 2.5));
  const GAPS = [[0.15, 0.62], [2.45, 2.92]];
  const inGap = (a) => { a = ((a % TAU) + TAU) % TAU; return GAPS.some(([g0, g1]) => a > g0 && a < g1); };
  const motes = mkParts(40, () => ({ a: R(0, TAU), r: R(90, 150), sp: R(1.2, 2.4), c: Rn.next() < 0.5 ? WILL[4] : WILL[3] }));
  const chunks = mkParts(72, (k) => ({ a: (k / 72) * TAU + R(-0.02, 0.02), j: R(-3, 3), w: R(6, 10), h: R(3.5, 5.5), c: [WILL[2], WILL[3], WILL[4]][k % 3], k }));
  const sighCracks = mkParts(10, (k) => jagPts(WX, WY, WX + Math.cos(k / 10 * TAU + R(-0.2, 0.2)) * R(34, 46), WY + Math.sin(k / 10 * TAU + R(-0.2, 0.2)) * R(20, 28), 5, 2.5));

  // 木裂
  const flakes = mkParts(260, () => ({ ts: R(0, 6.0), ox: R(-12, 12), oy: R(-50, -4), vx: R(-14, 14), vy: R(-26, -6), life: R(0.35, 0.7), s: Rn.next() < 0.5 ? 1 : 2, w: Rn.next() < 0.5, spin: R(-10, 10), rot: R(0, TAU), k: Rn.next() }));
  const wisps = mkParts(5, (k) => ({ ox: -9 + k * 4.5 + R(-1, 1), h: R(8, 14), ph: R(0, TAU) }));
  const bodyCr = mkParts(4, () => jagPts(R(-6, 6), R(-34, -26), R(-7, 7), R(-18, -10), 3, 1.5));
  const kick = [1, 2, 3].map((i) => mkParts(10, () => ({ kind: "chip", x: POS.lead[i][0], y: POS.lead[i][1], vx: R(-60, 60), vy: R(-60, 0), g: 220, t0: 2.4 + 1.6 * (i - 1), life: R(0.3, 0.5), s: R(2, 3), rot: R(0, TAU), spin: R(-10, 10), c: 0 })));

  // 克雷松
  const [C0x, C0y] = POS.cresFrom, [C1x, C1y] = POS.cresTo, [DX, DY] = POS.device;
  const needles = mkParts(30, () => ({ a: R(0, TAU), r: R(30, 60), d: R(0, 0.25) }));
  const ripSeg = mkParts(3, () => Array.from({ length: 14 }, () => R(0.75, 1.2)));
  const slit = jagPts(C1x - 22, C1y, C1x + 22, C1y, 9, 2);
  const specks = mkParts(16, () => ({ kind: "dot", x: C1x, y: C1y - 24, vx: R(-70, 70), vy: R(-80, 30), g: 90, t0: 1.5 + R(0, 0.1), life: R(0.4, 0.8), s: Rn.next() < 0.4 ? 2 : 1, c: 0 }));
  const lattice = [];
  for (let gy = -80; gy <= 80; gy += 16) for (let gx = -80; gx <= 80; gx += 16) { const d = Math.hypot(gx, gy); if (d < 78) lattice.push({ x: DX + gx + (gy / 16 % 2 ? 8 : 0), y: DY + gy * 0.8, d }); }
  const rising = mkParts(30, () => ({ a: R(0, TAU), r: Math.sqrt(Rn.next()) * 75, t0: R(1.4, 3.6), life: R(0.6, 1.0) }));

  // 双王
  const [KX, KY] = POS.khan, [LX, LY] = POS.lion, RR = 80;
  const rimOrder = mkParts(20, (k) => ({ k, at: R(0, 0.85) }));
  const kCracks = mkParts(9, (k) => { const a = k / 9 * TAU + R(-0.2, 0.2); return jagPts(LX + Math.cos(a) * RR * 0.98, LY + Math.sin(a) * RR * 0.8 * 0.98, LX + Math.cos(a + R(-0.3, 0.3)) * R(6, 16), LY + Math.sin(a) * R(4, 10), 7, 4); });
  const embersIn = mkParts(26, () => ({ a: R(0, TAU), r: R(30, 55), ph: R(0, 1), c: Rn.next() < 0.5 ? RED[3] : RED[0] }));
  const rocks = (cx, cy, t0, pal) => mkParts(18, (i) => ({ kind: "chip", x: cx + R(-10, 10), y: cy + R(-6, 6), vx: R(-120, 120), vy: R(-110, 40), g: 200, t0: t0 + R(0, 0.05), life: R(0.4, 0.75), s: R(2, 4), rot: R(0, TAU), spin: R(-14, 14), c: pal[i % pal.length] }));
  const rocksK = rocks(LX, LY, 2.5, [RED[0], RED[2], RED[1]]);
  const rocksL = rocks(KX, KY, 6.1, P === "kingsA" ? [GOLD[1], GOLD[3], GOLD[0]] : [PURP[1], PURP[3], PURP[0]]);
  const smokes = mkParts(8, () => ({ a: R(0, TAU), d: R(20, 60), r: R(5, 9) }));
  const crossStars = mkParts(16, () => ({ a: R(0, TAU), d: Math.sqrt(Rn.next()) * RR * 0.9, t0: R(0, 0.45), L: R(4, 8) }));
  const sparkOut = mkParts(14, (i) => ({ kind: "streak", x: 0, y: 0, a: i / 14 * TAU + R(-0.15, 0.15), sp: R(140, 220), life: R(0.18, 0.3), s: 2 }));

  return {
    update(dt) { t += dt; },
    draw(p) {
      // ================= 萨米的意志 =================
      if (P === "willA" || P === "willB") {
        const A = P === "willA";
        // —— 冰凌（0–2.6）——
        if (A) {
          for (const ic of icicles) {
            const tau = t - ic.t0;
            if (tau < 0 || tau > 1.7) continue;
            if (U) {
              if (tau < 0.8) { const e = ease.outCubic(tau / 0.8); p.ellipse(ic.x, ic.y, 2 + 6 * e, 1 + 2.6 * e, WILL[1]); }   // 落点影子由小变大
              else if (tau < 1.6) for (const cr of ic.cr) drawJag(p, cr, Math.min(1, (tau - 0.8) / 0.12) * (1 - Math.max(0, (tau - 1.2) / 0.4)), 1.6, CRACK[0], null);
            } else {
              if (tau > 0.5 && tau < 0.66) star4(p, ic.x, ic.y - 62, 3, 1, WILL[5]);                 // 高处一点冰光（预兆）
              if (tau >= 0.6 && tau < 0.8) { const h = 62 * (1 - (tau - 0.6) / 0.2); shard(p, ic.x, ic.y - h - 16, Math.PI / 2, 22, 8, WILL[3], WILL[5]); }
              if (tau >= 0.8 && tau < 0.87) star4(p, ic.x, ic.y - 4, 14, 2.5, WILL[4]);
              if (tau >= 0.8 && tau < 1.15) shard(p, ic.x, ic.y - 13, Math.PI / 2, 16 * (1 - (tau - 0.8) / 0.35), 7, WILL[2], WILL[4]);
            }
          }
        } else {
          for (let ci = 0; ci < 2; ci++) {
            const q = clamp((t - ci * 0.6) / 0.8), fade = clamp((t - ci * 0.6 - 1.7) / 0.4);
            if (U && t > ci * 0.6 && fade < 1) drawJag(p, colCrack[ci], q * (1 - fade), 2.2, CRACK[0], WILL[2]);   // 一条地裂沿列跑过去
          }
          if (!U) for (const ic of icicles) {
            const tau = t - ic.t0 - 0.8 - 0.0;
            if (tau < 0 || tau > 0.45) continue;
            const g = clamp(tau / 0.08), sh = tau > 0.38 ? 1 - (tau - 0.38) / 0.07 : 1;
            shard(p, ic.x - 6, ic.y, -Math.PI / 2 - 0.45, 14 * g * sh, 6, WILL[2], WILL[4]);
            shard(p, ic.x + 6, ic.y, -Math.PI / 2 + 0.45, 14 * g * sh, 6, WILL[2], WILL[4]);
            shard(p, ic.x, ic.y, -Math.PI / 2, 28 * g * sh, 9, WILL[3], WILL[5]);
            if (tau < 0.07) star4(p, ic.x, ic.y - 10, 8, 1.5, WILL[4]);
          }
        }
        if (!U) for (const cs of icChips) for (const q of cs) drawPart(p, q, A ? t : t - 0.45 + 0.45);
        // —— 叹息（2.8–6.0）——
        const s = t - 2.8;
        if (s >= 0) {
          if (A) {
            if (!U && s < 1.0) for (const m of motes) {   // 雪往胸口收
              const k = ease.inQuad(s / 1.0), rr = m.r * (1 - k) + 4, a = m.a + s * m.sp;
              const x = WCH[0] + Math.cos(a) * rr, y = WCH[1] + Math.sin(a) * rr * 0.8;
              p.rect(Math.round(x), Math.round(y), 2, 2, m.c);
              p.dot(WCH[0] + Math.cos(a - 0.12) * (rr + 4), WCH[1] + Math.sin(a - 0.12) * (rr + 4) * 0.8, WILL[2]);
            }
          } else if (U && s < 1.6) {
            for (const cr of sighCracks) drawJag(p, cr, Math.min(1, s / 1.0) * (1 - clamp((s - 1.2) / 0.4)), 2, CRACK[0], WILL[2]);   // 地裂从脚下往外爬
          }
          if (!U && s < 1.1) star4(p, WCH[0], WCH[1], s < 1.0 ? 4 + 8 * s : 24, s < 1.0 ? 1.5 : 3, s < 1.0 ? WILL[4] : WILL[5]);   // 胸口冰晶蓄光 → 呼出一闪
          if (s >= 1.0) {
            const rr = 18 + 85 * (s - 1.0);
            if (A && !U) {
              for (const c of chunks) {   // 风雪碎块环（缺口里什么都没有）
                if (inGap(c.a)) continue;
                const r = rr + c.j, ca = Math.cos(c.a), sa = Math.sin(c.a), tx = -sa, ty = ca;
                const x = WX + ca * r, y = WY + sa * r * 0.85;
                p.poly([[x + tx * c.w / 2, y + ty * c.w / 2 * 0.85], [x + ca * c.h, y + sa * c.h], [x - tx * c.w / 2, y - ty * c.w / 2 * 0.85], [x - ca * c.h * 0.6, y - sa * c.h * 0.6]], c.c);
                if (s - 1.0 < 0.6 && c.k % 2) p.rect(Math.round(WX + ca * (r - 9)), Math.round(WY + sa * (r - 9) * 0.85), 2, 2, WILL[4]);
              }
              for (const [g0, g1] of GAPS) for (const a of [g0, g1]) shard(p, WX + Math.cos(a) * rr, WY + Math.sin(a) * rr * 0.85, a, 9, 4, WILL[2], WILL[5]);
            }
            if (!A && !U) {
              for (let m = 0; m < 40; m++) {   // 冰凌一圈圈从地里顶出来，跟着波前走
                const rm = 16 + 9 * m, age = s - 1.0 - (rm - 16) / 85;
                if (age < 0 || age > 0.4) continue;
                const h = age < 0.07 ? 11 * age / 0.07 : 11 * (1 - (age - 0.07) / 0.33);
                const n = Math.round(TAU * rm / 10);
                for (let k = 0; k < n; k++) {
                  const a = (k + (m % 2) * 0.5) / n * TAU;
                  if (inGap(a)) continue;
                  const x = WX + Math.cos(a) * rm, y = WY + Math.sin(a) * rm * 0.85;
                  if (x < -330 || x > 330 || y < -190 || y > 200) continue;
                  p.tri(x - 2.5, y, x + 2.5, y, x, y - h, k % 2 ? WILL[3] : WILL[2]);
                  if (h > 4) p.line(x, y - h, x, y - h + 3, WILL[5]);
                }
              }
            }
            if (!U) for (let k = 0; k < 24; k++) {   // 24 发中圆弹骑在波前上
              const a = (k / 24) * TAU + 0.07;
              if (inGap(a)) continue;
              bullet(p, WX + Math.cos(a) * (rr + 3), WY + Math.sin(a) * (rr + 3) * 0.85, 4, WILL[3]);
            }
          }
        }
      }

      // ================= 木裂：自我泯灭 =================
      if (P === "leadA" || P === "leadB") {
        const A = P === "leadA", L = leadPos(t), on = t < 5.9, pal = A ? TEAL : RED;
        const bx = L.x, by = L.y;
        let dx = 0, dy = 0;
        if (L.dash >= 0) { const a = POS.lead[L.dash], b = POS.lead[L.dash + 1], d = Math.hypot(b[0] - a[0], b[1] - a[1]); dx = (b[0] - a[0]) / d; dy = (b[1] - a[1]) / d; }
        const grow = clamp(t / 0.8);
        if (U) {
          // 地上拖痕：A 深青刮痕两道，B 暗红细线一条（393：拖尾一律暗红细线）
          for (let i = 0; i < 3; i++) {
            const d0 = 1.4 + 1.6 * i, a = POS.lead[i], b = POS.lead[i + 1];
            if (t < d0) continue;
            const u1 = ease.inOutQuad(clamp((t - d0) / 1.0)), u0 = clamp((t - d0 - 0.5) / 0.8);
            if (u1 <= u0) continue;
            const x0 = a[0] + (b[0] - a[0]) * u0, y0 = a[1] + (b[1] - a[1]) * u0, x1 = a[0] + (b[0] - a[0]) * u1, y1 = a[1] + (b[1] - a[1]) * u1;
            if (A) { p.beam(x0, y0 - 3, x1, y1 - 3, 2, TEAL[1]); p.beam(x0, y0 + 3, x1, y1 + 3, 2, TEAL[1]); }
            else p.line(x0, y0, x1, y1, RED[3]);
          }
        } else if (on) {
          if (A) {
            for (const w of wisps) {   // 深青黑气从身上往上冒（原作 flow_01 / smoke_01），冲刺时往后倒
              const h = w.h * grow * (0.85 + 0.15 * Math.sin(t * 9 + w.ph)), sw = Math.sin(t * 6 + w.ph) * 2;
              const x0 = bx + w.ox, y0 = by - 24, x1 = x0 - dx * h * 0.9 + sw, y1 = y0 - h * (L.dash >= 0 ? 0.6 : 1) - dy * h * 0.5;
              p.poly([[x0 - 1.5, y0], [x0 + 1.5, y0], [x1, y1]], TEAL[2]);
              p.line(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2, TEAL[4]);
            }
          } else {
            for (const cr of bodyCr) {   // 身上裂出红缝（剥离）
              const pts = cr.map(([x, y]) => [bx + x, by + y]);
              drawJag(p, pts, grow, 1, t % 0.27 < 0.2 ? RED[4] : RED[3], null);
            }
          }
          // 碎屑：A 黑白碎片（原作 lizi 白 / 黑），B 黑红三角碎片；第 i 段冲刺掉得更多
          const rate = L.dash >= 0 ? 1 : 0.35;
          for (const f of flakes) {
            if (f.k > rate * (0.45 + 0.2 * Math.max(0, L.seg))) continue;
            const a = t - f.ts;
            if (a < 0 || a > f.life) continue;
            const P0 = leadPos(f.ts);
            let vx = f.vx, vy = f.vy;
            if (P0.dash >= 0) { const q0 = POS.lead[P0.dash], q1 = POS.lead[P0.dash + 1], d = Math.hypot(q1[0] - q0[0], q1[1] - q0[1]); vx -= (q1[0] - q0[0]) / d * 40; vy -= (q1[1] - q0[1]) / d * 40; }
            const x = P0.x + f.ox + vx * a, y = P0.y + f.oy + vy * a + 30 * a * a;
            if (A) p.rect(Math.round(x), Math.round(y), f.s, f.s, f.w ? hex("#eef4f0") : TEAL[0]);
            else { const s = 1.5 + f.s, an = f.rot + f.spin * a; p.tri(x + Math.cos(an) * s, y + Math.sin(an) * s, x + Math.cos(an + 2.3) * s, y + Math.sin(an + 2.3) * s, x + Math.cos(an + 4) * s * 0.6, y + Math.sin(an + 4) * s * 0.6, f.w ? RED[3] : RED[0]); }
          }
          for (const ks of kick) for (const q of ks) drawPart(p, { ...q, c: A ? [TEAL[2], TEAL[0], hex("#eef4f0")][Math.floor(q.s * 7) % 3] : [RED[0], RED[2], RED[3]][Math.floor(q.s * 7) % 3] }, t);
        }
      }

      // ================= 克雷松：闪现 + 稳定场 =================
      if (P === "cresA" || P === "cresB") {
        const A = P === "cresA", pal = A ? INDIGO : YG;
        // 落点眼纹：提前 1.5 秒睁开一半，落地后阖上
        if (U && t < 2.0) {
          const op = t < 1.5 ? 0.5 * ease.outCubic(clamp(t / 0.6)) : 0.5 * (1 - clamp((t - 1.5) / 0.4));
          const w = 22, h = 9;
          if (op > 0.02) {
            const up = [], lo = [];
            for (let i = 0; i <= 16; i++) { const x = -1 + i / 8; up.push([C1x + x * w, C1y - h * op * 2 * (1 - x * x)]); lo.push([C1x + x * w, C1y + h * 0.6 * (1 - x * x)]); }
            p.poly(up.concat(lo.reverse()), pal[1]);
            p.circle(C1x, C1y - 1, Math.min(6, h * op * 1.6), pal[3]);
            p.circle(C1x, C1y - 1, 2.5, pal[0]);
            if (t < 1.5 && t % 0.4 < 0.2) p.dot(C1x + 2, C1y - 3, pal[5]);
            if (!A) for (let k = 0; k < 4; k++) { const a = [0.3, 2.8, 3.5, 6.0][k]; p.line(C1x + Math.cos(a) * w * 0.9, C1y + Math.sin(a) * 6, C1x + Math.cos(a) * (w + 9), C1y + Math.sin(a) * 9, pal[2]); }
          }
          if (t >= 1.5) drawJag(p, slit, Math.min(1, (t - 1.5) / 0.1) * (1 - clamp((t - 1.8) / 0.3)), t < 1.7 ? 4 : 2, pal[0], pal[3]);   // 地缝裂开，本体从缝里挤出
        }
        if (!U) {
          const cx = C0x, cy = C0y - 25;
          if (A && t > 0.3 && t < 0.9) for (const n of needles) {   // 黑色速度线往身上收（原作 suduxin_bais 负速度）
            const k = clamp((t - 0.3 - n.d) / 0.5);
            if (k <= 0 || k >= 1) continue;
            const r = n.r * (1 - ease.inQuad(k));
            p.beam(cx + Math.cos(n.a) * r, cy + Math.sin(n.a) * r, cx + Math.cos(n.a) * (r + 7), cy + Math.sin(n.a) * (r + 7), 1.6, INDIGO[0]);
          }
          if (t > 0.85 && t < 0.95) star4(p, cx, cy, 14, 2, pal[3]);
          for (let k = 0; k < 3; k++) {   // 残影涟漪：粗、有断口、慢慢外扩后碎掉（不画细环）
            const age = t - 0.9 - 0.18 * k;
            if (age < 0 || age > 0.9) continue;
            const r = 8 + 36 * ease.outCubic(age / 0.9), w = 3.2 * (1 - age / 0.9) + 1.5;
            for (let i = 0; i < 14; i++) {
              if ((i + k) % 4 === 3) continue;
              const a0 = i / 14 * TAU, rr = A ? r : r * ripSeg[k][i];
              p.arc(C0x, C0y - 8, rr, w, a0, a0 + TAU / 14 * 0.8, age < 0.3 ? pal[3] : pal[2]);
            }
          }
          if (t >= 1.5 && t < 1.6) star4(p, C1x, C1y - 24, 18, 2.5, pal[4]);
          for (const q of specks) drawPart(p, { ...q, c: A ? (q.s > 1 ? ORANGE : INDIGO[4]) : (q.s > 1 ? YG[4] : YG[2]) }, t);
        }
        // —— 稳定场（2.8 起）——
        const s = t - 2.8;
        if (s >= 0) {
          // 设施占位（原作 trap_107_smpow 外观未出，样张里只是一根石板灯柱）
          if (!U) {
            p.rect(DX - 3, DY - 14, 6, 14, SLATE[1]);
            p.rect(DX - 2, DY - 13, 2, 12, SLATE[2]);
            const lr = s < 1.0 ? 1.5 + 2 * s : 3.5;
            p.circle(DX, DY - 17, lr, s < 1.0 ? SLATE[3] : SLATE[5]);
            if (s < 1.0) for (let k = 0; k < 6; k++) { const a = k / 6 * TAU + s * 5, r = 26 * (1 - s); p.rect(Math.round(DX + Math.cos(a) * r), Math.round(DY - 17 + Math.sin(a) * r * 0.7), 2, 2, SLATE[4]); }
            if (s >= 1.0 && s < 1.08) star4(p, DX, DY - 17, 14, 2, SLATE[4]);
          }
          const fr = 85, fu = s - 1.0;
          if (fu >= 0) {
            if (A) {
              // 场边 28 根短桩依次立起（扫一圈 0.35 秒）+ 场内十字格点随波前亮起再收成小点
              if (!U) for (let k = 0; k < 28; k++) {
                const a = -Math.PI / 2 + k / 28 * TAU, at = k / 28 * 0.35;
                if (fu < at) continue;
                const c = fu - at < 0.07 ? SLATE[5] : SLATE[2];
                p.beam(DX + Math.cos(a) * (fr - 8), DY + Math.sin(a) * (fr - 8) * 0.8, DX + Math.cos(a) * fr, DY + Math.sin(a) * fr * 0.8, 3.5, c);
                p.rect(Math.round(DX + Math.cos(a) * fr) - 1, Math.round(DY + Math.sin(a) * fr * 0.8) - 1, 2, 2, SLATE[5]);
              }
              if (U) for (const g of lattice) {
                const at = g.d / fr * 0.5, a = fu - at;
                if (a < 0) continue;
                if (a < 0.45) { const c = a < 0.08 ? SLATE[5] : SLATE[2]; p.rect(g.x - 3, g.y, 7, 2, c); p.rect(g.x, g.y - 3, 2, 7, c); }
                else p.rect(g.x, g.y, 2, 2, SLATE[2]);
              }
            } else {
              // 6 根锚桩在场边升起，再用粗虚线一段段连起来；场里少量光点往上飘
              const anc = Array.from({ length: 6 }, (_, k) => { const a = -Math.PI / 2 + k / 6 * TAU; return [DX + Math.cos(a) * fr, DY + Math.sin(a) * fr * 0.8]; });
              if (U) for (let k = 0; k < 6; k++) {
                const lt = clamp((fu - 0.25 - k * 0.06) / 0.25);
                if (lt <= 0) continue;
                const [x0, y0] = anc[k], [x1, y1] = anc[(k + 1) % 6], L = Math.hypot(x1 - x0, y1 - y0);
                for (let d = 0; d < L * lt; d += 10) { const e = Math.min(d + 6, L * lt); p.beam(x0 + (x1 - x0) * d / L, y0 + (y1 - y0) * d / L, x0 + (x1 - x0) * e / L, y0 + (y1 - y0) * e / L, 2.5, SLATE[3]); }
              }
              if (!U) {
                for (let k = 0; k < 6; k++) {
                  const h = 12 * ease.outBack(clamp((fu - k * 0.04) / 0.2));
                  if (h <= 0) continue;
                  const [x, y] = anc[k];
                  p.rect(x - 2, y - h, 4, h, SLATE[1]);
                  p.rect(x - 1, y - h - 2, 2, 3, fu - k * 0.04 < 0.3 ? SLATE[5] : SLATE[4]);
                }
                for (const m of rising) {
                  const a = s - m.t0;
                  if (a < 0 || a > m.life) continue;
                  p.rect(Math.round(DX + Math.cos(m.a) * m.r), Math.round(DY + Math.sin(m.a) * m.r * 0.8 - a * 22), 2, 2, SLATE[5]);
                }
              }
            }
            if (!U && fu > 0.3) {   // 克雷松被场罩住：四角括号收紧（看得出「这下打得动了」）
              const k = ease.outCubic(clamp((fu - 0.3) / 0.25)), hw = 26 - 8 * k, hh = 34 - 8 * k, cx = C1x, cy = C1y - 26;
              for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
                const x = cx + sx * hw, y = cy + sy * hh;
                p.rect(Math.min(x, x - sx * 7), y - (sy < 0 ? 0 : 1), 7, 2, SLATE[4]);
                p.rect(x - (sx < 0 ? 0 : 1), Math.min(y, y - sy * 7), 2, 7, SLATE[4]);
              }
            }
          }
        }
      }

      // ================= 双王：征服 / 敕令 =================
      if (P === "kingsA" || P === "kingsB") {
        const A = P === "kingsA";
        // —— 征服（哈兰 → 圈画在路加脚下），0–3.6 ——
        {
          const q = clamp(t / 2.5), u = t - 2.5;
          if (t < 2.5) {
            if (A) {
              if (U) {
                for (const ro of rimOrder) {   // 圈边一段段压出来（粗、断口）
                  if (q < ro.at) continue;
                  const a0 = ro.k / 20 * TAU;
                  p.arc(LX, LY, RR, 4, a0, a0 + TAU / 20 * 0.72, RED[2]);
                }
                for (const cr of kCracks) drawJag(p, cr, ease.inQuad(q) * 0.9, 2.2, RED[0], q > 0.6 && t % 0.2 < 0.1 ? RED[4] : RED[3]);   // 裂纹从圈边往圆心爬
              }
            } else if (!U) {
              const sp = 1.5 * TAU * q * q;   // 三道鞭痕绕圈越抽越快
              for (let k = 0; k < 3; k++) {
                const a0 = sp + k / 3 * TAU;
                p.arc(LX, LY, RR, (uu) => 9 * Math.sin(Math.PI * uu), a0, a0 + 1.0, (uu) => (uu > 0.85 ? RED[5] : uu > 0.5 ? RED[3] : RED[1]));
              }
            }
            if (!U) {
              star4(p, KX, KY - 40, 6 + 10 * q + (t % 0.3 < 0.15 ? 2 : 0), 1.5 + q, RED[3], q > 0.7 ? WHITE : RED[5]);   // 哈兰身上红十字蓄力（原作 smkght_idle cross）
              for (const e of embersIn) {   // 红黑火星往哈兰身上收（lizi_in）
                const k = (e.ph + t * 0.9) % 1, r = e.r * (1 - k);
                p.rect(Math.round(KX + Math.cos(e.a) * r), Math.round(KY - 30 + Math.sin(e.a) * r * 0.8), 2, 2, e.c);
              }
            }
          } else if (u < 1.1) {
            if (A) {
              if (U && u < 0.9) for (const cr of kCracks) drawJag(p, cr, 0.9 * (1 - clamp((u - 0.4) / 0.5)), 2.5, RED[0], u < 0.15 ? RED[5] : RED[3]);
            } else if (!U && u < 0.12) for (let k = 0; k < 3; k++) {   // 鞭痕收进圆心
              const a0 = 1.5 * TAU + k / 3 * TAU, r = RR * (1 - u / 0.12);
              if (r > 6) p.arc(LX, LY, r, 6, a0, a0 + 0.9, RED[3]);
            }
            if (!U) {
              const ru = ease.outQuart(clamp(u / 0.4)), r = 8 + (RR + 6) * ru, w = Math.max(2, 9 * (1 - ru) + 2);
              if (u < 0.5) for (let i = 0; i < 18; i++) {   // 冲击环：粗、断口、红 → 黑
                if (i % 5 === 4) continue;
                const a0 = i / 18 * TAU;
                p.arc(LX, LY - 6, r, w, a0, a0 + TAU / 18 * 0.85, u < 0.1 ? RED[4] : u < 0.25 ? RED[3] : A ? RED[1] : RED[0]);
              }
              if (u < 0.08) star4(p, LX, LY - 14, 30, 4, RED[4]);
              if (u > 0.05 && u < 0.9) for (const sm of smokes) {   // 暗红烟团（实心、往外收缩）
                const k = clamp((u - 0.05) / 0.85), rr = sm.r * (1 - k);
                if (rr > 1) p.circle(LX + Math.cos(sm.a) * sm.d * (0.6 + 0.6 * k), LY + Math.sin(sm.a) * sm.d * 0.7 * (0.6 + 0.6 * k) - 10 * k, rr, k < 0.3 ? RED[2] : RED[1]);
              }
              for (const q2 of rocksK) drawPart(p, q2, t);
              if (u < 0.3) for (const sk of sparkOut) { const a = u; if (a > sk.life) continue; const d = sk.sp * a + 10; p.beam(LX + Math.cos(sk.a) * d, LY - 10 + Math.sin(sk.a) * d * 0.8, LX + Math.cos(sk.a) * (d + 12), LY - 10 + Math.sin(sk.a) * (d + 12) * 0.8, 2, u < 0.1 ? RED[5] : RED[3]); }
            }
          }
        }
        // —— 敕令（路加 → 圈画在哈兰脚下），3.6–7.2 ——
        {
          const s = t - 3.6, q = clamp(s / 2.5), u = s - 2.5, pal = A ? GOLD : PURP;
          if (s >= 0 && s < 2.5) {
            if (A) {
              if (U) for (let k = 0; k < 48; k++) {   // 历法刻度：顺时针一格格亮起，像一圈日晷
                if (q < k / 48) continue;
                const a = -Math.PI / 2 + k / 48 * TAU, long = k % 12 === 0, r0 = RR - (long ? 13 : 7);
                p.beam(KX + Math.cos(a) * r0, KY + Math.sin(a) * r0, KX + Math.cos(a) * (RR - 1), KY + Math.sin(a) * (RR - 1), long ? 3 : 2.5, long ? GOLD[4] : GOLD[3]);
              }
              if (!U) {
                const a = -Math.PI / 2 + q * TAU;   // 指针
                p.beam(KX, KY, KX + Math.cos(a) * (RR - 16), KY + Math.sin(a) * (RR - 16), 2.5, GOLD[2]);
                for (let k = 0; k < 4; k++) if (q >= k / 4) { const b = -Math.PI / 2 + k / 4 * TAU; star4(p, KX + Math.cos(b) * RR, KY + Math.sin(b) * RR, 5 + (s % 0.4 < 0.2 ? 1 : 0), 1, GOLD[4], GOLD[5]); }
              }
            } else if (!U) {
              for (let k = 0; k < 16; k++) {   // 16 支箭依次出现在圈外、指向圆心（原作 smlion_skill_01 arrow），最后一齐扎下去
                if (q < k / 16 * 0.85) continue;
                const a = k / 16 * TAU - Math.PI / 2, plunge = clamp((s - 2.3) / 0.2), bob = Math.sin(s * 6 + k) * 1.5;
                const r = (RR + 14 + bob) * (1 - 0.8 * ease.inQuad(plunge));
                const hx = KX + Math.cos(a) * r, hy = KY + Math.sin(a) * r * 0.85, tx = KX + Math.cos(a) * (r + 20), ty = KY + Math.sin(a) * (r + 20) * 0.85;
                p.beam(tx, ty, hx, hy, 2.6, PURP[2]);
                const nx = -Math.sin(a), ny = Math.cos(a);
                p.tri(hx - Math.cos(a) * 8, hy - Math.sin(a) * 8 * 0.85, hx + nx * 5 + Math.cos(a) * 1, hy + ny * 5, hx - nx * 5 + Math.cos(a) * 1, hy - ny * 5, PURP[4]);
              }
            }
            if (!U) {
              star4(p, LX, LY - 44, 6 + 10 * q + (s % 0.3 < 0.15 ? 2 : 0), 1.5 + q, pal[3], q > 0.7 ? WHITE : pal[5]);   // 路加身上十字星蓄力（cross_star_01）
              for (let k = 0; k < 18; k++) { const kk = (k / 18 + s * 0.7) % 1, a = k * 2.4, r = 50 * (1 - kk); p.rect(Math.round(LX + Math.cos(a) * r), Math.round(LY - 34 + Math.sin(a) * r * 0.8), 2, 2, k % 2 ? pal[4] : pal[2]); }   // 沙光往身上收（sand_01）
            }
          } else if (s >= 2.5 && u < 1.2 && !U) {
            const ru = ease.outQuart(clamp(u / 0.4)), r = 8 + (RR + 6) * ru, w = Math.max(2, 9 * (1 - ru) + 2);
            if (u < 0.5) for (let i = 0; i < 18; i++) {
              if (i % 6 === 5) continue;
              const a0 = i / 18 * TAU + 0.1;
              p.arc(KX, KY - 6, r, w, a0, a0 + TAU / 18 * 0.85, u < 0.1 ? pal[5] : u < 0.25 ? pal[4] : pal[2]);
            }
            if (u < 0.08) star4(p, KX, KY - 14, 30, 4, pal[4]);
            for (const cs of crossStars) {   // 圈里十字星一颗颗迸开（cross_star_01）
              const a = u - cs.t0;
              if (a < 0 || a > 0.3) continue;
              star4(p, KX + Math.cos(cs.a) * cs.d, KY + Math.sin(cs.a) * cs.d * 0.85, cs.L * (a < 0.1 ? 1 : 1 - (a - 0.1) / 0.2), 1, pal[4], pal[5]);
            }
            for (const q2 of rocksL) drawPart(p, q2, t);
            if (u < 0.3) for (const sk of sparkOut) { const d = sk.sp * u + 10; if (u > sk.life) continue; p.beam(KX + Math.cos(sk.a) * d, KY - 10 + Math.sin(sk.a) * d * 0.8, KX + Math.cos(sk.a) * (d + 12), KY - 10 + Math.sin(sk.a) * (d + 12) * 0.8, 2, u < 0.1 ? pal[5] : pal[3]); }
          }
        }
      }
    },
  };
}
