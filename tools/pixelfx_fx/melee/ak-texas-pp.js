// 德克萨斯「转平面」（docs/257，开关 fx/px_plane，照 docs/246 斯卡蒂 / docs/254 星熊的做法）：pixelfx 画法，按本作俯视斜角重画。
// 一个文件按 part 出各件；每件分两层（layer）：
//   up 立起层 —— 离地的东西（腰高拔刀刀痕、骤雨旋斩、落下 / 插地的源石剑、钉剑、飞剑剑气、号令光柱、连携十字斩），原点 = 脚底地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（刀痕投影、落剑冲击与焦痕、剑阵刃光、地面环），已按 SY（0.72）压扁，画在地面层。
// 1 像素 = 1 美术像素 = 2 世界像素，游戏里只按 2 倍整数放大、不旋转；方向件按 dir（−90 / −45 / 0 / 45 / 90°）逐向生成，另一半水平翻转。
// view: "raw" 出「旧做法」对照：正俯视 / 正圆、光晕烤进颜色，游戏里旋转 + 小数缩放贴。
// 色：源石剑琥珀橙一组 8 阶（原作普攻 / 剑雨的橙色刃光与三角碎晶）；剑柄钢灰；精二点缀冷青刃光 #9fe3ff（插地后沿刃走的那道光）。不用危险红。
import { fit, clamp, smooth, ease, noise, TAU, hex, WHITE } from "../../core/index.js";

export const meta = {
  name: "Texas plane",
  desc: "Texas's iai sweeps, storm spins, falling originium swords, pinned swords, flying sword qi, charge-order pillar, sword-rain ring and link cross-cut redrawn for a 3/4 top-down plane.",
  tags: ["melee", "slash", "topdown", "texas", "one-shot"],
  size: [300, 260],
  origin: [150, 170],
  duration: 1.0,
  loop: false,
  fps: 15,   // 统一动画时钟：本作特效帧条一律 15 fps
  bg: "dark",
  options: {
    palette: ["#120804", "#2c1406", "#5a2808", "#9c4610", "#e2781c", "#ffac3c", "#ffdc9c", "#ffffff"],
    steel: ["#16161c", "#2a2a34", "#44444f", "#6c6c7a", "#a4a4b4", "#dcdce6"],
    dust: ["#18140f", "#2c261d", "#463d2f", "#6a5e4a", "#90826a"],
    accent: "#9fe3ff",
    part: "slash",
    layer: "up",
    view: "plane",
    R: 56, span: 2.4, dir: 0, H0: 12, W: 9, L: 18, el: 0, SY: 0.72, dur: 0.3, seed: 3, fall: 40, stick: 0.35, lean: 0, h: 9, S: 1, flip: 0,
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1

// ---------------------------------------------------------------- 拔刀（普攻，锥形 slash_r 112 / 半角 1.2 → 半径 56、弧 2.4）：腰高水平刀痕，两头针尖（居合），第 0 拍已扫满八成
function iaiT(t, span) {
  const a0 = -span / 2;
  const head = a0 + span * (0.82 + 0.18 * clamp(t / 0.067));
  const tail = a0 + span * 0.3 * smooth(0.07, 0.27, t);
  return [a0, head, tail];
}

function slash(p, t, o, C, ACC, ST) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : +o.H0, th = +o.dir * D2R, el = +o.el, n = C.length;
  const span = +o.span, [a0, head, tail] = iaiT(t, span);
  const hot = t < 0.067, cool = smooth(0.07, +o.dur, t);
  if (head - tail < 0.05 || cool >= 0.62) return;   // 收到只剩细线之前整道消失（不留 1 格碎点）
  const R = +o.R, Wr = +o.W * (1 - 0.6 * cool), B = R + 3;
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 1.5 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x) - th;
    a = ((a - a0) % TAU + TAU) % TAU + a0;
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);
    // 两头针尖、最厚处偏刀头（u ≈ 0.62）
    const prof = u < 0.62 ? Math.pow(u / 0.62, 0.75) : Math.pow((1 - u) / 0.38, 0.55);
    const wr = Wr * prof;
    if (wr < 1.6) return;
    const q = (R + 0.6 * nz(a * 17, o.seed + 3) - r) / wr;
    if (q < 0 || q > 1) return;
    let ci;
    const rim = el >= 1 ? 0.27 : 0.14;                 // 精一起白刃线加厚一倍（1 倍下也看得出刀变「亮」了）
    if (q < rim) ci = hot ? n - 1 : (el >= 1 ? n - 2 : n - 3);   // 外缘刃线：精零出手后是亮琥珀，精一起才是一道粗白刃（档差一眼可见）
    else if (q < 0.4) ci = n - 3;
    else if (q < 0.68) ci = n - 4;
    else if (q < 0.88) ci = n - 5;
    else { ci = n - 6; out.a = 0.6; }
    if (q > 0.2 && q < 0.88 && nz(r * 1.1 + o.seed, o.seed + 91) > 0.72) ci += 1;   // 速度纹
    if (hot && u > 0.8 && q < 0.35) ci = n - 1;
    ci = clamp(ci - Math.round(cool * 2.6), 1, n - 1);
    out.c = C[ci];
    if (out.a === undefined) out.a = cool > 0.6 ? 0.6 : 1;
    if (el >= 2 && !hot && q > rim && q < rim + 0.14 && cool < 0.5) out.c = ACC;   // 精二：白刃内侧一道冷青刃光
  });
  if (raw) {
    for (let a = tail; a <= head; a += 0.12) p.light(Math.cos(a + th) * R * 0.9, Math.sin(a + th) * R * 0.9, C[n - 2], 0.35 * (1 - cool));
    return;
  }
  // 出手第一拍：刀尖一道径向刃光（拔刀那一下）
  if (hot) {
    const ha = head + th;
    for (let d = R * 0.82; d <= R + 5; d += 0.5) {   // 只在刀尖附近（不往圆心拉出一根细棍）
      const x = Math.cos(ha) * d, y = Math.sin(ha) * d * SY - H0;
      p.px(Math.round(x), Math.round(y), d > R * 0.9 && d < R + 3 ? WHITE : C[n - 2]);
    }
  }
  // 精一起：刀头甩出源石碎晶（2 格小三角，受重力）；精二多、混冷青
  if (el >= 1 && t > 0.02 && t < 0.3) {
    const ha = head + th, tx = -Math.sin(ha), ty = Math.cos(ha) * SY, hx = Math.cos(ha) * R, hy = Math.sin(ha) * R * SY - H0;
    const N = el >= 2 ? 12 : 10, u = t - 0.02;
    for (let i = 0; i < N; i++) {
      const sp = 80 + 110 * nz(i * 3.1, o.seed + 201), da = (nz(i * 1.7, o.seed + 203) - 0.5) * 1.4;
      const dx = tx * Math.cos(da) - ty * Math.sin(da), dy = tx * Math.sin(da) + ty * Math.cos(da);
      const x = hx + dx * sp * u + Math.cos(ha) * sp * 0.25 * u, y = hy + dy * sp * u - 30 * u + 300 * u * u;
      const X = Math.round(x), Y = Math.round(y);
      const cold = el >= 2 && i % 3 === 0;
      const c = cold ? (u < 0.12 ? WHITE : ACC) : (u < 0.1 ? C[n - 2] : u < 0.2 ? C[n - 3] : C[n - 4]);
      p.px(X, Y, c); p.px(X + 1, Y, c); p.px(X + 2, Y, c); p.px(X, Y - 1, u < 0.2 ? C[n - 3] : C[n - 5]); p.px(X + 1, Y - 1, u < 0.2 ? C[n - 3] : C[n - 5]); p.px(X, Y - 2, C[n - 5]);   // 3 格三角碎晶
    }
  }
}

function slashGround(p, t, o, C, DU) {
  if (o.view === "raw") return;
  const R = +o.R, W = +o.W, SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, span = +o.span;
  // 精一起：刀尖扫过的地面留一道焦痕弧（刚斩时亮琥珀 → 暗琥珀 → 焦黑，0.25 秒后一节节断开，0.5 秒散完）——刀痕本身的精一变化，不靠钉剑
  if (el >= 1) {
    const brk = smooth(0.22, 0.5, t), a0b = -span / 2, a1b = a0b + span * (0.82 + 0.18 * clamp(t / 0.067));
    if (brk < 0.99) for (let a = a0b + span * 0.06; a <= a1b - span * 0.03; a += 0.5 / R) {
      if (nz(a * 23, o.seed + 41) < brk) continue;
      const rr = R * 0.96 + 0.8 * nz(a * 9, o.seed + 43), X = Math.round(Math.cos(a + th) * rr), Y = Math.round(Math.sin(a + th) * rr * SY);
      const c = t < 0.1 ? C[n - 2] : t < 0.2 ? C[n - 3] : t < 0.32 ? C[n - 5] : DU[1];
      p.px(X, Y, c);
      if (el >= 2 && t < 0.2) p.px(X, Y + 1, C[n - 4]);
      else p.px(X, Y + 1, DU[0]);
    }
  }
  const [a0, head, tail] = iaiT(t, span);
  const cool = smooth(0.07, +o.dur, t);
  if (head - tail < 0.05 || cool >= 0.62) return;
  for (let a = tail; a <= head; a += 0.4 / R) {
    const u = (a - tail) / Math.max(0.001, head - tail);
    const prof = u < 0.62 ? Math.pow(u / 0.62, 0.75) : Math.pow((1 - u) / 0.38, 0.55);
    for (let d = 0; d < W * 0.5 * prof; d += 1) p.dot(Math.round(Math.cos(a + th) * (R - d)), Math.round(Math.sin(a + th) * (R - d) * SY), C[0], 0.45 * (1 - cool));
  }
}

// ---------------------------------------------------------------- 骤雨（每第 4 次出手 360° 连斩 4 下，storm_r 100 → 半径 50）/ 回马剑（112 → 56）：一整道约 300° 的连续月牙，粗细起伏，不画整圈
function spin(p, t, o, C, ACC) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : +o.H0, el = +o.el, n = C.length, R = +o.R;
  const SPAN = 5.25, a0 = -2.2 + (+o.seed % 5) * 0.4;
  const head = a0 + SPAN * (0.62 + 0.38 * clamp(t / 0.067)), tail = a0 + SPAN * 0.25 * smooth(0.07, 0.3, t);
  const hot = t < 0.067, cool = smooth(0.07, +o.dur, t);
  if (cool >= 0.62) return;   // 同拔刀：整道一起收掉，不留细环碎点
  const Wr = +o.W * (1 - 0.6 * cool), B = R + 3;
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 1.5 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x);
    a = ((a - a0) % TAU + TAU) % TAU + a0;
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);
    const prof = Math.min(1, u / 0.15) * Math.min(1, (1 - u) / 0.1) * (0.75 + 0.25 * Math.sin(u * 9 + o.seed));   // 粗细起伏、两头收
    const wr = Wr * prof;
    if (wr < 1.6) return;
    const q = (R - r) / wr;
    if (q < 0 || q > 1) return;
    const rim = el >= 1 ? 0.27 : 0.14;   // 同拔刀：精零亮琥珀细刃，精一起粗白刃
    let ci = q < rim ? (hot ? n - 1 : (el >= 1 ? n - 2 : n - 3)) : q < 0.42 ? n - 3 : q < 0.72 ? n - 4 : n - 5;
    if (q > 0.88) out.a = 0.6;
    if (hot && u > 0.86 && q < 0.4) ci = n - 1;
    if (pz < 0) ci -= 1;   // 远侧（身后那半圈）暗一阶
    ci = clamp(ci - Math.round(cool * 2.6), 1, n - 1);
    out.c = C[ci];
    if (out.a === undefined) out.a = cool > 0.6 ? 0.6 : 1;
    if (el >= 2 && !hot && q > rim && q < rim + 0.14 && cool < 0.5) out.c = ACC;
  });
  if (raw) for (let a = tail; a <= head; a += 0.2) p.light(Math.cos(a) * R * 0.9, Math.sin(a) * R * 0.9, C[n - 2], 0.3 * (1 - cool));
}

function spinGround(p, t, o, C) {
  if (o.view === "raw") return;
  const R = +o.R, SY = +o.SY, cool = smooth(0.07, +o.dur, t);
  if (cool >= 0.62) return;
  const SPAN = 5.25, a0 = -2.2 + (+o.seed % 5) * 0.4;
  const head = a0 + SPAN * (0.62 + 0.38 * clamp(t / 0.067)), tail = a0 + SPAN * 0.25 * smooth(0.07, 0.3, t);
  for (let a = tail; a <= head; a += 0.5 / R) for (let d = 0; d < +o.W * 0.4; d += 1) p.dot(Math.round(Math.cos(a) * (R - d)), Math.round(Math.sin(a) * (R - d) * SY), C[0], 0.4 * (1 - cool));
}

// ---------------------------------------------------------------- 源石剑（剑雨 / 余像 / 剑阵 / 次元斩落剑）：从天而降，插进地面，刃光沿刃走一趟，最后碎成碎晶
// 剑尖朝下；剑身琥珀结晶（左侧受光、中线白芯），护手 / 剑柄钢灰。lean = 每格高度的横向斜率（另一边游戏里翻转）
function bladeCell(C, ST, n, w, hw, k, edgeHot) {
  const s = hw > 0 ? w / hw : 0;   // -1 左 .. 1 右
  if (Math.abs(w) < 0.6) return edgeHot ? WHITE : C[n - 2];           // 中线白芯
  if (s < -0.2) return k > 0.85 ? C[n - 3] : C[n - 3];
  if (s < 0.5) return C[n - 4];
  return C[n - 5];
}

function drawSword(p, gx, gy, z, L, W, lean, C, ST, ACC, el, hotT, glint) {
  const n = C.length, hw = W / 2;
  // 剑身：剑尖（z）→ 护手（z + L）
  for (let k = 0; k <= L; k += 0.5) {
    const u = k / L, half = hw * Math.min(1, (u + 0.02) / 0.22) * (u > 0.96 ? 0.85 : 1);   // 剑尖收尖
    const cx = gx + lean * k;
    for (let w = -half; w <= half; w += 0.5) {
      let c = bladeCell(C, ST, n, w, half, u, hotT);
      if (hotT && Math.abs(w) < half * 0.7) c = u < 0.6 ? WHITE : C[n - 2];
      if (glint >= 0 && Math.abs(u - glint) < 0.09) c = el >= 2 ? (Math.abs(w) < 1 ? WHITE : ACC) : (Math.abs(w) < 1 ? WHITE : C[n - 2]);   // 刃光沿刃往上走
      p.px(Math.round(cx + w), Math.round(gy - z - k), c);
    }
  }
  // 护手 + 剑柄 + 柄头
  const gk = L + 1, gxx = gx + lean * gk, gw = Math.max(3, Math.round(W * 0.9 + 1));
  for (let w = -gw; w <= gw; w++) { p.px(Math.round(gxx + w), Math.round(gy - z - gk), w < 0 ? ST[4] : ST[3]); p.px(Math.round(gxx + w), Math.round(gy - z - gk - 1), ST[2]); }
  const HL = Math.max(3, Math.round(L * 0.22));
  for (let k = 0; k < HL; k++) { const hx = gx + lean * (gk + 2 + k); p.px(Math.round(hx), Math.round(gy - z - gk - 2 - k), ST[1]); p.px(Math.round(hx) - 1, Math.round(gy - z - gk - 2 - k), ST[2]); }
  p.px(Math.round(gx + lean * (gk + 2 + HL)), Math.round(gy - z - gk - 2 - HL), C[n - 3]);   // 柄头一点琥珀
}

const FALL_T = 0.1;   // 落下时长（同玩法 fall_t / rain_fall 0.1 秒）

function sword(p, t, o, C, ACC, ST, DU) {
  const raw = o.view === "raw", el = +o.el, n = C.length, L = +o.L, W = +o.W, lean = +o.lean, stick = +o.stick, fall = +o.fall;
  const end = FALL_T + stick, brk = smooth(end, end + 0.14, t);
  if (brk >= 0.99) return;
  if (t < FALL_T) {
    // 下落：先慢后快（同玩法剑雨），上方两道残影（拖出的速度线）
    const k = t / FALL_T, z = fall * (1 - k * k) + 0.5;
    for (let s = 1; s <= 2; s++) {   // 残影：剑身上方一条细光
      const z2 = z + L + 2 + s * 5;
      for (let d = 0; d < 6; d++) p.dot(Math.round(lean * (z2 - z + d)), Math.round(-z2 - d), s === 1 ? C[n - 3] : C[n - 5], s === 1 ? 0.9 : 0.6);
    }
    drawSword(p, 0, 0, z, L, W, lean, C, ST, ACC, el, false, -1);
    if (raw) p.light(0, -z - L * 0.4, C[n - 2], 0.5);
    return;
  }
  const sink = Math.min(3, Math.round(L * 0.14)), u = t - FALL_T;
  if (brk <= 0.01) {
    const hot = u < 0.067;
    const glint = (!hot && u < 0.3) ? clamp((u - 0.067) / 0.2) : -1;   // 插地后一拍起：刃光从剑尖往护手走一趟
    drawSword(p, 0, 0, -sink, L, W, lean, C, ST, ACC, el, hot, glint);
    if (hot && !raw) {   // 插地那一拍：地面一道横向刃光（白 → 琥珀，两头收）
      const fl = 8 + Math.round(L * 0.45);
      for (let x = -fl; x <= fl; x++) p.px(x, -1, Math.abs(x) < fl * 0.45 ? WHITE : C[n - 2]);
      for (let z = 0; z < 4 + L * 0.3; z++) p.px(0, -z - 1, WHITE);
    }
    if (glint >= 0.85 && !raw) {   // 刃光走到护手：一颗四芒小星（精二大一圈、冷青）
      const sy = -(L - sink) - 1, sx = Math.round(lean * L), arm = el >= 2 ? 4 : 2;
      for (let d = -arm; d <= arm; d++) { p.px(sx + d, sy, Math.abs(d) < 2 ? WHITE : (el >= 2 ? ACC : C[n - 2])); p.px(sx, sy + d, Math.abs(d) < 2 ? WHITE : (el >= 2 ? ACC : C[n - 2])); }
    }
    if (raw) p.light(0, -L * 0.4, C[n - 2], 0.4);
    return;
  }
  // 碎开：剑身碎成 2 格碎晶，往两侧落下、变暗
  const v = t - end;
  for (let i = 0; i < 6 + Math.round(L / 4); i++) {
    const k0 = L * nz(i * 2.3, o.seed + 301), a = (nz(i * 1.7, o.seed + 303) - 0.5) * 2.4;
    const x = lean * k0 + Math.sin(a) * 60 * v, y = -(k0 - sink) - 20 * v + 260 * v * v;
    if (y > 2) continue;
    if (nz(i * 4.1, o.seed + 305) < brk * 0.7) continue;
    const c = v < 0.05 ? C[n - 2] : v < 0.1 ? C[n - 4] : C[n - 5];
    p.px(Math.round(x), Math.round(y), c); p.px(Math.round(x) + 1, Math.round(y), c);
  }
}

function swordGround(p, t, o, C, ACC, ST, DU) {
  if (o.view === "raw") return;
  const SY = +o.SY, L = +o.L, W = +o.W, el = +o.el, n = C.length, end = FALL_T + +o.stick;
  const fade = smooth(end, end + 0.16, t);
  if (fade >= 0.99) return;
  if (t < FALL_T) {   // 预兆：剑的影子越来越实
    const k = t / FALL_T, rw = Math.round(W * 0.5 + 1 + 2 * k);
    for (let x = -rw; x <= rw; x++) p.px(x, 0, C[0]);
    if (k > 0.4) for (let x = -rw + 1; x < rw; x++) p.px(x, 1, C[0]);
    return;
  }
  const u = t - FALL_T, hot = u < 0.067;
  // 插地冲击：不规整短裂 + 一圈压扁的碎边（刚落时亮，冷成焦痕）
  const N = 5 + Math.round(L / 8) + el;
  for (let i = 0; i < N; i++) {
    const a = TAU * (i + nz(i * 1.3, o.seed + 401) * 0.6) / N, len = (3 + L * 0.28) * (0.6 + 0.5 * nz(i * 2.1, o.seed + 403));
    for (let d = 1; d < len; d += 1) {
      if (nz(d * 0.9 + i * 7, o.seed + 405) < fade * 0.9) continue;
      const c = hot ? (d < len * 0.5 ? WHITE : C[n - 2]) : u < 0.2 ? (el >= 2 && d < len * 0.5 ? ACC : C[n - 3]) : u < 0.35 ? C[n - 5] : DU[1];
      p.px(Math.round(Math.cos(a) * d), Math.round(Math.sin(a) * d * SY), c);
    }
  }
  for (let x = -2; x <= 2; x++) p.px(x, 0, DU[0]);   // 剑插进去的那一点压暗
  p.px(-1, 1, DU[0]); p.px(0, 1, DU[0]); p.px(1, 1, DU[0]);
}

// ---------------------------------------------------------------- 剑阵（精二剑雨收尾 / 剑雨滂沱起手）：地面一圈放射刃光 + 断续环，0.5 秒冷掉
function array(p, t, o, C, ACC, ST, DU) {
  const R = +o.R, SY = +o.SY, el = +o.el, n = C.length;
  const g = ease.outCubic(clamp(t / 0.15)), fade = smooth(0.2, 0.55, t);
  if (fade >= 0.99) return;
  const M = 8;
  for (let j = 0; j < M; j++) {   // 放射刃光：从中心往外一道道细光（白 → 冷青 / 琥珀 → 暗）
    const a = TAU * (j + 0.5 * nz(j, o.seed + 501)) / M, L = R * (0.55 + 0.4 * nz(j * 2.3, o.seed + 503)) * g;
    for (let d = 6; d < L; d += 1) {
      if (nz(d * 0.7 + j * 5, o.seed + 505) < fade * 0.95) continue;
      const q = d / Math.max(1, L);
      const c = t < 0.07 ? (q < 0.7 ? WHITE : C[n - 2]) : t < 0.25 ? (q > 0.6 ? C[n - 3] : (el >= 2 ? ACC : C[n - 2])) : C[n - 5];
      p.px(Math.round(Math.cos(a) * d), Math.round(Math.sin(a) * d * SY), c);
    }
  }
  const r = R * (0.5 + 0.5 * g), m = Math.ceil(r * TAU * 1.2);   // 断续环（2 格边 + 1 格暗内边）
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 3.1, o.seed + 511) < 0.25 + fade * 0.6) continue;
    const rr = r + 1.2 * nz(a * 6, o.seed + 513);
    const ci = clamp((t < 0.07 ? n - 1 : n - 3) - Math.round(fade * 3) - (Math.sin(a) < -0.2 ? 1 : 0), 1, n - 1);
    p.px(Math.round(Math.cos(a) * rr), Math.round(Math.sin(a) * rr * SY), C[ci]);
    p.px(Math.round(Math.cos(a) * (rr - 1)), Math.round(Math.sin(a) * (rr - 1) * SY), C[ci - 1 >= 1 ? ci - 1 : 1]);
    p.px(Math.round(Math.cos(a) * (rr - 2.5)), Math.round(Math.sin(a) * (rr - 2.5) * SY), C[1]);
  }
}

// ---------------------------------------------------------------- 钉剑（精一：被拔刀阻挡的敌人各插一柄源石剑，定住 pin_dur 0.7 秒后碎掉）：原点 = 敌人脚底，剑插在身上 h 高
function pin(p, t, o, C, ACC, ST) {
  const el = +o.el, n = C.length, h = +o.h, L = 15, W = 3, lean = 0.55;
  const STAY = 0.7, brk = smooth(STAY, STAY + 0.14, t);
  if (brk >= 0.99) return;
  const into = 4 * (1 - ease.outCubic(clamp(t / 0.067)));   // 刺进去：第 0 拍从斜上方扎入
  if (brk <= 0.01) {
    const hot = t < 0.067, glint = (t > 0.1 && t < 0.4) ? clamp((t - 0.1) / 0.3) : -1;
    // 只画露在身外的那一截（剑尖已没入）：从 h 往斜上方
    for (let k = 3; k <= L; k += 0.5) {
      const u = k / L, cx = lean * (k + into), z = h + k + into;
      for (let w = -W / 2; w <= W / 2; w += 0.5) {
        let c = Math.abs(w) < 0.6 ? (hot ? WHITE : C[n - 2]) : w < 0 ? C[n - 3] : C[n - 5];
        if (glint >= 0 && Math.abs(u - glint) < 0.12) c = el >= 2 ? ACC : WHITE;
        p.px(Math.round(cx + w), Math.round(-z), c);
      }
    }
    const gk = L + 1 + into, gx = lean * gk;
    for (let w = -2; w <= 2; w++) p.px(Math.round(gx + w), Math.round(-(h + gk)), w < 0 ? ST[4] : ST[3]);
    for (let k = 0; k < 3; k++) p.px(Math.round(lean * (gk + 2 + k)), Math.round(-(h + gk + 2 + k)), ST[1]);
    if (hot) for (let d = -3; d <= 3; d++) { p.px(d, -h, Math.abs(d) < 2 ? WHITE : C[n - 2]); p.px(0, -h + d, Math.abs(d) < 2 ? WHITE : C[n - 2]); }   // 刺入点一颗十字闪
    return;
  }
  const v = t - STAY;   // 碎开
  for (let i = 0; i < 6; i++) {
    const k0 = 3 + 11 * nz(i * 2.3, o.seed + 601), a = (nz(i * 1.7, o.seed + 603) - 0.5) * 2.6;
    const x = lean * k0 + Math.sin(a) * 50 * v, y = -(h + k0) - 15 * v + 240 * v * v;
    if (y > 0 || nz(i * 4.1, o.seed + 605) < brk * 0.7) continue;
    p.px(Math.round(x), Math.round(y), v < 0.06 ? C[n - 2] : C[n - 4]);
  }
}

// ---------------------------------------------------------------- 后期剑气（growth/late_shape 给近战的额外一击，vis_growth._fire_qi）：德克萨斯版 = 飞出去的源石剑
// 一次出手的几道剑气在游戏里合成一柄（S = 1 / 2 / 3+ 道 → 剑长 26 / 34 / 42），腰高平飞、剑尖朝前，身后三道速度线；
// 精一身后甩碎晶；精二刃上冷青刃光。三帧：0 热白 / 1 常态 / 2 碎开（游戏按剑气年龄与剩余寿命挑帧）。沿路落剑由游戏另生成（剑雨意象）
function qi(p, t, o, C, ACC, ST, DU) {
  const SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, S = +o.S;
  const L = [26, 34, 42][S - 1], W = [4, 5, 6][S - 1], H0 = 12;
  let fx = Math.cos(th), fy = Math.sin(th) * SY;
  const fl = Math.hypot(fx, fy); fx /= fl; fy /= fl;
  const nx = -fy, ny = fx;
  const f = Math.min(2, Math.round(t * 15)), brk = f === 2;
  for (let s = -L / 2; s <= L / 2; s += 0.5) {
    const u = (s + L / 2) / L;                                       // 0 剑柄端 → 1 剑尖
    if (brk && nz(s * 1.3, o.seed + 701) < 0.5) continue;
    const half = u < 0.18 ? 0.8 : (W / 2) * Math.min(1, (1 - u) / 0.28 + 0.15);
    for (let w = -half; w <= half; w += 0.5) {
      let c;
      if (u < 0.18) c = u < 0.06 ? C[n - 3] : (w < 0 ? ST[3] : ST[2]);   // 剑柄 / 护手
      else if (Math.abs(w) < 0.6) c = f === 0 ? WHITE : C[n - 2];
      else if (w < 0) c = f === 0 ? C[n - 2] : C[n - 3];
      else c = C[n - 4];
      if (el >= 2 && !brk && u > 0.3 && w < -half + 1.1) c = ACC;     // 精二：上沿一道冷青刃光
      if (brk) c = C[clamp(n - 4 + (Math.abs(w) < 0.6 ? 1 : 0), 1, n - 1)];
      p.px(Math.round(fx * s + nx * w), Math.round(fy * s + ny * w - H0), c);
    }
    if (u > 0.18 && Math.abs(Math.round(s * 2) % 2) === 0) {
      const gx = fx * s, gy = fy * s;                                 // 护手横档
      if (u < 0.22) for (let w = -W / 2 - 2; w <= W / 2 + 2; w += 0.5) p.px(Math.round(gx + nx * w), Math.round(gy + ny * w - H0), ST[4]);
    }
  }
  if (!brk) for (let k = 0; k < 3; k++) {                           // 身后三道速度线（长短不一）
    const w = (k - 1) * (W * 0.5 + 1), len = [10, 16, 9][k] + 4 * S;
    for (let d = 2; d < len; d += 1) p.dot(Math.round(fx * (-L / 2 - d) + nx * w), Math.round(fy * (-L / 2 - d) + ny * w - H0), d < len * 0.4 ? C[n - 3] : C[n - 5], d < len * 0.4 ? 1 : 0.7);
  }
  if (el >= 1) for (let i = 0; i < 4 + 2 * el; i++) {                // 身后甩出的碎晶
    const u2 = (f + 0.5) / 15, side = i % 2 ? 1 : -1;
    const X = fx * (-L / 2 - 6 - 50 * u2 * nz(i, o.seed + 711)) + nx * side * (W + 3 + 30 * u2 * nz(i * 2, o.seed + 713));
    const Y = fy * (-L / 2 - 6) + ny * side * (W + 3) - H0 - 20 * u2 + 200 * u2 * u2;
    p.px(Math.round(X), Math.round(Y), el >= 2 && i % 3 === 0 ? ACC : (f === 0 ? C[n - 2] : C[n - 4]));
  }
}

function qiGround(p, t, o, C) {
  const SY = +o.SY, th = +o.dir * D2R, S = +o.S, L = [26, 34, 42][S - 1];
  let fx = Math.cos(th), fy = Math.sin(th) * SY;
  const fl = Math.hypot(fx, fy); fx /= fl; fy /= fl;
  const f = Math.min(2, Math.round(t * 15));
  for (let s = -L / 2; s <= L / 2; s += 1) p.dot(Math.round(fx * s), Math.round(fy * s), C[0], f === 2 ? 0.3 : 0.55);   // 影子
}

// ---------------------------------------------------------------- S2 冲锋号令·γ型（精一解锁，永久生效；起手一次）：举剑处冲起一道琥珀光柱 + 脚下断续环；精二更高、顶上冷青四芒
function order(p, t, o, C, ACC, ST, DU) {
  const el = +o.el, n = C.length, Hm = el >= 2 ? 64 : 48;
  const grow = ease.outCubic(clamp(t / 0.1)), fade = smooth(0.15, 0.5, t);
  if (fade >= 0.99) return;
  const H = Hm * grow, x0 = 6;
  for (let z = 8; z < H; z += 0.5) {
    const u = (z - 8) / Math.max(1, Hm - 8), w = Math.max(0.5, (el >= 2 ? 3.5 : 2.5) * (1 - u * 0.85) * (1 - 0.6 * fade));
    if (fade > 0.2 && nz(z * 0.8, o.seed + 801) < fade * 0.8) continue;   // 散掉前一节节断开
    for (let x = -w; x <= w; x += 0.5) {
      const q = Math.abs(x) / w;
      let c = q < 0.35 ? (t < 0.07 ? WHITE : C[n - 2]) : q < 0.75 ? C[n - 3] : C[n - 5];
      c = fade > 0.5 && q < 0.35 ? C[n - 3] : c;
      p.px(Math.round(x0 + x), Math.round(-z), c);
    }
  }
  if (el >= 2 && t > 0.05 && t < 0.4) {   // 顶上一颗冷青四芒
    const sy = -Math.round(H) - 2, arm = 5;
    for (let d = -arm; d <= arm; d++) { const c = Math.abs(d) < 2 ? WHITE : ACC; p.px(x0 + d, sy, c); p.px(x0, sy + d, c); }
  }
  for (let i = 0; i < 6 + 3 * el; i++) {   // 往上飘的碎晶
    const u = t, x = x0 + (nz(i, o.seed + 803) - 0.5) * 20, z = 10 + 80 * u * (0.5 + nz(i * 2, o.seed + 805)) + 10 * nz(i * 3, o.seed + 807);
    if (nz(i * 5 + t * 15, o.seed + 809) < fade) continue;
    p.px(Math.round(x), Math.round(-z), el >= 2 && i % 3 === 0 ? ACC : C[n - 3]);
  }
}

function orderGround(p, t, o, C, ACC, ST, DU) {
  const R = +o.R, SY = +o.SY, n = C.length;
  const g = ease.outCubic(clamp(t / 0.18)), fade = smooth(0.15, 0.5, t), r = R * (0.45 + 0.55 * g);
  if (fade >= 0.99) return;
  const m = Math.ceil(r * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 3.1, o.seed + 821) < 0.25 + fade * 0.6) continue;
    const ci = clamp((t < 0.07 ? n - 1 : n - 3) - Math.round(fade * 3), 1, n - 1);
    p.px(Math.round(Math.cos(a) * r), Math.round(Math.sin(a) * r * SY), C[ci]);
    p.px(Math.round(Math.cos(a) * (r - 1.5)), Math.round(Math.sin(a) * (r - 1.5) * SY), C[1]);
  }
}

// ---------------------------------------------------------------- 连携技（技能连携 v2「追击」/ 旧连携「冲刺斩」）：目标处两道交叉的大刀痕（X，腰高），地上 X 形焦痕；原点 = 目标脚底，dir = 冲刺方向
function xcut(p, t, o, C, ACC, ST, DU) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : 14, th = +o.dir * D2R, n = C.length, R = +o.R;
  const hot = t < 0.067, cool = smooth(0.07, 0.4, t);
  if (cool >= 0.8) return;
  for (let k = 0; k < 2; k++) {
    if (k === 1 && t < 0.03) continue;                                 // 第二刀晚半拍（第 0 拍只有一刀）
    const a = th + (k === 0 ? 0.62 : -0.62), fx = Math.cos(a), fy = Math.sin(a) * SY;
    let nx = -fy, ny = fx; const nl = Math.hypot(nx, ny); nx /= nl; ny /= nl;
    const Wm = 5 * (1 - 0.6 * cool);
    for (let s = -R; s <= R; s += 0.5) {
      const u = (s + R) / (2 * R), prof = Math.pow(Math.sin(Math.PI * u), 0.6), hw = Wm * prof;
      if (hw < 0.5) continue;
      const bow = 4 * Math.sin(Math.PI * u) * (k === 0 ? 1 : -1);      // 微弯（刀走过的弧）
      for (let w = -hw; w <= hw; w += 0.5) {
        const q = Math.abs(w) / hw;
        let ci = q < 0.3 ? (hot || k === 1 && t < 0.1 ? n - 1 : n - 2) : q < 0.7 ? n - 3 : n - 5;
        ci = clamp(ci - Math.round(cool * 2.6), 1, n - 1);
        p.px(Math.round(fx * s + nx * (w + bow)), Math.round(fy * s + ny * (w + bow) - H0), C[ci]);
      }
    }
    if (raw) p.light(0, -H0, C[n - 2], 0.6 * (1 - cool));
  }
}

function xcutGround(p, t, o, C, ACC, ST, DU) {
  if (o.view === "raw") return;
  const SY = +o.SY, th = +o.dir * D2R, R = +o.R, n = C.length, fade = smooth(0.2, 0.6, t);
  if (fade >= 0.99) return;
  for (let k = 0; k < 2; k++) {
    const a = th + (k === 0 ? 0.62 : -0.62), fx = Math.cos(a), fy = Math.sin(a) * SY;
    for (let s = -R * 0.8; s <= R * 0.8; s += 1) {
      if (nz(s * 0.9 + k * 13, o.seed + 901) < fade * 0.9) continue;
      const c = t < 0.07 ? C[n - 2] : t < 0.25 ? C[n - 4] : DU[1];
      p.px(Math.round(fx * s), Math.round(fy * s), c);
      if (Math.abs(s) < R * 0.4) p.px(Math.round(fx * s), Math.round(fy * s) + 1, DU[0]);
    }
  }
}

// ---------------------------------------------------------------- 旧做法对照用的直线刀光（冲刺 / 次元斩）：一条水平长条，游戏里旋转 + 横向拉伸
function rawLine(p, t, o, C) {
  const n = C.length, fade = smooth(0.05, 0.3, t);
  if (fade >= 0.99) return;
  for (let x = -32; x <= 32; x++) {
    const u = Math.abs(x) / 32, w = 3 * (1 - u * u);
    for (let y = -w; y <= w; y += 0.5) p.px(x, Math.round(y), Math.abs(y) < 1 ? WHITE : C[n - 3]);
  }
  for (let x = -32; x <= 32; x += 4) p.light(x, 0, C[n - 2], 0.5 * (1 - fade));
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ST = fit(o.steel, 6), DU = fit(o.dust, 5), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "slash": return gd ? slashGround(p, t, o, C, DU) : slash(p, t, o, C, ACC, ST);
    case "spin": return gd ? spinGround(p, t, o, C) : spin(p, t, o, C, ACC);
    case "sword": return gd ? swordGround(p, t, o, C, ACC, ST, DU) : sword(p, t, o, C, ACC, ST, DU);
    case "array": return gd ? array(p, t, o, C, ACC, ST, DU) : undefined;
    case "pin": return gd ? undefined : pin(p, t, o, C, ACC, ST);
    case "qi": return gd ? qiGround(p, t, o, C) : qi(p, t, o, C, ACC, ST, DU);
    case "order": return gd ? orderGround(p, t, o, C, ACC, ST, DU) : order(p, t, o, C, ACC, ST, DU);
    case "xcut": return gd ? xcutGround(p, t, o, C, ACC, ST, DU) : xcut(p, t, o, C, ACC, ST, DU);
    case "line": return rawLine(p, t, o, C);
  }
}
