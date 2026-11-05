// 水月「转平面」（docs/261，开关 fx/px_plane）：pixelfx 画法，按本作俯视斜角重画（同 docs/246 斯卡蒂的做法）。
// 意象：深海、水母、触手、幻象（镜花水月）。色：本人深蓝紫 8 阶（house.js OP.mizuki 加一阶淡紫白）；
// 水母荧光青 #6fe8ff（原作命中的青色水母伞）；精二点缀荧光紫 #b98cff（深蓝之籽 / 镜花水月）。不用危险红。
// 一个文件按 part 出多种件，每种分两层导出（layer）：
//   up 立起层 —— 离地的东西（腰高的伞面刀痕、竖直触手、水母伞、缠绕），原点 = 脚底地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（投影、裂隙暗水、冲击环、水镜），已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层。
// 1 像素 = 1 美术像素 = 2 世界像素；方向件按 dir（平面角，度）逐向生成，游戏挑最近一张（另一半水平翻转）。
// view: "raw" 出「旧做法」对照：正俯视原样（圆不压扁、光晕烤进颜色），游戏里旋转 + 小数缩放贴上去。
// 画面随机只用 noise 散列（seed），不抽随机数。半透明淡出不用 Bayer 抖动（2 倍下成网点），用噪声成团消散或真半透明 blend。
import { clamp, smooth, ease, noise, TAU, hex, WHITE, fit } from "../../core/index.js";

export const meta = {
  name: "Mizuki plane",
  desc: "Mizuki's umbrella sweeps, tentacles, jellyfish blooms, binding coils and moon-in-the-water field redrawn for a 3/4 top-down plane.",
  tags: ["water", "tentacle", "jellyfish", "topdown", "mizuki", "one-shot"],
  size: [360, 320],
  origin: [180, 210],
  duration: 0.8,
  loop: false,
  fps: 15,
  bg: "dark",
  options: {
    palette: ["#070a22", "#111a52", "#1e2f8f", "#3150c8", "#5a7cf0", "#9aa8ff", "#cfd6ff", "#ffffff"],
    cyan: "#6fe8ff",
    cyanL: "#c4f7ff",
    accent: "#b98cff",
    part: "sweep",
    layer: "up",
    view: "plane",
    style: "basic",
    R: 56, span: 2.6, dir: 0, H0: 12, W: 10, H: 32,
    el: 0, SY: 0.72, dur: 0.42, seed: 3, n: 6, half: "front",
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1
const R0 = (v) => Math.round(v);

// ---------------------------------------------------------------- 伞击（腰高的伞面刀痕）
// 伞面月牙：外缘是伞沿的一排弧形扇贝（伞骨之间鼓出），伞骨是几条暗一阶的径向线；刃 = 外缘 1 格亮边。
// 精一：伞沿下挂一排水母细须（内沿往下垂的 2–4 格短线）+ 外缘青色荧光点；精二：伞骨换荧光紫 + 内沿一道荧光紫副弧。
// style：basic 普攻 / s1 唤醒（更大更白、外缘青色水母荧光、伞骨发亮）/ s2 囚徒困境（更快更薄、青白、身后一道幻影残弧）/ s3 镜花水月旋斩（深蓝紫 + 荧光紫刃）
function sweepT(t, span, full) {
  const a0 = -span / 2;
  const head = a0 + span * (full ? 0.45 + 0.55 * clamp(t / 0.1) : 0.6 + 0.4 * clamp(t / 0.067));
  const tail = a0 + span * 0.2 * smooth(0.07, 0.32, t);
  return [a0, head, tail];
}

function canopy(p, t, o, C, X, k) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : +o.H0, th = +o.dir * D2R, el = +o.el, n = C.length;
  const st = o.style || "basic", full = k.full;
  const tt = t - (k.dt || 0);
  if (tt < 0) return;
  const span = full ? TAU * 0.86 : +o.span;
  const [a0, head, tail] = sweepT(tt, span, full);
  const hot = tt < (st === "s1" ? 0.13 : 0.08), cool = smooth(0.08, +o.dur, tt);
  if (head - tail < 0.03 || cool >= 0.74) return;
  const R = k.R, Wr = k.W * (1 - 0.65 * cool);
  const ribs = full ? 22 : Math.max(5, Math.round(span * 3.2));   // 伞骨数
  const B = R + 4;
  p.shade(-B, -B * SY - H0 - 2, B, B * SY - H0 + 6, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 2 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x) - th;
    a = ((a - a0) % TAU + TAU) % TAU + a0;
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);
    let wr = Wr * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.7)), 0.7);
    if (full) wr *= 0.78 + 0.4 * nz(a * 1.3, +o.seed + 41);
    if (wr < 0.8) return;
    const rf = ((a - a0) / span) * ribs, fr = rf - Math.floor(rf);          // 伞骨之间的位置 0..1
    const scal = 2.6 * Math.sin(Math.PI * fr);                               // 伞沿扇贝：伞骨之间鼓出
    const edgeR = R - 2.6 + scal;
    const q = (edgeR - r) / wr;                                              // 0 外缘 → 1 内沿
    if (q < -0.02 || q > 1) return;
    let ci;
    if (q < 0.14) ci = hot ? n - 1 : n - 2;                                   // 伞沿亮边（刃）
    else if (q < 0.36) ci = n - 3;
    else if (q < 0.62) ci = n - 4;
    else if (q < 0.86) ci = n - 5;
    else ci = n - 6;
    const rib = fr < 0.09 || fr > 0.91;                                      // 伞骨线
    if (rib && q > 0.16) ci -= 1;
    if (st === "s1") ci += 1;
    if (st === "s2") ci += q < 0.5 ? 1 : 0;
    if (st === "s3") ci -= 1;
    if (hot && u > 0.8 && q < 0.55) ci = n - 1;                              // 伞尖热白
    ci = clamp(ci - Math.round(cool * 2.5) - (u < 0.18 ? 1 : 0), 1, n - 1);
    out.c = C[ci];
    if (q > 0.86 && nz(r * 1.7 + a * 9, +o.seed + 77) < 0.45) return 0;      // 内沿成团变稀（不平涂、不网点）
    if (!hot && q < 0.14 && (st === "s1" || st === "s2")) out.c = st === "s1" ? X.cyL : X.cyL;   // 唤醒 / 囚徒困境：青白沿
    else if (!hot && q < 0.14 && st === "basic" && el >= 1) out.c = X.cy;     // 精一起：普攻伞沿换水母荧光青
    if (st === "s3" && !hot && q < 0.16) out.c = X.ac;                       // 镜花水月：荧光紫刃
    if (el >= 2 && !hot && rib && q > 0.16 && q < 0.8 && st !== "s2") out.c = X.ac;   // 精二：伞骨荧光紫
    if (cool > 0.55 && nz(r * 2.3 + a * 13, +o.seed + 79) < 0.4) return 0;   // 收势最后两拍成团消散
  });
  if (raw) for (let a = tail; a <= head; a += 0.12) p.light(Math.cos(a + th) * R * 0.9, Math.sin(a + th) * R * 0.9, C[n - 2], 0.35 * (1 - cool));
  // 精一起：伞沿下垂的水母细须（内沿往下挂，随收势变短）
  if (el >= 1 && cool < 0.6 && st !== "s3") {
    for (let a = tail + (head - tail) * 0.15; a <= head; a += 0.075) {
      if (nz(a * 5.3, +o.seed + 13) < 0.35) continue;
      const rr = R - Wr * 0.9, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY - H0;
      const L = R0((3 + 4 * nz(a * 7.7, +o.seed + 17)) * (1 - cool));
      for (let s = 1; s <= L; s++) p.px(R0(x + Math.sin(s * 0.9 + a * 4) * 0.6), R0(y + s), s <= 1 ? C[n - 3] : el >= 2 ? X.ac : C[n - 5]);
    }
    for (let a = tail + (head - tail) * 0.3; a <= head; a += 0.17) {   // 外缘青色荧光点
      if (nz(a * 8.1, +o.seed + 19) < 0.55) continue;
      const rr = R + 2, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY - H0;
      p.px(R0(x), R0(y), X.cy);
    }
  }
  // 囚徒困境：身后一道幻影残弧（晚一拍、暗两阶、只画伞沿那一圈）
  if (st === "s2" && tt > 0.066 && cool < 0.5) {
    const Rg = R - Wr - 3;
    for (let a = tail; a <= head - 0.15; a += 0.6 / Rg) {
      if (nz(a * 6.1, +o.seed + 23) < 0.3) continue;
      p.px(R0(Math.cos(a + th) * Rg), R0(Math.sin(a + th) * Rg * SY - H0), C[n - 4]);
    }
  }
  // 精二：内沿一道荧光紫副弧（镜花水月旋斩本来就是紫刃，不再加）
  if (el >= 2 && st !== "s3" && cool < 0.5) {
    const Rg = R - Wr * 0.55;
    for (let a = tail + (head - tail) * 0.25; a <= head; a += 0.5 / Rg) if (nz(a * 9.3, +o.seed + 29) > 0.35)
      p.px(R0(Math.cos(a + th) * Rg), R0(Math.sin(a + th) * Rg * SY - H0), X.ac);
  }
  // 唤醒 / 镜花水月：沿弧向外甩出几滴荧光水
  if ((st === "s1" || st === "s3") && tt > 0.03 && tt < 0.32) {
    const u = tt - 0.03, N = st === "s1" ? 14 + 3 * el : 18;
    for (let i = 0; i < N; i++) {
      const a = tail + (head - tail) * nz(i * 2.3, +o.seed + 301) + th, sp = 45 + 55 * nz(i * 1.9, +o.seed + 303);
      const x = Math.cos(a) * (R + sp * u), y = Math.sin(a) * (R + sp * u) * SY - H0 - 30 * u + 280 * u * u;
      const c = u < 0.1 ? WHITE : st === "s3" ? (i % 2 ? X.ac : C[n - 3]) : (i % 2 ? X.cy : C[n - 3]);
      p.px(R0(x), R0(y), c);
      if (i % 3 === 0) p.px(R0(x) + 1, R0(y), c);
    }
  }
}

// 地上：伞面刀痕的投影阴影（外半圈）
function canopyGround(p, t, o, C, X, full) {
  if (o.view === "raw") return;
  const R = +o.R, W = +o.W, SY = +o.SY, th = +o.dir * D2R;
  const span = full ? TAU * 0.86 : +o.span;
  const [, head, tail] = sweepT(t, span, full);
  const cool = smooth(0.08, +o.dur, t);
  if (head - tail < 0.03 || cool >= 0.74) return;
  for (let a = tail; a <= head; a += 0.45 / R) {
    const u = (a - tail) / Math.max(0.001, head - tail);
    const wr = W * 0.5 * Math.pow(Math.sin(Math.PI * Math.pow(u, 1.7)), 0.7);
    for (let d = 0; d < wr; d += 1) {
      const rr = R - d, x = Math.cos(a + th) * rr, y = Math.sin(a + th) * rr * SY;
      p.dot(R0(x), R0(y), C[0], 0.42 * (1 - cool));
    }
  }
}

// ---------------------------------------------------------------- 触手（从目标脚下的裂隙里钻出）
// 立起：基部粗、往上收尖、顶端卷成钩；出（2 拍升起）→ 抽（朝前倾、钩甩出去）→ 停 → 缩回地里。
// 身：暗靛（背光侧）→ 深蓝 → 亮边（受光侧 1 格）；精一起内侧一排淡色吸盘点；精二吸盘换荧光紫、旁边多一根细的。
// style：basic / link（连携：更高、青色亮边、两根）/ big（镜花水月：更粗）
function tentShape(t, H, lean, seed) {
  const up = ease.outCubic(clamp(t / 0.13)), sink = smooth(0.3, 0.46, t);
  const h = H * up * (1 - 0.95 * sink);
  const whip = smooth(0.06, 0.18, t) * (1 - 0.5 * smooth(0.2, 0.34, t));
  return { h, whip: whip * lean, curl: 0.45 + 0.85 * smooth(0.05, 0.2, t) };   // 卷到约 1.3π：张开的钩，不闭成圈
}

function tentacle(p, t, o, C, X, k) {
  const el = +o.el, n = C.length, st = o.style || "basic";
  const H = k.H, w0 = k.w0, dx0 = k.dx || 0, lean = k.lean === undefined ? 1 : k.lean;
  const s = tentShape(t - (k.dt || 0), H, lean, +o.seed);
  if (s.h < 2) return;
  const N = Math.max(4, Math.ceil(s.h * 1.3));
  const pts = [];
  for (let i = 0; i <= N; i++) {
    const v = i / N, z = v * s.h;
    const bend = s.whip * Math.pow(v, 1.8) * H * 0.45 + Math.sin(v * 3.2 + +o.seed) * 1.2 * v;
    pts.push([dx0 + bend, -z, v]);
  }
  // 顶端卷钩：最后一段按螺线卷回来
  const tip = pts[pts.length - 1], hookR = Math.max(3, w0 * 0.7), sg = lean >= 0 ? 1 : -1;
  const HN = Math.ceil(hookR * s.curl * 4);
  for (let j = 1; j <= HN; j++) {   // 连续的螺线卷钩（逐半格取点，不留虚点）
    const u = j / HN, a = u * s.curl * Math.PI, rr = hookR * (1 - 0.45 * u);
    pts.push([tip[0] + sg * (Math.sin(a) * rr), tip[1] - (1 - Math.cos(a)) * rr * 0.85, 1 + u * 0.5]);
  }
  for (let i = 0; i < pts.length; i++) {
    const [x, y, v] = pts[i];
    const w = v > 1 ? Math.max(1, 2.6 * (1.5 - v) * 2 * 0.5 + 0.4) : Math.max(2, w0 * (1 - v * 0.74));
    const hw = w / 2;
    for (let d = -hw; d <= hw; d += 0.5) {
      const q = (d + hw) / Math.max(0.5, w);                     // 0 背光侧 → 1 受光侧
      let ci = q < 0.25 ? 1 : q < 0.6 ? 2 : q < 0.85 ? 3 : 5;
      if (st === "big") ci += q > 0.5 ? 1 : 0;
      const X0 = R0(x + d), Y0 = R0(y);
      let c = C[clamp(ci, 1, n - 1)];
      if (q >= 0.85 && st === "link") c = X.cyL;
      if (q >= 0.85 && st !== "link" && t < 0.1) c = C[n - 2];
      p.px(X0, Y0, c);
    }
    // 吸盘（内侧一排点）
    if (el >= 1 && v > 0.15 && v < 0.85 && i % 3 === 0) p.px(R0(x - hw * 0.4), R0(y), el >= 2 ? X.ac : C[n - 3]);
  }
}

function tent(p, t, o, C, X) {
  const el = +o.el, st = o.style || "basic", H = +o.H;
  const w0 = st === "big" ? 10 : st === "link" ? 9 : 6 + el;
  tentacle(p, t, o, C, X, { H, w0, lean: 1 });
  if (el >= 2 || st === "link") tentacle(p, t, o, C, X, { H: H * 0.62, w0: Math.max(3, w0 - 3), dx: -6, lean: -0.8, dt: 0.05 });
  if (o.view === "raw") p.light(0, -H * 0.5, C[5], 0.4);
}

// 地上：触手钻出的裂隙——一摊参差的暗水（深靛芯 + 深蓝边 + 几点荧光），收拢消失
function rift(p, t, o, C, X) {
  if (o.view === "raw") return;
  const SY = +o.SY, el = +o.el, Rr = (+o.H) * 0.34 + 2;
  const g = ease.outCubic(clamp(t / 0.1)) * (1 - smooth(0.3, 0.5, t));
  const R = Rr * g;
  if (R < 1) return;
  p.shade(-R - 2, -R * SY - 2, R + 2, R * SY + 2, (x, y, out) => {
    const pz = y / SY, a = Math.atan2(pz, x), r = Math.hypot(x, pz);
    const rr = R * (0.78 + 0.32 * nz(a * 2.6, +o.seed + 51));
    if (r > rr) return;
    const q = r / rr;
    out.c = q > 0.82 ? C[2] : q > 0.6 ? C[1] : C[0];
    if (q > 0.82 && nz(a * 11, +o.seed + 53) > 0.82) out.c = el >= 2 ? X.ac : X.cy;
  });
}

// ---------------------------------------------------------------- 水母绽开（命中）
// 原作 attack_hit：蓝色尖刺星芒一闪 → 青色水母伞鼓开（伞沿扇贝、伞里亮顶）→ 伞往上浮、颜色暗下、细须往下飘 → 散掉。
// 精二：伞里一朵四瓣荧光紫花（原作 skill_03_hit 的四瓣纹）。style：hit 普攻（小）/ burst 唤醒创伤扩散（大、多须）/ sting 深蓝之籽（紫）
function bell(p, cx, cy, R, C, X, body, rim, top, k) {
  // 伞：上半椭圆 + 下缘扇贝
  const n = C.length, hh = R * 0.78;
  p.shade(cx - R - 1, cy - hh - 1, cx + R + 1, cy + 3, (x, y, out) => {
    const dx = (x - cx) / R, dy = (y - cy) / hh;
    if (dy > 0) {   // 下缘扇贝
      const sc = 0.22 * Math.abs(Math.sin(dx * Math.PI * 2.5));
      if (dy > sc || Math.abs(dx) > 1) return;
      out.c = rim;
      return;
    }
    const r = Math.hypot(dx, dy);
    if (r > 1) return;
    if (k.outline && r < 0.72) return;                        // 只剩伞的轮廓
    out.c = r > 0.86 ? rim : dy < -0.55 && Math.abs(dx) < 0.45 ? top : body;
  });
}

function bloom(p, t, o, C, X) {
  const el = +o.el, n = C.length, st = o.style || "hit", raw = o.view === "raw";
  const R = +o.R;
  const f = Math.floor(t * 15 + 1e-6);
  const cy0 = -(+o.H0);
  const cyan = st === "sting" ? X.ac : X.cy, cyanL = st === "sting" ? C[6] : X.cyL;
  if (f === 0) {   // 尖刺星芒一闪
    const N = st === "burst" ? 9 : 7;
    for (let i = 0; i < N; i++) {
      const a = (i / N) * TAU + nz(i * 1.3, +o.seed + 61) * 0.5, L = R * (0.7 + 0.5 * nz(i * 2.1, +o.seed + 63));
      for (let d = 0; d <= L; d += 0.5) p.px(R0(Math.cos(a) * d), R0(cy0 + Math.sin(a) * d * 0.8), d < L * 0.45 ? WHITE : cyanL);
    }
    p.shade(-3, cy0 - 3, 3, cy0 + 3, (x, y, out) => (Math.hypot(x, y - cy0) <= 2.5 ? WHITE : undefined));
    if (raw) p.light(0, cy0, cyanL, 0.8);
    return;
  }
  if (f > 5) return;
  const rise = [0, 0, 1, 3, 5, 7][f], Rk = R * [0, 0.85, 1.0, 1.0, 0.95, 0.9][f];
  const cy = cy0 - rise;
  const dim = f >= 4;
  bell(p, 0, cy, Rk, C, X, dim ? C[4] : cyan, dim ? C[3] : cyanL, dim ? C[5] : WHITE, { outline: f >= 4 });
  // 精二四瓣花纹
  if (el >= 2 && f >= 1 && f <= 4) {
    const pr = Rk * 0.42;
    for (let a = 0; a < TAU; a += 0.06) {
      const rr = pr * Math.abs(Math.cos(2 * a));
      p.px(R0(Math.cos(a) * rr), R0(cy - Rk * 0.32 + Math.sin(a) * rr * 0.75), f >= 3 ? C[5] : X.ac);
    }
  }
  // 细须：伞下往下飘（精一起更多更长）
  if (f >= 2) {
    const ns = (st === "burst" ? 6 : 3) + el;
    for (let i = 0; i < ns; i++) {
      const x0 = (i / Math.max(1, ns - 1) - 0.5) * Rk * 1.5;
      const L = Rk * (0.7 + 0.25 * el) * (st === "burst" ? 1.4 : 1) * (1 - 0.25 * (f - 2));
      for (let s = 1; s <= L; s++) {
        if (f >= 4 && (s + i) % 2) continue;
        p.px(R0(x0 + Math.sin(s * 0.55 + i * 1.7 + f) * 1.2), R0(cy + 2 + s), s < L * 0.4 ? (dim ? C[4] : cyan) : (el >= 2 ? X.ac : C[4]));
      }
    }
  }
  if (raw) p.light(0, cy - Rk * 0.3, cyan, 0.6 * (1 - f / 6));
}

// 地上：唤醒创伤扩散的冲击环（只画边：2 格亮边 + 2 格深色内边，有断口，往外扩）/ 普攻命中小湿印
function bloomGround(p, t, o, C, X) {
  if (o.view === "raw") return;
  const SY = +o.SY, st = o.style || "hit", R = +o.R;
  if (st !== "burst") return;
  const Rg = R * 2.2 * ease.outCubic(clamp(t / 0.2));
  const fade = smooth(0.18, 0.42, t);
  if (fade >= 1 || Rg < 2) return;
  const m = Math.ceil(Rg * TAU);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 3.7, +o.seed + 71) < 0.22 + 0.5 * fade) continue;
    for (let d = 0; d < 4; d++) {
      const rr = Rg - d, x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY;
      p.px(R0(x), R0(y), d < 2 ? (d === 0 && t < 0.13 ? X.cyL : C[4]) : C[1]);
    }
  }
}

// ---------------------------------------------------------------- 缠绕（束缚 / 连携）
// 一根触手绕敌人腰间一圈多（1.25 圈，矮螺旋，不挡住敌人），分前半圈 / 后半圈两张（游戏里后半圈排在敌人后面、前半圈排在前面）；循环：一勒一松。
function coil(p, t, o, C, X) {
  const el = +o.el, n = C.length, SY = +o.SY, rx = +o.R, half = o.half;
  const f = Math.floor(t * 15 + 1e-6) % 6;
  const sq = [0, 1, 1.5, 1, 0, -0.5][f];
  const ry = rx * SY * 0.62;
  const TURN = TAU * 1.25;
  for (let a = 0; a < TURN; a += 0.5 / rx) {
    const z = 3 + (a / TURN) * 5;                              // 螺旋往上
    const s = Math.sin(a);
    const front = s > 0;
    if ((half === "front") !== front) continue;
    const r = rx - sq * 0.6;
    const x = Math.cos(a) * r, y = s * ry - z;
    const w = 3 - (a / TURN) * 1.2;                            // 往末端收细
    for (let d = 0; d < w; d += 0.5) {
      const ci = d < 0.8 ? 1 : d < w - 1 ? (front ? 3 : 2) : front ? 5 : 3;
      p.px(R0(x), R0(y + d - w / 2), C[ci]);
    }
    if (front && el >= 1 && Math.floor(a * 3) % 4 === 0) p.px(R0(x), R0(y), el >= 2 ? X.ac : C[n - 3]);
  }
  // 末端翘起的小钩（前半圈）
  if (half === "front") {
    const a = TURN, x = Math.cos(a) * rx, y = Math.sin(a) * ry - 8;
    for (let j = 0; j < 4; j++) p.px(R0(x + j * 0.6), R0(y - j), C[4 - (j > 2 ? 1 : 0)]);
  }
}

// ---------------------------------------------------------------- 一圈触手（S2 起手 / 惊跳反射·余悸）
// n 根触手在半径 R 上先后钻出、朝外倾；S2 起手（style s2）中心一团冰蓝尖晶炸开 + 暗色碎屑（原作 skill_02_start）
function tring(p, t, o, C, X, gd) {
  const R = +o.R, SY = +o.SY, N = +o.n, el = +o.el, st = o.style || "ring";
  const items = [];
  for (let i = 0; i < N; i++) {
    const a = (i / N) * TAU + 0.3 + nz(i * 1.9, +o.seed + 81) * 0.4;
    items.push({ a, x: Math.cos(a) * R * (0.85 + 0.2 * nz(i, +o.seed + 83)), y: Math.sin(a) * R * SY * (0.85 + 0.2 * nz(i, +o.seed + 83)), dt: 0.03 * (i % 3) });
  }
  if (gd) {
    for (const it of items) {
      const tt = t - it.dt;
      if (tt < 0) continue;
      const pp = { x: it.x, y: it.y };
      const sub = Object.assign({}, o, { H: +o.H });
      p.save && p.save();
      // 每根的裂隙
      const g = ease.outCubic(clamp(tt / 0.1)) * (1 - smooth(0.3, 0.5, tt)), r = (+o.H * 0.3 + 2) * g;
      if (r >= 1) p.shade(pp.x - r - 1, pp.y - r * SY - 1, pp.x + r + 1, pp.y + r * SY + 1, (x, y, out) => {
        const dx = x - pp.x, dz = (y - pp.y) / SY, rr = r * (0.8 + 0.3 * nz(Math.atan2(dz, dx) * 2.6, +o.seed + 85 + it.a));
        const q = Math.hypot(dx, dz) / rr;
        if (q > 1) return;
        out.c = q > 0.75 ? C[2] : C[0];
      });
    }
    if (st === "s2") {   // 中心：暗色碎屑落地
      const fade = smooth(0.2, 0.6, t);
      for (let i = 0; i < 26; i++) {
        if (nz(i * 3.1, +o.seed + 87) < fade) continue;
        const a = nz(i * 1.3, +o.seed + 89) * TAU, d = 6 + 30 * nz(i * 2.7, +o.seed + 91) * ease.outCubic(clamp(t / 0.25));
        p.px(R0(Math.cos(a) * d), R0(Math.sin(a) * d * SY), i % 4 ? C[1] : C[3]);
      }
    }
    return;
  }
  items.sort((A, B) => A.y - B.y);
  for (const it of items) {
    const lean = it.x >= 0 ? 0.7 : -0.7;
    const H = +o.H * (0.8 + 0.4 * nz(it.a * 3, +o.seed + 93));
    const sub = (x0, y0) => tentacle({
      px: (x, y, c) => p.px(x + R0(x0), y + R0(y0), c),
    }, t, o, C, X, { H, w0: 5 + el, lean, dt: it.dt });
    sub(it.x, it.y);
  }
  if (st === "s2" && t < 0.27) {   // 中心冰蓝尖晶
    const f = Math.floor(t * 15 + 1e-6), L0 = [14, 24, 20, 12][f] || 0;
    for (let i = 0; i < 11; i++) {
      const a = (i / 11) * TAU + nz(i * 1.7, +o.seed + 95), L = L0 * (0.55 + 0.6 * nz(i * 2.9, +o.seed + 97));
      for (let d = 0; d <= L; d += 0.5) {
        const wv = (1 - d / L) * 1.6;
        for (let w = -wv; w <= wv; w += 0.5)
          p.px(R0(Math.cos(a) * d - Math.sin(a) * w), R0(-14 + Math.sin(a) * d * 0.8 + Math.cos(a) * w), d < L * 0.35 || f === 0 ? WHITE : f >= 2 ? C[5] : X.cyL);
      }
    }
  }
}

// ---------------------------------------------------------------- 镜花水月起手：一只大水母从脚下浮起 + 地上一圈水镜（带一弯月影）
function moon(p, t, o, C, X, gd) {
  const SY = +o.SY, R = +o.R, n = C.length;
  if (gd) {
    const Rg = R * (0.35 + 0.65 * ease.outCubic(clamp(t / 0.25)));
    const fade = smooth(0.3, 0.6, t);
    if (fade >= 1) return;
    const m = Math.ceil(Rg * TAU * 1.1);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 3.1, +o.seed + 101) < 0.18 + 0.6 * fade) continue;
      for (let d = 0; d < 5; d++) {
        const rr = Rg - d, x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY;
        p.px(R0(x), R0(y), d === 0 ? (t < 0.14 ? WHITE : X.ac) : d < 3 ? C[4] : C[1]);
      }
    }
    for (let d = 5; d < 14; d++) for (let j = 0; j < m; j += 1) {   // 内侧淡渐变（真半透明，不抖动）
      const a = (j / m) * TAU, rr = Rg - d;
      p.blend(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), C[3], 0.12 * (1 - (d - 5) / 9) * (1 - fade));
    }
    // 月影：地上一弯新月，水纹里抖
    if (t > 0.07) {
      const mr = 9, sh = Math.floor(t * 15) % 2;
      p.shade(-mr - 2, -mr * SY - 2, mr + 2, mr * SY + 2, (x, y, out) => {
        const a1 = Math.hypot(x, y / SY), a2 = Math.hypot(x - 4, y / SY + 1);
        if (a1 > mr || a2 < mr * 0.92) return;
        if ((R0(y) + sh) % 3 === 0) return;                        // 水纹横断
        out.c = a1 > mr - 1.5 ? WHITE : C[6];
      });
    }
    return;
  }
  // 立起：大水母浮起（伞 R 20、长须），亮 → 淡紫轮廓 → 散
  const rise = 8 + 46 * ease.outCubic(clamp(t / 0.45));
  const f = Math.floor(t * 15 + 1e-6);
  if (t > 0.6) return;
  const Rb = 18 + 3 * Math.sin(t * 18);
  const dim = t > 0.38;
  bell(p, 0, -rise, Rb, C, X, dim ? C[4] : X.cy, dim ? X.ac : X.cyL, WHITE, { outline: t > 0.47 });
  for (let a = 0; a < TAU; a += 0.04) {   // 伞里四瓣花纹
    const rr = Rb * 0.45 * Math.abs(Math.cos(2 * a));
    p.px(R0(Math.cos(a) * rr), R0(-rise - Rb * 0.3 + Math.sin(a) * rr * 0.75), X.ac);
  }
  for (let i = 0; i < 9; i++) {
    const x0 = (i / 8 - 0.5) * Rb * 1.6, L = 30 + 12 * nz(i * 1.7, +o.seed + 103);
    for (let s = 1; s <= L; s++) {
      if (t > 0.45 && (s + i) % 2) continue;
      p.px(R0(x0 + Math.sin(s * 0.3 + i * 1.3 + t * 12) * 2), R0(-rise + 2 + s), s < 8 ? X.cy : i % 2 ? X.ac : C[4]);
    }
  }
  if (f === 0) for (let i = 0; i < 12; i++) {   // 起手一闪
    const a = (i / 12) * TAU, L = 20 + 10 * nz(i, +o.seed + 105);
    for (let d = 4; d <= L; d += 0.5) p.px(R0(Math.cos(a) * d), R0(-14 + Math.sin(a) * d * 0.7), d < 10 ? WHITE : X.cyL);
  }
}

// 镜花水月持续：脚下一面水镜（只画断续的边 + 2 格深色内边 + 贴边淡渐变，循环，跟着人走；几点水光）
function pool(p, t, o, C, X) {
  const R = +o.R, SY = +o.SY, f = Math.floor(t * 15 + 1e-6) % 6;
  const m = Math.ceil(R * TAU * 1.1), rot = f * 0.05;
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz((a + rot) * 3.3, +o.seed + 111) < 0.42) continue;
    const rr = R * (1 + 0.012 * Math.sin(a * 5 + f));
    for (let d = 0; d < 4; d++) {
      const x = Math.cos(a) * (rr - d), y = Math.sin(a) * (rr - d) * SY;
      p.px(R0(x), R0(y), d === 0 ? X.ac : d === 1 ? C[3] : C[1]);
    }
  }
  for (let d = 4; d < 12; d++) for (let j = 0; j < m; j += 2) {
    const a = (j / m) * TAU, rr = R - d;
    p.blend(R0(Math.cos(a) * rr), R0(Math.sin(a) * rr * SY), C[3], 0.1 * (1 - (d - 4) / 8));
  }
  for (let i = 0; i < 5; i++) {   // 水光：几点亮，按拍轮换
    if ((i + f) % 3) continue;
    const a = nz(i * 2.3, +o.seed + 113) * TAU, d = R * (0.3 + 0.55 * nz(i * 4.1, +o.seed + 115));
    const x = R0(Math.cos(a) * d), y = R0(Math.sin(a) * d * SY);
    p.px(x, y, C[6]); p.px(x - 1, y, C[4]); p.px(x + 1, y, C[4]);
  }
}

// ---------------------------------------------------------------- 深蓝之籽：小水母（循环，一张一缩）
function jelly(p, t, o, C, X) {
  const f = Math.floor(t * 15 + 1e-6) % 6, el = +o.el, R = +o.R;
  const pul = [0, 1, 1.5, 1, 0.3, -0.3][f];
  const Rw = R + pul * 0.6, cy = -(+o.H0);
  bell(p, 0, cy, Rw, C, X, C[6], X.ac, WHITE, { outline: false });
  p.px(0, R0(cy - Rw * 0.35), X.ac);                          // 伞里一点荧光芯
  for (let i = 0; i < 4; i++) {
    const x0 = (i / 3 - 0.5) * Rw * 1.2, L = R * 1.6 - (i % 2);
    for (let s = 1; s <= L; s++) p.px(R0(x0 + Math.sin(s * 0.7 + i * 1.9 + f * 1.05) * 0.9), R0(cy + 1 + s), s < 3 ? C[5] : i % 2 ? X.ac : C[4]);
  }
}

// 唤醒充能好：脚下一圈断续青色小环（循环，一亮一暗）
function ready(p, t, o, C, X) {
  const R = +o.R, SY = +o.SY, f = Math.floor(t * 15 + 1e-6) % 6;
  const m = Math.ceil(R * TAU);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (Math.floor((a / TAU) * 12 + f * 0.5) % 2) continue;
    p.px(R0(Math.cos(a) * R), R0(Math.sin(a) * R * SY), f < 3 ? X.cy : C[4]);
  }
}

// 扩散（升级卡溅射）：一圈细水纹往外扩、断口越来越多
function ripple(p, t, o, C, X) {
  const R = +o.R, SY = +o.SY;
  const r = 4 + (R - 4) * ease.outCubic(clamp(t / 0.22)), fade = smooth(0.1, 0.3, t);
  if (fade >= 1) return;
  const m = Math.ceil(r * TAU);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 4.3, +o.seed + 131) < 0.25 + 0.6 * fade) continue;
    p.px(R0(Math.cos(a) * r), R0(Math.sin(a) * r * SY), t < 0.07 ? C[6] : C[4]);
    p.px(R0(Math.cos(a) * (r - 1)), R0(Math.sin(a) * (r - 1) * SY), C[1]);
  }
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8);
  const X = { cy: hex(o.cyan), cyL: hex(o.cyanL), ac: hex(o.accent) };
  const gd = o.layer === "gd";
  switch (o.part) {
    case "sweep": return gd ? canopyGround(p, t, o, C, X, false) : canopy(p, t, o, C, X, { R: +o.R, W: +o.W, full: false });
    case "spin": return gd ? canopyGround(p, t, o, C, X, true) : canopy(p, t, o, C, X, { R: +o.R, W: +o.W, full: true });
    case "tent": return gd ? rift(p, t, o, C, X) : tent(p, t, o, C, X);
    case "bloom": return gd ? bloomGround(p, t, o, C, X) : bloom(p, t, o, C, X);
    case "coil": return gd ? undefined : coil(p, t, o, C, X);
    case "tring": return tring(p, t, o, C, X, gd);
    case "moon": return moon(p, t, o, C, X, gd);
    case "pool": return gd ? pool(p, t, o, C, X) : undefined;
    case "jelly": return gd ? undefined : jelly(p, t, o, C, X);
    case "ready": return gd ? ready(p, t, o, C, X) : undefined;
    case "ripple": return gd ? ripple(p, t, o, C, X) : undefined;
  }
}
