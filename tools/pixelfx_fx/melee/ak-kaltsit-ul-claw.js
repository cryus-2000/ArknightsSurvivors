// 凯尔希 · Mon3tr 爪击（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：俯视，原点 = Mon3tr 判定原点，正右为出爪方向，游戏里按方向旋转。
// 原作参照（只作参照，build/ark_ref/mon3tr，还原见 Claude outputs/pixelfx_ul_kaltsit/ref/）：
//   普攻 monstr_attack_hit_02：几道细长、弯的黄绿爪痕（trail_127_4，#fffa61 → #82ff7d）+ 命中处绿光 + 十字小标（M3_03）飘散；
//   S3 熔毁 monstr_skill_03_start_01 + skill_03_hit：四道粗的白芯红边大爪弧扫过 + 红黑拖尾，命中处红色四角星 + 横向红闪 + 红碎片。
// move：basic（普攻，克制：细爪三道）/ s3（熔毁期间，四道白芯红爪 + 命中星）。
// 精英档（docs/242 §10 / docs/91 §6）：E0 三道细爪；E1 加命中处的十字小标飘升（原作 icon）+ 爪尾余痕（对应精一「指挥」伤害与爪击范围提升）；
//   E2 爪痕变成骨白芯 + 黄边、多第四道、甩出骨屑（对应精二前后爪 / 骨刃）。熔毁只在精二，只出 E2。
// 爪痕彼此不等长、不等距、弧心各偏，避免等距并排（§9.3）；不画孤立圆，光晕沿爪痕走（glowLine）。
import { Particles, Lights, Bits, B, P, Rng, fit, clamp, smooth, ease, noise, hex, TAU } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 #12）：OP.kaltsit 黄绿、OP.kaltsit_melt 熔毁红

// 实色：painter.put 在 a < 1 时按 Bayer 点阵抖动（棋盘格脏点，§12 画面不能脏）；本作一律 a ≥ 0.5 画实、< 0.5 不画，淡出靠色阶变暗
function solid(p) {
  if (p._solid) return;
  const f = p.put.bind(p);
  p.put = (sx, sy, c, a = 1) => { if (a < 0.999) { if (a < 0.5) return; a = 1; } f(sx, sy, c, a); };
  p._solid = 1;
}

export const meta = {
  name: "Kal'tsit Mon3tr claw unleashed",
  desc: "Mon3tr's claw seen from above: thin curved lime claw marks rake across the cone with a soft green flare and little medical crosses drifting up; during Meltdown four heavy white-cored red claws tear through and a red star bursts on the target.",
  tags: ["melee", "claw", "slash", "summon", "topdown", "one-shot"],
  size: [180, 180],
  origin: [60, 90],
  duration: 0.75,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: OP.kaltsit,
    red: OP.kaltsit_melt,   // 熔毁红（组长 C 11-04 审定：白芯 + 压暗绯红，色相 2–8°）
    bone: "#f3efd8",    // E2 骨白芯
    radius: 54,         // 判定半径（1x 像素）：由 targets judge 传 (m_reach + pad) / 2
    half: 1.3,          // 判定半角（弧度）：judge 传 m_arc
    move: "basic",      // basic / s3
    elite: 2,
    quick: 0,           // 1 = 队友版余韵减半（Mon3tr 跟召唤者，仍按队长 / 队友区分）
    spray: 0,           // 往外甩的火星 / 骨屑（1 = 甩；11-04 用户：往外甩的一律去掉，§14.7）
    layer: "all",
    seed: 4,
  },
};

// 一道爪痕：以 (cx, cy) 为弧心、半径 r 的弧，从 a0 扫 len（带符号）弧度；两头尖、中间宽 w；head / tail = 已扫出 / 已收尾的比例
function claw(p, k, s, head, tail, hot, age) {
  if (head - tail < 0.02) return;
  const C = s.C, n = C.length, L = Math.abs(s.len), dir = Math.sign(s.len), B0 = s.r + s.w + 3;
  p.shade(s.cx - B0, s.cy - B0, s.cx + B0, s.cy + B0, (x, y, out) => {
    if (Math.hypot(x, y) > k + 0.5) return;   // 核心不出判定半径
    const dx = x - s.cx, dy = y - s.cy, r = Math.hypot(dx, dy);
    let u = (dir * (Math.atan2(dy, dx) - s.a0)) % TAU;
    if (u < 0) u += TAU;
    u /= L;
    if (u < tail || u > head || u > 1) return;
    const v = (u - tail) / Math.max(0.05, head - tail);   // 0 = 尾、1 = 头：头尖、尾细
    let w = s.w * Math.pow(Math.sin(Math.PI * clamp(u)), 0.7) * (0.45 + 0.55 * v);
    if (s.saw) w *= 0.6 + 0.55 * Math.abs(Math.sin(u * (9 + (s.seed % 4)) * Math.PI + noise(u * 5, s.seed) * 1.5));   // E2 骨刃：锯齿外缘（不等距）
    const jag = 0.8 * noise(u * 9 + s.seed, s.seed);
    const d = Math.abs(r - s.r - jag);
    if (d > w * 0.5 + 0.35) return;
    const q = d / Math.max(0.5, w * 0.5);   // 0 = 爪痕中线
    if (s.melt) {   // 熔毁弧（组长 C v2）：弧身 #84120e / #b01c16，#d8443a 只做 1 格外缘，白芯只在弧长中间 1/3；首帧中段白热
      const mid = u > 0.33 && u < 0.66, M = s.M;
      if (q > 0.72 || d > w * 0.5 - 0.6) { out.c = age > 0.6 ? M[3] : M[4]; return; }
      if (mid && q < 0.42 && (hot > 1 || age < 0.45)) { out.c = hot > 1 || age < 0.2 ? M[6] : M[5]; return; }
      out.c = (q < 0.45 ? M[3] : M[2]);
      if (age > 0.6) out.c = q < 0.45 ? M[2] : M[1];
      return;
    }
    if (hot > 1) { out.c = C[n - 1]; return; }   // 首帧白热
    if (s.core && q < 0.45 && age < 0.55) { out.c = s.core; return; }   // E2 骨白芯 / 熔毁白芯
    const ci = Math.round((n - 2) - q * 2.2 - age * 3.2 - (1 - v) * 1.2 + hot);
    out.c = C[clamp(ci, 2, n - 1)];
    out.a = q > 0.8 ? 0.75 : 1;
  });
}

export function create(o) {
  const el = clamp(Math.round(+o.elite), 0, 2), s3 = o.move === "s3", quick = +o.quick > 0;
  const G = fit(o.palette, 8), RD = fit(o.red, 8), C = s3 ? RD : G, Rg = new Rng(o.seed), R0 = o.radius, H = o.half;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const DL = (s3 ? 1 : [0.45, 0.7, 1][el]) * (quick ? 0.5 : 1);   // 装饰余韵系数（E0 约 0.25 s、E1 约 0.4 s、E2 0.5–0.7 s）
  const GK = s3 ? 0.5 : [0.35, 0.6, 0.9][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  const bits = new Bits({ ground: () => 1e9 });

  // ---- 爪痕：普攻 3 道（E2 4 道）细爪；熔毁 4 道粗爪。弧心在 Mon3tr 身后偏一点，半径落在判定半径内（核心不出判定）
  const n = s3 ? 4 : el >= 2 ? 4 : 3;
  const sg = Rg.chance(0.5) ? 1 : -1;   // 从左往右 / 从右往左扫
  const marks = [];
  // 11-04 用户：爪痕顺着出爪方向划（Mon3tr 扑向哪边就朝哪边划）。每道爪 = 一段略弯的弧，从身前往外划到判定边缘附近：
  //   中点 M、走向 β（普攻 ≈ 正前、各道微张成耙；熔毁两组 ±0.3 rad 交叉）、弯曲半径 rc（大 = 直），侧向位置不等距
  const lat = [], NL = n;
  for (let i = 0; i < NL; i++) lat.push((i - (NL - 1) / 2) / Math.max(1, NL - 1));
  const circ3 = (ax, ay, bx, by, cx, cy) => {   // 过三点的圆：圆心与半径
    const d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
    const ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d;
    const uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d;
    return [ux, uy, Math.hypot(ax - ux, ay - uy)];
  };
  // 熔毁（组长 C v2）：3 道错开的长弧，从 Mon3tr 身侧起、弯着扫过身前目标，弧长 ≥ 判定半径 × 1.5；前两道同向平行，只有最后一道反向交叉
  if (s3) for (let i = 0; i < 3; i++) {
    const rev = i === 2, sv = rev ? -sg : sg, sh = i === 1 ? -0.16 : i === 0 ? 0.0 : 0.05;
    const A = [R0 * (-0.05 + 0.08 * i), sv * R0 * (0.74 + sh)], B = [R0 * (0.9 - 0.04 * i), -sv * R0 * (0.4 - sh * 0.5)];
    const Mx = R0 * (0.62 + Rg.range(-0.03, 0.03)), My = sv * R0 * (0.22 + sh) + Rg.range(-1, 1);
    const [cx, cy, rc] = circ3(A[0], A[1], Mx, My, B[0], B[1]);
    const a0 = Math.atan2(A[1] - cy, A[0] - cx), aM = Math.atan2(My - cy, Mx - cx), a1 = Math.atan2(B[1] - cy, B[0] - cx);
    let sp = a1 - a0; while (sp > Math.PI) sp -= TAU; while (sp < -Math.PI) sp += TAU;
    let sm = aM - a0; while (sm > Math.PI) sm -= TAU; while (sm < -Math.PI) sm += TAU;
    if (Math.sign(sm) !== Math.sign(sp)) sp = sp - Math.sign(sp) * TAU;
    marks.push({ seed: o.seed * 7 + i * 13, cx, cy, r: rc, a0, len: sp, w: Rg.range(3.6, 4.4) * (i === 0 ? 1.15 : 1), C, melt: true, M: o.red.map(hex), t0: [0, 0.035, 0.1][i] + Rg.range(0, 0.01) });
  }
  for (let i = 0; i < (s3 ? 0 : n); i++) {
    const rev = s3 ? i % 2 === 1 : el >= 2 && i === n - 1;
    // 熔毁（组长 C 11-04：3–4 道长弧扫过，跨度至少判定半径）：每道从 Mon3tr 身前划到判定边缘，明显弯；两道一组正反交叉，交点落在命中处
    const yl = s3 ? R0 * [-0.3, 0.16, 0.32, -0.12][i] * sg + R0 * Rg.range(-0.04, 0.04) : R0 * Math.sin(H) * 0.82 * (lat[i] + Rg.range(-0.1, 0.1)) * sg;
    const L = R0 * (s3 ? Rg.range(1.0, 1.15) : Rg.range(0.6, 0.74)) * (rev && !s3 ? 0.8 : 1);
    const xm = R0 * (s3 ? [0.56, 0.6, 0.62, 0.58][i] + Rg.range(-0.03, 0.03) : Rg.range(0.52, 0.6));
    const beta = s3 ? (rev ? -0.6 : 0.6) * sg + Rg.range(-0.06, 0.06) : Math.atan2(yl, R0) * 0.55 + (rev ? -0.5 * sg : 0) + Rg.range(-0.05, 0.05);
    const rc = R0 * (s3 ? Rg.range(0.9, 1.2) : Rg.range(1.2, 2.2)), side = s3 ? (rev ? -1 : 1) * sg : (Rg.chance(0.5) ? 1 : -1);
    const nx = -Math.sin(beta) * side, ny = Math.cos(beta) * side;
    const cx = xm + nx * rc, cy = yl + ny * rc, thm = Math.atan2(yl - cy, xm - cx);
    const ds = (-Math.sin(thm) * Math.cos(beta) + Math.cos(thm) * Math.sin(beta)) > 0 ? 1 : -1, span = L / rc;
    marks.push({
      seed: o.seed * 7 + i * 13, cx, cy, r: rc, a0: thm - ds * span / 2, len: ds * span,
      w: s3 ? Rg.range(3.2, 4.2) * (i === 0 ? 1.2 : 1) : [Rg.range(1.8, 2.4), Rg.range(2.0, 2.6), Rg.range(3.0, 3.8)][el],
      C, core: s3 ? C[7] : el >= 2 ? hex(o.bone) : 0, saw: !s3 && el >= 2,
      t0: (s3 ? [0, 0.02, 0.07, 0.09][i] : i * 0.018) + Rg.range(0, 0.01),
    });
  }
  const SW = s3 ? 0.07 : 0.055, HOLD = s3 ? 0.06 : 0.03, FADE = s3 ? 0.22 : [0.12, 0.16, 0.2][el];
  const T_HIT = s3 ? 0.11 : SW * 0.8;   // 命中时刻（爪尖到判定外缘附近；熔毁等第三道交叉划到）
  const hx = R0 * (s3 ? 0.6 : 0.72), hy = 0;   // 命中处（判定扇区中段，正前方）

  // ---- 甩出物（装饰）：沿出爪切向甩出的火星 / 碎屑；E2 骨屑；熔毁红碎片 + 横向红闪
  if (deco && +o.spray > 0) {
    const nsp = Math.round((s3 ? 16 : [5, 8, 11][el]));
    for (let i = 0; i < nsp; i++) {
      const m = marks[Rg.int(0, n - 1)], u = Rg.range(0.35, 0.95), a = m.a0 + m.len * u, tang = a + Math.sign(m.len) * Math.PI / 2;
      const x = m.cx + Math.cos(a) * m.r, y = m.cy + Math.sin(a) * m.r, sp = Rg.range(60, s3 ? 260 : 170), da = tang + Rg.range(-0.5, 0.5);
      ps.spawn(P.SPARK, x, y, Math.cos(da) * sp, Math.sin(da) * sp, Rg.range(0.12, s3 ? 0.4 : 0.3) * DL + 0.05, 0, 1, m.t0 + SW * u);
    }
    if (el >= 2 || s3) for (let i = 0; i < (s3 ? 9 : 5); i++) {
      const a = Rg.range(-H * 0.6, H * 0.6), sp = Rg.range(80, s3 ? 220 : 150);
      bits.add({ kind: B.SHARD, x: hx * Rg.range(0.8, 1.05), y: Math.sin(a) * R0 * 0.3, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, a: Rg.range(0, 6.28), va: Rg.range(-18, 18),
        s: Rg.range(1.5, s3 ? 3.4 : 2.4), c: s3 ? C[5] : hex(o.bone), ramp: (s3 ? o.red : o.palette).slice(2, 7), g: 0, drag: 2.4, bounce: 0, life: Rg.range(0.3, 0.55) * DL + 0.1 });
    }
  }
  // ---- 十字小标（E1 起；原作 icon_2 M3_03 医疗十字）：命中处飘升、不等距散布，归装饰层
  const crosses = [];
  if (!s3 && el >= 1) for (let i = 0; i < (el >= 2 ? 5 : 4); i++)
    crosses.push({ x: hx + Rg.range(-R0 * 0.22, R0 * 0.18), y: Rg.range(-R0 * 0.3, R0 * 0.3), vy: -Rg.range(14, 30), vx: Rg.range(-6, 6), t0: T_HIT + Rg.range(0.02, 0.12), life: Rg.range(0.3, 0.5) * DL + 0.18, big: i < 2 || Rg.chance(0.3) });
  // ---- 熔毁命中星（核心：四角星主形；装饰：横向红闪 + 光）
  const starA = Rg.range(-0.25, 0.25);

  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); bits.update(dt); lights.update(dt); },
    drawBack(p) { if (deco) ps.draw(p, "back"); },
    draw(p) {
      solid(p);
      // 装饰：沿爪痕的光（不画圆形光团）
      if (deco) for (const m of marks) {
        const u = t - m.t0;
        if (u < 0) continue;
        const k = (1 - smooth(SW, SW + HOLD + FADE * (s3 ? 1.1 : 2.2) * DL + 0.05, u)) * GK;
        if (k <= 0.01) continue;
        const head = ease.outExpo(clamp(u / SW));
        for (let f = 0.05; f < head; f += 0.14) {
          const a1 = m.a0 + m.len * f, a2 = m.a0 + m.len * Math.min(head, f + 0.22);
          if (Math.hypot(m.cx + Math.cos(a1) * m.r, m.cy + Math.sin(a1) * m.r) > R0 || Math.hypot(m.cx + Math.cos(a2) * m.r, m.cy + Math.sin(a2) * m.r) > R0) continue;   // 光只跟可见的爪痕走，不在判定外留孤立光团
          p.glowLine(m.cx + Math.cos(a1) * m.r, m.cy + Math.sin(a1) * m.r, m.cx + Math.cos(a2) * m.r, m.cy + Math.sin(a2) * m.r, (s3 ? 9 : 5) + m.w, C[s3 ? 5 : 5], (s3 ? 0.32 : 0.2) * k);
        }
      }
      // 核心：爪痕
      if (core) for (const m of marks) {
        const u = t - m.t0;
        if (u < 0) continue;
        const head = ease.outExpo(clamp(u / SW)), tail = smooth(SW + HOLD, SW + HOLD + FADE, u);
        const hot = u < 1 / 24 + 0.005 ? 3 : u < (s3 ? 0.07 : 0.09) ? 0.6 : 0;
        if (tail < 1) claw(p, R0, m, head, tail, hot, clamp(u / (SW + HOLD + FADE)));
        // E1 起：爪尾余痕（暗一档、细，晚一点收）
        if (!s3 && el >= 1) {
          const t2 = smooth(SW + HOLD, SW + HOLD + FADE + 0.12 * DL + 0.04, u);
          if (t2 < 1 && u > SW) claw(p, R0, { ...m, w: m.w * 0.45, r: m.r - m.w * 0.9, core: 0, C: G.slice(0, 6) }, Math.min(head, 0.92), Math.max(t2, 0.08), 0, 0.5 + 0.5 * t2);
        }
      }
      // 熔毁命中星
      if (s3) {
        const u = t - T_HIT;
        if (u >= 0 && u < 0.3) {
          const k = 1 - u / 0.3, L = 8 * (0.7 + 0.5 * ease.outQuart(clamp(u / 0.08)));
          if (core) for (let j = 0; j < 4; j++) {   // 四角星（不等长两轴）
            const a = starA + j * Math.PI / 2, Lj = L * (j % 2 ? 0.62 : 1);
            const ex = hx + Math.cos(a) * Lj, ey = Math.sin(a) * Lj;
            p.poly([[hx + Math.cos(a + 1.3) * 2, Math.sin(a + 1.3) * 2], [ex, ey], [hx + Math.cos(a - 1.3) * 2, Math.sin(a - 1.3) * 2]], u < 0.05 ? RD[7] : u < 0.12 ? RD[5] : RD[4], 1);
          }
          // 组长 C v2：去掉中心红光团与横闪（孤立 / 半透明糊团）
        }
      }
      if (deco) {
        bits.draw(p);
        ps.draw(p, "front");
        for (const c of crosses) {   // 十字小标：3×3 / 5×5 像素十字，飘升淡出
          const u = t - c.t0;
          if (u < 0 || u > c.life) continue;
          const x = c.x + c.vx * u, y = c.y + c.vy * u, a = 1 - u / c.life, col = u < 0.05 ? G[7] : G[clamp(Math.round(7 - u * 5), 5, 7)];
          const m = c.big ? 2 : 1.5;
          p.rect(x - m, y, m * 2 + 1, 1, col, a);
          p.rect(x, y - m, 1, m * 2 + 1, col, a);
        }
        lights.draw(p);
      }
    },
  };
}
