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
    if (st === "s3" && !hot && q < 0.16) out.c = X.ac;                       // 镜花水月：荧光紫刃
    if (el >= 2 && !hot && rib && q > 0.16 && q < 0.8 && st !== "s2") out.c = X.ac;   // 精二：伞骨荧光紫
    if (cool > 0.55 && nz(r * 2.3 + a * 13, +o.seed + 79) < 0.4) return 0;   // 收势最后两拍成团消散
  });
  if (raw) for (let a = tail; a <= head; a += 0.12) p.light(Math.cos(a + th) * R * 0.9, Math.sin(a + th) * R * 0.9, C[n - 2], 0.35 * (1 - cool));
  // 11-05 用户「加吸盘亮点看不出什么差距」：精一不再靠细须 / 青沿这类细节区分，改由触手（新元素）出现；伞面 E0 = E1，E2 才质变
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
      // 11-05 用户「特效范围会过大吗」：水滴只在伞面边内侧甩起、往下落，不越过判定半径（外缘 ≤ R × 1.04）
      const a = tail + (head - tail) * nz(i * 2.3, +o.seed + 301) + th, rr = R * (0.86 + 0.18 * nz(i * 1.9, +o.seed + 303) * Math.min(1, u / 0.25));
      const x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY - H0 - 30 * u + 280 * u * u;
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

// 触手形态（11-05 用户「触手是不是可以多做几个形态，现在只有一个像是钩子一样的」）：按场合用不同形态，同一形态按 v（变体）随机弯向、长短、粗细。
//   slam  拍击：从地下甩起一道弧、越过头顶拍到前方地上（普攻追击）
//   pierce 刺穿：细长尖端从地面直刺上来，一拍到顶、尖端白亮，快收（唤醒每团大水母下）
//   curl  卷须：身子像水母触须一样波浪起伏，末端卷两小圈（囚徒困境束缚，配缠绕）
//   cluster 群生：四五根细触手像水草一样摇曳着冒出来（连携）
//   big   粗拍击（镜花水月）
// 画法：沿中心线逐点按宽度横向填色（背光侧暗靛 → 深蓝 → 受光侧亮边 1 格），吸盘点精一淡色 / 精二荧光紫。
function strand(p, pts, wfn, C, X, o, opt) {
  const el = +o.el, n = C.length;
  for (let i = 0; i < pts.length; i++) {
    const [x, y, v, nx, ny] = pts[i];
    const w = wfn(v), hw = w / 2;
    for (let d = -hw; d <= hw; d += 0.5) {
      const q = (d + hw) / Math.max(0.5, w);
      let ci = q < 0.25 ? 1 : q < 0.6 ? 2 : q < 0.85 ? 3 : 5;
      if (opt.big) ci += q > 0.5 ? 1 : 0;
      let c = C[clamp(ci, 1, n - 1)];
      if (q >= 0.85 && opt.rim) c = opt.rim;
      if (opt.tipHot && v > 0.86) c = v > 0.94 ? WHITE : X.cyL;
      p.px(R0(x + nx * d), R0(y + ny * d), c);
    }
    if (el >= 1 && !opt.noSuck && v > 0.15 && v < 0.85 && i % 3 === 0) p.px(R0(x - nx * hw * 0.4), R0(y - ny * hw * 0.4), el >= 2 ? X.ac : C[n - 3]);
  }
}

// 按航向积分出中心线：从 (x0, 0) 朝上出发，第 s 段航向 = 朝上 + turn(v)
function path(x0, L, turn, ds = 0.5) {
  const pts = [];
  let x = x0, y = 0, h = -Math.PI / 2;
  const N = Math.max(2, Math.ceil(L / ds));
  for (let i = 0; i <= N; i++) {
    const v = i / N;
    const hh = -Math.PI / 2 + turn(v);
    pts.push([x, y, v, -Math.sin(hh), Math.cos(hh)]);   // 法线（横向填色方向）
    x += Math.cos(hh) * ds;
    y += Math.sin(hh) * ds;
  }
  return pts;
}

function tentForm(p, t, o, C, X) {
  const el = +o.el, form = o.form || "slam", H = +o.H, vs = +o.v || 0, sd = +o.seed + vs * 17;
  const jL = 0.85 + 0.3 * nz(1.7, sd), jW = Math.round((nz(2.9, sd) - 0.5) * 2), jB = 0.75 + 0.5 * nz(4.1, sd), sg = nz(5.3, sd) < 0.25 ? -1 : 1;
  const out = smooth(0.32, 0.47, t);   // 缩回
  if (form === "slam" || form === "big") {
    const big = form === "big", L = H * 1.25 * jL * (1 - 0.9 * out);
    const w0 = (big ? 10 : 6 + el) + jW;
    if (L < 2) return;
    const up = ease.outCubic(clamp(t / 0.1));
    const sw = smooth(0.08, 0.2, t);                       // 甩过头顶
    const Lc = L * (0.45 + 0.55 * up);
    const turn = (v) => sg * (0.15 * up + (Math.PI * 0.95 * jB) * sw) * Math.pow(v, 1.4) + Math.sin(v * 5 + sd) * 0.12;
    const pts = path(0, Lc, turn);
    strand(p, pts, (v) => Math.max(1.5, w0 * (1 - v * 0.8)), C, X, o, { big, rim: big ? null : null });
    if (t >= 0.19 && t < 0.3) {                            // 拍到地上：尖端处一圈溅起的水点
      const tip = pts[pts.length - 1];
      for (let i = 0; i < 9; i++) {
        const a = (i / 9) * Math.PI + Math.PI, r = 3 + 4 * nz(i * 1.9, sd) + (t - 0.19) * 60;
        p.px(R0(tip[0] + Math.cos(a) * r), R0(tip[1] + Math.sin(a) * r * 0.6), i % 2 ? X.cyL : C[5]);
      }
    }
    if (el >= 2 && !big) {                                 // 精二：旁边多一根卷须（第二种形态）
      tentForm(p, t - 0.05, Object.assign({}, o, { form: "curl", H: H * 0.6, el: 2, v: vs + 1, _x: -7 * sg }), C, X);
    }
    return;
  }
  if (form === "pierce") {
    const L = H * 1.15 * jL * (t < 0.067 ? 0.7 : 1) * (1 - smooth(0.2, 0.33, t));
    if (L < 2) return;
    const w0 = 4 + Math.min(1, el) + jW * 0.5, lean = sg * 0.12 * jB;
    const pts = path(+o._x || 0, L, (v) => lean + Math.sin(v * 3 + sd) * 0.04);
    strand(p, pts, (v) => Math.max(1, w0 * Math.pow(1 - v, 0.8)), C, X, o, { tipHot: t < 0.14, noSuck: true });
    if (t < 0.067) for (let i = 0; i < 6; i++) {           // 破土碎点
      const a = Math.PI + (i / 5) * Math.PI;
      p.px(R0(Math.cos(a) * (4 + i)), R0(Math.sin(a) * 2), C[4]);
    }
    return;
  }
  if (form === "curl") {
    const L = H * 1.2 * jL * ease.outCubic(clamp(t / 0.12)) * (1 - 0.92 * out);
    if (L < 2) return;
    const w0 = 4 + Math.min(1, el) + jW * 0.5, ph = t * 12 + sd;
    const turn = (v) => sg * (0.55 * jB * Math.sin(v * 6 - ph) * Math.min(1, v * 1.6) + (v > 0.72 ? Math.pow((v - 0.72) / 0.28, 1.3) * Math.PI * 1.7 : 0));
    const pts = path(+o._x || 0, L, turn, 0.4);
    strand(p, pts, (v) => Math.max(1.2, v > 0.72 ? 2.2 * (1 - (v - 0.72) / 0.28) + 0.8 : w0 * (1 - v * 0.55)), C, X, o, {});
    return;
  }
  if (form === "cluster") {
    const N = 4 + (vs % 2);
    for (let k = 0; k < N; k++) {
      const x0 = (k / (N - 1) - 0.5) * 18 + (nz(k * 2.3, sd) - 0.5) * 4;
      const tt = t - 0.025 * ((k * 3) % N);
      if (tt < 0) continue;
      const L = H * (0.55 + 0.45 * nz(k * 3.7, sd)) * ease.outCubic(clamp(tt / 0.12)) * (1 - 0.9 * smooth(0.32, 0.5, tt));
      if (L < 2) continue;
      const ph = tt * 10 + k * 1.9;
      const s2 = nz(k * 5.1, sd) < 0.5 ? -1 : 1;
      const pts = path(x0, L, (v) => s2 * (0.35 * Math.sin(v * 4 - ph) * v + 0.25 * v) + (x0 / 18) * 0.5 * v, 0.5);
      strand(p, pts, (v) => Math.max(1, 3.2 * (1 - v * 0.7)), C, X, o, { rim: X.cyL, noSuck: k % 2 === 1 });
    }
  }
}

function tent(p, t, o, C, X) {
  tentForm(p, t, o, C, X);
  if (o.view === "raw") p.light(0, -(+o.H) * 0.5, C[5], 0.4);
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

// 海月水母（11-05 用户「水月的水母应该是海月水母」）：扁平的碟形伞、半透明；伞里四个马蹄形生殖腺环（海月的招牌）；
// 伞沿一圈细短的缘须；中央垂下四条带褶边的短口腕（不是长垂须）。俯视斜角看：伞顶在上、伞沿略往下垂、生殖腺环按 3/4 视角压扁。
// cfg：body 伞体色、alpha 伞体透明度（真半透明，不抖动）、rim 伞缘 / 轮廓色、top 伞顶高光、gon 生殖腺环色、arm 口腕色、armK 口腕长 / R、
//      outline 只剩轮廓 + 生殖腺（消散那两拍）、ph 口腕摆动相位、fringe 缘须
function aurelia(p, cx, cy, R, C, X, cfg) {
  const hh = Math.max(2, R * 0.46), sag = R * 0.08;
  const topY = (u) => cy - hh * Math.pow(Math.max(0, 1 - u * u), 0.6);
  const botY = (u) => cy + sag * (1 - u * u);
  // 伞体
  for (let x = -R; x <= R; x++) {
    const u = x / R, y0 = R0(topY(u)), y1 = R0(botY(u));
    for (let y = y0; y <= y1; y++) {
      const edge = y === y0 || y === y1 || Math.abs(x) >= R - 0.5;
      if (edge) { p.px(R0(cx + x), y, cfg.rim); continue; }
      if (cfg.outline) continue;
      const hi = y <= y0 + 1 && u < -0.1 && u > -0.65;            // 伞顶左侧一道高光
      if (hi) p.px(R0(cx + x), y, cfg.top);
      else p.blend(R0(cx + x), y, cfg.body, cfg.alpha);
    }
  }
  // 四个马蹄形生殖腺环（环口朝中心）
  const gy = cy - hh * 0.42, rgx = R * 0.3, rgy = hh * 0.42, rh = Math.max(0.8, R * 0.16);   // 四环成苜蓿形（上下左右各一，3/4 视角压扁）
  for (let k = 0; k < 4; k++) {
    const a = (k / 4) * TAU, gx = cx + Math.cos(a) * rgx, gyy = gy + Math.sin(a) * rgy;
    if (rh < 1.2) { p.px(R0(gx), R0(gyy), cfg.gon); continue; }
    for (let b = 0; b < TAU; b += 0.35 / rh) {
      const rel = ((b - (a + Math.PI)) % TAU + TAU) % TAU;
      if (rel < 0.6 || rel > TAU - 0.6) continue;                 // 环口朝中心（马蹄形）
      p.px(R0(gx + Math.cos(b) * rh), R0(gyy + Math.sin(b) * rh * 0.7), cfg.gon);
    }
  }
  // 缘须：伞沿一圈细短须
  if (cfg.fringe !== false) for (let x = -R + 1; x <= R - 1; x++) {
    const u = x / R, y = R0(botY(u)) + 1, L = R >= 8 ? 1 + ((x + 9) % 2) : 1;
    for (let s = 0; s < L; s++) p.px(R0(cx + x), y + s, s ? C[4] : cfg.rim);
  }
  // 口腕：中央四条带褶边的短腕
  const ph = cfg.ph || 0, L = Math.max(2, R * (cfg.armK || 0.7));
  for (let i = 0; i < 4; i++) {
    const x0 = cx + (i / 3 - 0.5) * R * 0.5;
    for (let s = 1; s <= L; s++) {
      const x = x0 + Math.sin(s * 0.6 + i * 1.7 + ph) * (0.6 + s / L);
      const y = botY(0) + s;
      p.px(R0(x), R0(y), cfg.arm);
      if (R >= 9 && s % 3 === 1) p.px(R0(x + (i < 2 ? -1 : 1)), R0(y), cfg.outline ? C[3] : cfg.rim);   // 褶边
    }
  }
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
  // 海月水母：精零 / 精一生殖腺淡紫白，精二荧光紫（发光）；唤醒的大水母口腕更长
  const gon = el >= 2 || st === "sting" ? X.ac : C[5];
  aurelia(p, 0, cy, Rk, C, X, { body: dim ? C[4] : cyan, alpha: dim ? 0.4 : 0.62, rim: dim ? C[3] : cyanL, top: WHITE, gon: dim && el < 2 ? C[4] : gon,
    arm: dim ? C[3] : (st === "burst" ? cyanL : C[5]), armK: (st === "burst" ? 0.85 : 0.6) + 0.1 * el, outline: f >= 4, ph: f * 1.1 });
  if (raw) p.light(0, cy - Rk * 0.3, cyan, 0.6 * (1 - f / 6));
}

// 地上：唤醒创伤扩散的冲击环（只画边：2 格亮边 + 2 格深色内边，有断口，往外扩）/ 普攻命中小湿印
function bloomGround(p, t, o, C, X) {
  if (o.view === "raw") return;
  const SY = +o.SY, st = o.style || "hit", R = +o.R;
  if (st !== "burst") return;
  const Rg = R * 2.0 * ease.outCubic(clamp(t / 0.2));   // 判定 burst r 80 → 美术 40；精二 R 20 × 2.0 = 40（不超）
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
  // 精二：再一根反向缠的触手（两股交叉对缠，形状变化，不只是换色）
  if (el >= 2) for (let a = 0; a < TURN; a += 0.5 / rx) {
    const z = 8 - (a / TURN) * 5, s2 = Math.sin(-a + 0.8), front = s2 > 0;
    if ((half === "front") !== front) continue;
    const x = Math.cos(-a + 0.8) * (rx + 1), y = s2 * ry - z;
    for (let d = 0; d < 2.5; d += 0.5) p.px(R0(x), R0(y + d - 1.2), C[d < 0.8 ? 1 : front ? 4 : 2]);
    if (front && Math.floor(a * 3) % 4 === 1) p.px(R0(x), R0(y), X.ac);
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
    const form = ["slam", "pierce", "curl", "cluster"][(items.indexOf(it) + +o.seed) % 4];   // 一圈里各种形态混着出（不复制粘贴）
    tentForm({ px: (x, y, c) => p.px(x + R0(it.x), y + R0(it.y), c) }, t - it.dt, Object.assign({}, o, { form, H: H * (form === "cluster" ? 0.8 : 1), v: items.indexOf(it) % 3 }), C, X);
    void lean;
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
  aurelia(p, 0, -rise, Rb + 4, C, X, { body: dim ? C[4] : X.cy, alpha: dim ? 0.4 : 0.6, rim: dim ? X.ac : X.cyL, top: WHITE, gon: X.ac,
    arm: dim ? C[4] : X.cyL, armK: 1.25, outline: t > 0.47, ph: t * 12 });   // 一只大海月水母浮起（四个荧光紫生殖腺环、长褶口腕）
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
  aurelia(p, 0, cy, Rw + 1, C, X, { body: C[6], alpha: 0.7, rim: C[5], top: WHITE, gon: X.ac, arm: C[5], armK: 1.0, ph: f * 1.05 });   // 小海月水母
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
