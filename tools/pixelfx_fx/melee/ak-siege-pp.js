// 推进之王「转平面」（docs/264，开关 fx/px_plane，照 docs/246 斯卡蒂 / docs/254 星熊的做法）：pixelfx 画法，按本作俯视斜角重画。
// 一个文件按 part 出各件；每件分两层（layer）：
//   up 立起层 —— 离地的东西（下砸锤弧、落点白闪、火星线、碎石、尘墙、岩刺、冲柱），原点 = 脚底 / 落点地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（裂网、砸坑、冲击环、地裂、尘印），已按 SY（0.72）压扁，画在地面层。
// 1 像素 = 1 美术像素 = 2 世界像素，游戏里只按 2 倍整数放大、不旋转；方向件按 dir（−90 / −45 / 0 / 45 / 90°）逐向生成，另一半水平翻转。
// view: "raw" 出「旧做法」对照：正俯视 / 正圆、光晕烤进颜色，游戏里旋转 + 小数缩放贴。
// 色：本人金（游戏代表色 #ffc759 一组，熔金 8 阶；不用危险红）；尘 / 碎石暖土；精二点缀白金熔芯 #fff1b8（裂缝冷得慢、一直透亮）。
// 力量感照「裂地 v3」（11-05 用户认可）：不规整的分叉裂网、爆亮后冷却、隆起的尘墙；不画规整放射线 / 同心圈。
import { fit, clamp, smooth, ease, noise, TAU, hex, WHITE } from "../../core/index.js";

export const meta = {
  name: "Siege plane",
  desc: "Siege's hammer smashes, rally shout, aerial hammer slam, skull breaker, ground fissures with rock spikes, hammer shockwaves and the charge-in link slam, redrawn for a 3/4 top-down plane.",
  tags: ["melee", "impact", "topdown", "siege", "one-shot"],
  size: [320, 280],
  origin: [160, 170],
  duration: 1.0,
  loop: false,
  fps: 15,   // 统一动画时钟：本作特效帧条一律 15 fps
  bg: "dark",
  options: {
    palette: ["#1a0c05", "#3a1c0a", "#6b3812", "#a85e1a", "#e08e26", "#ffbf3c", "#ffe9a0", "#ffffff"],
    dust: ["#1a1510", "#2e261c", "#4a3e2e", "#6e5f48", "#9a8a6a"],
    stone: ["#17130f", "#2b241c", "#463b2e", "#665747", "#8f7f69", "#bcae94"],
    accent: "#fff1b8",
    part: "arc",
    layer: "up",
    view: "plane",
    style: "atk",
    R: 46, dir: 0, el: 0, SY: 0.72, L: 90, S: 10, dur: 0.34, seed: 3,
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1

// ---------------------------------------------------------------- 下砸锤弧（普攻 / S1 强化一锤 / S3 碎颅）：竖直面里从身后上方砸到身前落点
// 投影：沿出手方向 s、离地高 z → 屏幕 (dx·s + nx·w, dy·s + ny·w − z)；w = 锤头宽度方向（横向厚度），正对 / 背对镜头时也看得出一道宽弧
function arcGeo(o) {
  const R = +o.R, Lr = R * 0.7, zc = 16, rho = Math.hypot(Lr, zc);
  return { Lr, zc, rho, A0: 100 * D2R, A1: Math.atan2(-zc, Lr) };
}

function arcBand(p, t, o, C, ACC, ghost, dimK) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, st = o.style || "atk";
  const { zc, rho, A0, A1 } = arcGeo(o);
  const hotT = st === "atk" ? 0.067 : 0.134;                         // S1 / S3：热白多停一拍
  const W = (st === "s3" ? 12 : st === "s1" ? [9, 10, 11][el] : [6, 7, 8][el]) * (ghost ? 0.6 : 1);
  const HW = st === "s3" ? 5 : st === "s1" ? 4 : [2, 3, 3][el];
  const head = A0 + (A1 - A0) * (0.55 + 0.45 * clamp(t / 0.067));
  const tail = A0 + (A1 - A0) * (0.25 + 0.6 * smooth(hotT, +o.dur, t));   // 刀尾从上往下吃，上半段从不画满
  const hot = t < hotT && !ghost, cool = smooth(hotT, +o.dur, t);
  if (cool >= 0.65 || tail - head < 0.05) return;
  const dx = Math.cos(th), dy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  for (let a = tail; a >= head; a -= 0.5 / rho) {
    const u = (tail - a) / Math.max(0.001, tail - head);            // 0 锤尾 → 1 锤头（落点）
    const wr = W * (1 - 0.6 * cool) * Math.min(1, Math.pow(u / 0.6, 0.8));
    if (wr < 0.8) continue;
    const hw = HW * Math.min(1, 0.35 + u);
    for (let q = 0; q <= 1; q += 0.5 / wr) {
      const r = rho - q * wr, s = r * Math.cos(a), z = zc + r * Math.sin(a);
      if (z < -0.5) continue;
      if (q > 0.78 && ((Math.round(a * rho * 2) + Math.round(q * wr * 2)) & 1)) continue;   // 内沿抖动变稀，不平涂
      let ci = q < 0.2 ? (hot ? n - 1 : n - 2) : q < 0.5 ? n - 3 : q < 0.8 ? n - 4 : n - 5;
      if (q > 0.2 && q < 0.8 && nz(r * 0.8 + o.seed, o.seed + 91) > 0.72) ci += 1;     // 速度纹
      if (hot && u > 0.82 && q < 0.45) ci = n - 1;                   // 锤头热白
      ci = clamp(ci - Math.round(cool * 1.6) - (u < 0.25 ? 1 : 0) - dimK, 1, n - 1);
      let c = C[ci];
      if (el >= 2 && !hot && !ghost && q > 0.15 && q < 0.3) c = ACC;  // 精二：白金熔芯副刃
      for (let w = -hw; w <= hw; w += 1) {
        const edge = Math.abs(w) > hw - 1;
        p.px(Math.round(dx * s + nx * w), Math.round(dy * s + ny * w - z), edge && ci > 1 ? C[clamp(ci - 1, 1, n - 1)] : c);
      }
    }
  }
  if (raw) for (let a = tail; a >= head; a -= 0.15) p.light(Math.cos(a) * rho, -zc - rho * Math.sin(a), C[n - 2], 0.4 * (1 - cool));
}

function arc(p, t, o, C, ACC) {
  arcBand(p, t, o, C, ACC, false, 0);
}

// ---------------------------------------------------------------- 分叉裂网（裂地 v3：不规整、分叉、近落点宽）
function crackPaths(o, R, N, sd, fwd, spread) {
  const paths = [];
  for (let j = 0; j < N; j++) {
    let a = fwd === undefined ? TAU * (j + (nz(j * 1.7, sd + 701) - 0.5) * 0.7) / N : fwd + (j / Math.max(1, N - 1) - 0.5) * 2 * spread + (nz(j * 1.7, sd + 701) - 0.5) * 0.25;
    let x = Math.cos(a) * 3, y = Math.sin(a) * 3;
    const L = R * (0.5 + 0.45 * nz(j * 2.9, sd + 703));
    const pts = [[x, y, 0]];
    for (let s = 0; s < L; s += 1) {
      a += (nz(s * 0.25 + j * 11, sd + 705) - 0.5) * 0.36;
      x += Math.cos(a); y += Math.sin(a);
      pts.push([x, y, s / L]);
    }
    paths.push(pts);
    if (nz(j * 4.1, sd + 707) > 0.35) {   // 分叉
      const k = Math.floor(pts.length * (0.3 + 0.35 * nz(j * 5.3, sd + 709)));
      let [bx, by] = pts[k], ba = a + (nz(j * 6.7, sd + 711) > 0.5 ? 0.85 : -0.85);
      const bp = [[bx, by, pts[k][2]]], BL = L * (0.3 + 0.2 * nz(j, sd + 713));
      for (let s2 = 0; s2 < BL; s2++) { ba += (nz(s2 * 0.3 + j * 7, sd + 715) - 0.5) * 0.4; bx += Math.cos(ba); by += Math.sin(ba); bp.push([bx, by, pts[k][2] + s2 / L]); }
      paths.push(bp);
    }
  }
  return paths;
}

// 裂缝着色：白热 → 淡金 → 金 → 琥珀 → 冷成暗土、断成一节节；精二熔芯冷得慢（一直透一线白金）
function drawCracks(p, t, o, C, ACC, DU, paths, SY, molten, t0) {
  const n = C.length, u = t - (t0 || 0);
  if (u < 0) return;
  const grow = clamp(u / 0.1), fade = smooth(molten ? 0.35 : 0.22, molten ? 0.8 : 0.62, u);
  if (fade >= 0.99) return;
  for (const pts of paths) {
    for (const [x, y, f] of pts) {
      if (f > grow * 1.05) break;
      if (nz(f * 40 + x * 0.7, o.seed + 717) < fade * 0.92) continue;
      const X = Math.round(x), Y = Math.round(y * SY);
      let c;
      if (molten) c = u < 0.067 ? WHITE : u < 0.3 ? ACC : u < 0.5 ? C[n - 2] : u < 0.65 ? C[n - 4] : DU[1];
      else c = u < 0.067 ? WHITE : u < 0.16 ? C[n - 2] : u < 0.3 ? C[n - 4] : u < 0.42 ? C[n - 6] : DU[1];
      p.px(X, Y, c);
      if (f < 0.45 && u < 0.4) p.px(X, Y + 1, DU[0]);                 // 近落点那一截更宽（下沿压暗）
    }
  }
}

function crater(p, t, o, DU, rx, SY, a0) {
  const fade = smooth(0.15, 0.7, t);
  if (fade >= 0.97) return;
  p.shade(-rx - 1, -rx * SY - 1, rx + 1, rx * SY + 1, (x, y, out) => {
    const d = Math.hypot(x / rx, y / (rx * SY));
    if (d > 1) return;
    out.c = d > 0.8 && y < 0 ? DU[3] : DU[0];                         // 坑口上沿一圈受光土
    out.a = (a0 || 0.55) * (1 - fade) * (1 - d * 0.4);
  });
}

// ---------------------------------------------------------------- 贴地冲击环（断续、不规整，外缘亮、内侧一圈 2 格深色内边，没有整片填充）
function ring(p, t, o, C, R, SY, t0, thick) {
  const n = C.length, u = t - (t0 || 0);
  if (u < 0) return;
  const g = ease.outCubic(clamp(u / 0.2)), r = R * (0.35 + 0.65 * g), fade = smooth(0.14, 0.45, u);
  if (fade >= 0.995) return;
  const th = (thick || 2) + (1 - g) * 2, m = Math.ceil(r * TAU * 1.3);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, ca = Math.cos(a), sa = Math.sin(a);
    const rr = r + 1.6 * nz(a * 5, o.seed + 11) + 1.0 * nz(a * 13, o.seed + 17);
    if (nz(a * 3.1, o.seed + 23) < 0.2 + fade * 0.5) continue;      // 断口
    for (let k = 0; k < th; k += 0.5) {
      const q = k / th;
      let ci = q < 0.3 ? n - 2 : q < 0.7 ? n - 3 : n - 5;
      if (u < 0.07 && q < 0.4) ci = n - 1;
      if (sa < -0.2) ci -= 1;
      ci = clamp(ci - Math.round(fade * 2.5), 1, n - 1);
      p.dot(Math.round(ca * (rr - k)), Math.round(sa * (rr - k) * SY), C[ci], 1 - fade * 0.6);
    }
    if (fade < 0.7) for (let k = 0; k < 2; k += 0.5) {
      const r2 = rr - th - 1 - k;
      p.px(Math.round(ca * r2), Math.round(sa * r2 * SY), C[1]);
    }
  }
}

// ---------------------------------------------------------------- 立起层的碎件：火星线、碎石、尘墙、白闪
function streaks(p, t, o, C, N, spd, sd, t0, up) {
  const n = C.length, SY = +o.SY;
  for (let i = 0; i < N; i++) {
    const u = t - (t0 || 0) - 0.01 * (i % 3);
    const life = 0.28 + 0.16 * nz(i * 2.3, sd + 301);
    if (u <= 0 || u > life) continue;
    const a = TAU * nz(i * 1.9, sd + 303), v = spd * (0.6 + 0.6 * nz(i * 3.1, sd + 305)), vz = (up || 60) * (0.5 + nz(i * 4.7, sd + 307));
    const gx = Math.cos(a) * v * u, gy = Math.sin(a) * v * u * SY, z = Math.max(0, 4 + vz * u - 260 * u * u);
    const X = gx, Y = gy - z;
    const tx = Math.cos(a) * v, ty = Math.sin(a) * v * SY - (vz - 520 * u);    // 当前速度方向 → 拖成一道细线（原作放射状细长火星）
    const tl = Math.hypot(tx, ty) || 1, Ls = u < 0.1 ? 5 : 3;
    const c = u < 0.067 ? WHITE : u < life * 0.5 ? C[n - 2] : C[n - 3];
    for (let k = 0; k < Ls; k++) p.px(Math.round(X - tx / tl * k), Math.round(Y - ty / tl * k), k === 0 ? c : C[n - 4]);
  }
}

function rubble(p, t, o, ST, DU, N, R, sd, t0, hotC) {
  const SY = +o.SY, u = t - (t0 || 0.03);
  if (u <= 0) return;
  for (let i = 0; i < N; i++) {
    const a = TAU * nz(i * 2.3, sd + 601), rr = R * (0.15 + 0.6 * nz(i * 1.9, sd + 603));
    const high = i % 4 === 0;
    const vy = (high ? 150 : 80) + 70 * nz(i * 3.7, sd + 605), vr = 18 + 30 * nz(i * 4.3, sd + 607);
    const gx = Math.cos(a) * (rr + vr * u), gy = Math.sin(a) * (rr + vr * u) * SY;
    const z = vy * u - 360 * u * u;
    if (z < 0) continue;
    const sz = high ? 3 : nz(i * 6.1, sd + 609) > 0.5 ? 3 : 2, X = Math.round(gx), Y = Math.round(gy - z);
    for (let dx = 0; dx < sz; dx++) for (let dy = 0; dy < sz - (dx === sz - 1 ? 1 : 0); dy++) {
      let c = dy === 0 ? ST[4] : dx === 0 ? ST[3] : ST[2];                 // 光从左上来
      if (hotC && dy === 0 && dx === 0 && u < 0.25) c = hotC;               // 精二：碎石带一点熔金
      p.px(X + dx, Y + dy, c);
    }
  }
}

function dustWall(p, t, o, DU, R, m, hMax, sd, t0) {
  const SY = +o.SY, u = t - (t0 || 0.04);
  if (u <= 0 || u > 0.5) return;
  for (let j = 0; j < m; j++) {
    const a = TAU * (j + nz(j * 1.3, sd + 611) * 0.7) / m;
    const h = hMax * (0.45 + 0.55 * nz(j * 2.1, sd + 613)) * ease.outCubic(clamp(u / 0.2));
    const gx = Math.cos(a) * R * (0.88 + 0.16 * nz(j, sd + 615)), gy = Math.sin(a) * R * SY;
    const rr = 2 + (nz(j * 3.7, sd + 619) > 0.5 ? 1 : 0) + (u > 0.15 ? 1 : 0) - (u > 0.3 ? 1 : 0) - (u > 0.4 ? 1 : 0);   // 冒起来变大，散的时候缩小（不撒网点）
    if (rr < 1 || (u > 0.3 && nz(j * 7.7, sd + 621) < (u - 0.3) * 6)) continue;
    for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr; dx <= rr; dx++) {
      if (dx * dx + dy * dy > rr * rr + 0.5) continue;
      p.px(Math.round(gx + dx), Math.round(gy - h + dy), dy < 0 ? DU[4] : DU[3]);
    }
  }
}

function flash(p, t, C, rx, ry, z, t0) {
  const n = C.length, u = t - (t0 || 0);
  if (u < 0 || u >= 0.134) return;
  const k = u < 0.067 ? 1 : 0.55;
  const RX = rx * k, RY = ry * k;
  p.shade(-RX - 1, -z - RY - 1, RX + 1, -z + RY + 1, (x, y, out) => {
    const d = Math.hypot(x / RX, (y + z) / RY);
    if (d > 1) return;
    out.c = d < 0.55 ? (u < 0.067 ? WHITE : C[n - 2]) : C[n - 3];
    out.a = 1;
  });
  if (u < 0.067) for (let s = 0; s < ry * 3.2; s++) {                         // 一道竖直刺芒（砸地那一下往上冲）
    p.px(0, Math.round(-z - RY - s), s < ry * 1.6 ? WHITE : C[n - 2]);
  }
}

// ---------------------------------------------------------------- 普攻 / S1 强化一锤 的落点（立起层：白闪 + 火星线 + 碎石 + 尘墙；贴地层：裂网 + 砸坑 + 冲击环）
function impUp(p, t, o, C, ACC, ST, DU) {
  const el = +o.el, s1 = o.style === "s1", k = s1 ? 1.4 : 1;
  flash(p, t, C, (7 + 2 * el) * k, (3 + el) * k, 3, 0.0);
  streaks(p, t, o, C, ([6, 8, 10][el] + (s1 ? 4 : 0)), 120 * k, o.seed, 0.0, 60);
  if (el >= 1 || s1) rubble(p, t, o, ST, DU, (s1 ? 7 : 4) + 2 * el, (16 + 4 * el) * k, o.seed + 5, 0.03, el >= 2 ? ACC : null);
  if (el >= 1 || s1) dustWall(p, t, o, DU, (14 + 4 * el) * k, 10 + 3 * el, (6 + 2 * el) * k, o.seed + 7, 0.05);   // 精一起：隆起的尘墙
}

function impGd(p, t, o, C, ACC, DU) {
  const el = +o.el, s1 = o.style === "s1", k = s1 ? 1.4 : 1, SY = +o.SY;
  const raw = o.view === "raw";
  const sy = raw ? 1 : SY;
  crater(p, t, o, DU, (6 + 2 * el) * k, sy, 0.6);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, [18, 24, 30][el] * k, [4, 6, 8][el] + (s1 ? 2 : 0), o.seed + 41), sy, el >= 2, 0.0);
  if (s1) ring(p, t, o, C, 34 + 6 * el, sy, 0.02, 3);                         // S1 号令一锤：落点一圈金色冲击环（S1 的标志）
  if (raw) p.glow && p.glow(0, 0, 24 * k, C[C.length - 2], 0.6 * (1 - smooth(0.05, 0.3, t)));
}

// ---------------------------------------------------------------- S3 碎颅：落点横向扁白闪 + 向前分叉的地裂扇（原作 S3 hit）
function s3Up(p, t, o, C, ACC, ST, DU) {
  flash(p, t, C, 22, 4, 5, 0.0);
  streaks(p, t, o, C, 12, 150, o.seed + 3, 0.0, 70);
  rubble(p, t, o, ST, DU, 9, 22, o.seed + 9, 0.03, ACC);
  dustWall(p, t, o, DU, 22, 14, 10, o.seed + 13, 0.05);
}

function s3Gd(p, t, o, C, ACC, DU) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, th = raw ? 0 : +o.dir * D2R;
  crater(p, t, o, DU, 11, SY, 0.65);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, 58, 7, o.seed + 51, Math.atan2(Math.sin(th), Math.cos(th)), 0.55), SY, true, 0.0);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, 16, 4, o.seed + 57), SY, true, 0.0);
  if (raw) p.glow && p.glow(0, 0, 30, C[C.length - 2], 0.7 * (1 - smooth(0.05, 0.35, t)));
}

// ---------------------------------------------------------------- S2 跃空锤落地：竖直冲柱（原作）+ 碎石 + 尘墙；贴地大裂网 + 冲击环 + 砸坑。精二：冲柱白金芯、裂缝更密且熔芯冷得慢、碎石带熔金、第二圈尘墙
function pillar(p, t, C, ACC, H, W, el) {
  const n = C.length, u = t - 0.0;
  if (u >= 0.27) return;
  const k = u < 0.067 ? 1 : u < 0.134 ? 0.8 : u < 0.2 ? 0.55 : 0.3;
  const h = H * (u < 0.067 ? 0.75 : 1), w0 = W * k;
  for (let z = 0; z < h; z += 1) {
    const q = z / h, hw = w0 * (1 - 0.75 * q);
    for (let x = -hw; x <= hw; x += 1) {
      const e = Math.abs(x) / Math.max(0.5, hw);
      if (u > 0.134 && ((Math.round(x) + Math.round(z)) & 1) && e > 0.4) continue;
      let c = e < 0.35 ? (u < 0.134 ? WHITE : C[n - 2]) : e < 0.7 ? C[n - 2] : C[n - 3];
      if (el >= 2 && e >= 0.35 && e < 0.6 && u >= 0.067) c = ACC;
      p.px(Math.round(x), Math.round(-z), c);
    }
  }
}

function slamUp(p, t, o, C, ACC, ST, DU) {
  const R = +o.R, el = +o.el;
  pillar(p, t, C, ACC, R * 1.15, 9 + 2 * el, el);
  flash(p, t, C, 11, 4, 4, 0.0);
  streaks(p, t, o, C, 10 + 4 * el, 170, o.seed + 1, 0.0, 90);
  rubble(p, t, o, ST, DU, 12 + 4 * el, R * 0.8, o.seed + 3, 0.03, el >= 2 ? ACC : null);
  dustWall(p, t, o, DU, R * 0.95, 16 + 4 * el, 10 + 3 * el, o.seed + 5, 0.06);
  if (el >= 2) dustWall(p, t, o, DU, R * 0.55, 12, 8, o.seed + 6, 0.12);   // 精二：第二圈尘墙（晚一拍）
}

function slamGd(p, t, o, C, ACC, DU) {
  const R = +o.R, el = +o.el, raw = o.view === "raw", SY = raw ? 1 : +o.SY;
  crater(p, t, o, DU, R * 0.24, SY, 0.7);
  ring(p, t, o, C, R, SY, 0.0, 3);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, R * 0.95, [9, 9, 13][el], o.seed + 61), SY, el >= 2, 0.0);   // 精二：裂缝更密、熔芯冷得慢
  if (raw) p.glow && p.glow(0, 0, R * 0.6, C[C.length - 2], 0.7 * (1 - smooth(0.05, 0.4, t)));
}

// ---------------------------------------------------------------- 震地 / 狮吼（成长节点）：落点一圈贴地冲击环 + 环边尘团；狮吼双环、更厚、尘多
function quake(p, t, o, C, ACC, DU) {
  const R = +o.R, SY = +o.SY, roar = o.style === "roar";
  ring(p, t, o, C, R, SY, 0.0, roar ? 3 : 2);
  if (roar) ring(p, t, Object.assign({}, o, { seed: +o.seed + 40 }), C, R * 0.7, SY, 0.04, 2);
  const u = t - 0.05, m = roar ? 8 : 5;
  if (u > 0 && u < 0.4) for (let j = 0; j < m; j++) {                         // 环边尘团（贴地，往外滑开、越来越稀）
    const a = TAU * (j + nz(j * 1.7, o.seed + 81) * 0.6) / m, rr = R * (0.6 + 0.5 * ease.outCubic(clamp(u / 0.3)));
    const cx = Math.cos(a) * rr, cy = Math.sin(a) * rr * SY, r0 = 3 + (u > 0.15 ? 1 : 0) - (u > 0.28 ? 2 : 0);
    for (let dy = -r0; dy <= r0; dy++) for (let dx = -r0 * 1.5; dx <= r0 * 1.5; dx++) {
      if ((dx * dx) / 2.25 + dy * dy > r0 * r0) continue;
      if (u > 0.2 && nz(j * 5.3, o.seed + 1013) < (u - 0.2) * 4) continue;   // 散掉：整团消失（不撒网点）
      p.px(Math.round(cx + dx), Math.round(cy + dy), dy < 0 ? DU[3] : DU[2]);
    }
  }
}

// ---------------------------------------------------------------- 精一「粉碎」：击倒处碎石迸开（立起）+ 小裂星（贴地）
function crushUp(p, t, o, C, ACC, ST, DU) {
  flash(p, t, C, 5, 3, 6, 0.0);
  rubble(p, t, o, ST, DU, 8, 10, o.seed + 21, 0.02, C[C.length - 3]);
}
function crushGd(p, t, o, C, ACC, DU) {
  crater(p, t, o, DU, 5, +o.SY, 0.5);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, 13, 5, o.seed + 23), +o.SY, false, 0.0);
}

// ---------------------------------------------------------------- 狮吼撞击：小白闪 + 四点火星（立起）+ 小冲击环（贴地）
function crashUp(p, t, o, C) {
  flash(p, t, C, 6, 3, 8, 0.0);
  streaks(p, t, o, C, 5, 90, o.seed + 31, 0.0, 40);
}
function crashGd(p, t, o, C) { ring(p, t, o, C, 11, +o.SY, 0.0, 2); }

// ---------------------------------------------------------------- 精二「破阵」地裂（方向件，原点 = 锤落点）：一道锯齿直裂往前裂开，白热 → 白金熔芯 → 冷却断节；两侧短枝
function fisPath(o) {
  const L = +o.L, pts = [];
  let y = 0;
  for (let x = 0; x <= L; x += 1) {
    y += (nz(x * 0.21, o.seed + 901) - 0.5) * 1.3;
    y *= 0.93;
    pts.push([x, y, x / L]);
  }
  const br = [];
  for (let k = 0; k < Math.floor(L / 16); k++) {                             // 侧枝：不等距、两侧交替
    const i0 = Math.floor((k + 0.4 + 0.4 * nz(k, o.seed + 903)) * 16), sgn = k % 2 ? 1 : -1;
    if (i0 >= pts.length) break;
    let [bx, by] = pts[i0], ba = sgn * (0.7 + 0.4 * nz(k * 2, o.seed + 905)) + 0.3;
    const bp = [];
    for (let s = 0; s < 4 + 5 * nz(k * 3, o.seed + 907); s++) { ba += (nz(s + k * 9, o.seed + 909) - 0.5) * 0.4; bx += Math.cos(ba); by += Math.sin(ba); bp.push([bx, by, pts[i0][2]]); }
    br.push(bp);
  }
  return [pts, br];
}

function fisGd(p, t, o, C, ACC, DU) {
  const SY = +o.SY, th = +o.dir * D2R, n = C.length, molten = o.style !== "crk";
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const grow = clamp(t / 0.08), fade = smooth(0.3, 0.62, t);
  if (fade >= 0.99) return;
  const [pts, br] = fisPath(o);
  const P = (x, y) => [Math.round(fx * x + nx * y), Math.round(fy * x + ny * y)];
  for (const [x, y, f] of pts) {
    if (f > grow) break;
    if (nz(f * 50, o.seed + 911) < fade * 0.9) continue;
    const w = f < 0.85 ? 1 : 0;
    for (let k = -1 - w; k <= 1 + w; k++) {                                   // 裂口：中间亮芯，两侧暗边
      const [X, Y] = P(x, y + k * 0.8);
      const core = Math.abs(k) === 0;
      let c = core ? (t < 0.067 ? WHITE : molten ? (t < 0.3 ? ACC : t < 0.45 ? C[n - 3] : DU[1]) : (t < 0.2 ? C[n - 2] : t < 0.35 ? C[n - 4] : DU[1])) : DU[0];
      p.px(X, Y, c);
    }
  }
  for (const bp of br) for (const [x, y, f] of bp) {
    if (f > grow || nz(f * 30 + x, o.seed + 913) < fade) continue;
    const [X, Y] = P(x, y);
    p.px(X, Y, t < 0.2 ? C[n - 3] : DU[1]);
  }
}

// 岩刺（精二破阵）：沿地裂每 18 美术像素（36 世界）冒出一根，拔起 → 停 → 缩回，逐根错开；暗石身左上受光、刺尖一线熔金
function fisUp(p, t, o, C, ACC, ST) {
  const SY = +o.SY, th = +o.dir * D2R, L = +o.L, n = C.length;
  const fx = Math.cos(th), fy = Math.sin(th) * SY;
  const N = Math.max(1, Math.floor(L / 18));
  for (let k = 0; k < N; k++) {
    const u = t - 0.1 - 0.012 * k;
    if (u < 0) continue;
    const s = 18 * (k + 0.5), side = (nz(k, o.seed + 921) - 0.5) * 4;
    const gx = fx * s - Math.sin(th) * side, gy = fy * s + Math.cos(th) * SY * side;
    const H = 9 + 5 * nz(k * 2.3, o.seed + 923), W = 4 + Math.round(1.5 * nz(k * 3.1, o.seed + 925));
    const up = ease.outCubic(clamp(u / 0.07)), sink = ease.inQuad(clamp((u - 0.32) / 0.16));
    const h = H * up * (1 - sink);
    if (h < 1) continue;
    const lean = (nz(k * 4.4, o.seed + 927) - 0.5) * 0.4;
    for (let z = 0; z <= h; z += 0.5) {
      const q = z / h, hw = W * Math.pow(1 - q, 0.85);
      const cx = gx + lean * z;
      for (let x = Math.round(cx - hw); x <= Math.round(cx + hw); x++) {
        const sd = (x - cx) / Math.max(0.5, hw);
        let c = sd < -0.3 ? ST[4] : sd < 0.35 ? ST[3] : ST[1];
        if (q > 0.86) c = u < 0.1 ? WHITE : C[n - 2];                          // 刺尖一点熔金
        else if (Math.abs(sd) < 0.2 && q > 0.3 && u < 0.3) c = C[n - 3];      // 中缝一线金光
        p.px(x, Math.round(gy - z), c);
      }
    }
    if (u < 0.12) for (let j = -W - 1; j <= W + 1; j += 2) p.px(Math.round(gx + j), Math.round(gy + 1), ST[2]);   // 破土的碎屑
  }
}

// ---------------------------------------------------------------- S1 冲锋号令（全队回技力 + 下一锤强化）：腰高号令声浪（向外扩的断续金弧）+ 头顶一点号令金芒；贴地一小圈冲击 + 尘
// E0 一道声浪；E1 两道 + 脚下尘圈；E2 三道 + 最外一道白金
function s1castUp(p, t, o, C, ACC, DU) {
  const el = +o.el, SY = +o.SY, n = C.length, waves = el + 1;
  for (let w = 0; w < waves; w++) {
    const u = t - 0.07 * w;
    if (u < 0 || u > 0.36) continue;
    const r = 14 + 120 * u * (1 - u * 0.9), z = 26 + 4 * w, fade = smooth(0.18, 0.36, u);
    const m = Math.ceil(r * TAU);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 4.3 + w * 3, o.seed + 1001) < 0.3 + fade * 0.6) continue;  // 断续，不是整圈
      const sa = Math.sin(a);
      let c = u < 0.067 ? WHITE : sa > 0 ? C[n - 2] : C[n - 4];               // 前半圈亮、后半圈暗（有前后）
      if (el >= 2 && w === waves - 1 && u >= 0.067) c = ACC;
      p.px(Math.round(Math.cos(a) * r), Math.round(sa * r * SY - z), c);
      if (u < 0.15 && sa > 0.3) p.px(Math.round(Math.cos(a) * r), Math.round(sa * r * SY - z + 1), C[n - 4]);
    }
  }
}

function s1castGd(p, t, o, C, ACC, DU) {
  ring(p, t, o, C, 22 + 4 * +o.el, +o.SY, 0.0, 2);
  if (+o.el >= 1) quakeDust(p, t, o, DU, 18 + 4 * +o.el, 6 + 2 * +o.el);
}

function quakeDust(p, t, o, DU, R, m) {
  const SY = +o.SY, u = t - 0.03;
  if (u <= 0 || u > 0.4) return;
  for (let j = 0; j < m; j++) {
    const a = TAU * (j + nz(j * 1.7, o.seed + 1011) * 0.6) / m, rr = R * (0.7 + 0.5 * ease.outCubic(clamp(u / 0.3)));
    const cx = Math.cos(a) * rr, cy = Math.sin(a) * rr * SY, r0 = 2 + (u > 0.15 ? 1 : 0) - (u > 0.28 ? 2 : 0);
    for (let dy = -r0; dy <= r0; dy++) for (let dx = -r0 * 1.5; dx <= r0 * 1.5; dx++) {
      if ((dx * dx) / 2.25 + dy * dy > r0 * r0) continue;
      if (u > 0.2 && nz(j * 5.3, o.seed + 1013) < (u - 0.2) * 4) continue;   // 散掉：整团消失（不撒网点）
      p.px(Math.round(cx + dx), Math.round(cy + dy), dy < 0 ? DU[3] : DU[2]);
    }
  }
}

// ---------------------------------------------------------------- 万兽之王号令波（S1 分支）：0.4 秒扩到半径 90（180 世界）的金色断续环 + 2 格深色内边 + 环边扬尘；之后 0.25 秒淡掉
function cmdGd(p, t, o, C, ACC, DU) {
  const R = +o.R, SY = +o.SY, n = C.length;
  const g = 1 - Math.pow(1 - clamp(t / 0.4), 2), r = Math.max(6, R * g), fade = smooth(0.4, 0.62, t);
  if (fade >= 0.99) return;
  const m = Math.ceil(r * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, ca = Math.cos(a), sa = Math.sin(a);
    if (nz(a * 3.7, o.seed + 1101) < 0.15 + fade * 0.6) continue;
    const rr = r + 1.5 * nz(a * 6, o.seed + 1103);
    for (let k = 0; k < 3; k += 0.5) {
      let ci = k < 1 ? n - 2 : k < 2 ? n - 3 : n - 5;
      if (t < 0.067 && k < 1) ci = n - 1;
      if (sa < -0.2) ci -= 1;
      p.px(Math.round(ca * (rr - k)), Math.round(sa * (rr - k) * SY), C[clamp(ci - Math.round(fade * 3), 1, n - 1)]);
    }
    if (fade < 0.6) for (let k = 0; k < 2; k += 0.5) p.px(Math.round(ca * (rr - 4 - k)), Math.round(sa * (rr - 4 - k) * SY), C[1]);
  }
  for (let j = 0; j < 10; j++) {                                              // 扬尘：环边被推起的土，环过去后留下、变稀
    const a = TAU * (j + nz(j, o.seed + 1105) * 0.5) / 10;
    const rj = R * (0.35 + 0.6 * nz(j * 2.7, o.seed + 1107));
    if (r < rj) continue;
    const age = (r - rj) / R;
    if (age > 0.45 || nz(j * 9 + age * 20, o.seed + 1109) < age * 1.8) continue;
    const cx = Math.cos(a) * rj, cy = Math.sin(a) * rj * SY;
    for (let dx = -2; dx <= 2; dx++) for (let dy = -1; dy <= 1; dy++) if (!((dx + dy + j) & 1) || age < 0.15) p.px(Math.round(cx + dx), Math.round(cy + dy), dy < 0 ? DU[3] : DU[2]);
  }
}

// ---------------------------------------------------------------- S3 碎颅击起手：腰高一道横向白金光带（原作的横向镜头光带）往两侧拉开 + 脚下冲击环 + 往上飘的火星
function s3castUp(p, t, o, C, ACC) {
  const n = C.length;
  if (t < 0.27) {
    const k = t < 0.067 ? 0.6 : t < 0.134 ? 1 : t < 0.2 ? 0.8 : 0.5, L = 46 * k, H = t < 0.134 ? 3 : 2;
    for (let x = -L; x <= L; x += 1) {
      const e = Math.abs(x) / L;
      for (let y = -H; y <= H; y++) {
        if (t > 0.134 && e > 0.5 && ((Math.round(x) + y) & 1)) continue;
        const c = Math.abs(y) < 1 && e < 0.6 ? (t < 0.134 ? WHITE : ACC) : e < 0.8 ? C[n - 2] : C[n - 4];
        p.px(Math.round(x), -26 + y, c);
      }
    }
  }
  for (let i = 0; i < 10; i++) {                                             // 火星往上飘（慢，少）
    const u = t - 0.05 * (i % 4);
    if (u < 0 || u > 0.45) continue;
    const x = (nz(i * 2.3, o.seed + 1201) - 0.5) * 40, z = 10 + 70 * u + 6 * nz(i, o.seed + 1203);
    p.px(Math.round(x + Math.sin(u * 12 + i) * 2), Math.round(-z), u < 0.2 ? C[n - 2] : C[n - 4]);
  }
}
function s3castGd(p, t, o, C, ACC, DU) { ring(p, t, o, C, 40, +o.SY, 0.0, 3); quakeDust(p, t, o, DU, 34, 10); }

// S3 持续：脚下一圈烧红的炭火边（只画边，断续闪动，循环）
function s3aura(p, t, o, C, ACC) {
  const R = +o.R, SY = +o.SY, n = C.length, f = Math.round(t * 15);
  const m = Math.ceil(R * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    const v = nz(a * 5 + f * 0.9, o.seed + 1301);
    if (v < 0.42) continue;
    const rr = R + 1.2 * nz(a * 7, o.seed + 1303);
    const c = v > 0.85 ? ACC : v > 0.65 ? C[n - 3] : C[n - 5];
    p.px(Math.round(Math.cos(a) * rr), Math.round(Math.sin(a) * rr * SY), c);
    if (v > 0.7) p.px(Math.round(Math.cos(a) * (rr - 1.5)), Math.round(Math.sin(a) * (rr - 1.5) * SY), C[2]);
  }
}

// ---------------------------------------------------------------- 后期剑气（growth/late_shape，钝器）= 锤击冲击波：贴地往前滚的一道土浪（凸面朝前的拱起碎土 + 浪脚一线熔金），身后拖一道裂痕
// 一次出手的几道剑气在游戏里合成一道（S = 横向半宽，按道数 1 / 2 / 3+ 取三档）。三帧：0 出手热白 / 1 常态 / 2 碎开变稀。
// 精一：土浪上方蹦起碎石；精二：浪脚熔芯白金 + 裂痕更长
function qiUp(p, t, o, C, ACC, ST, DU) {
  const SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, S = +o.S;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const f = Math.min(2, Math.round(t * 15));
  const bulge = S * 0.4, Hm = 6 + el + S * 0.15;
  const P = (x, w, z) => [Math.round(fx * x + nx * w), Math.round(fy * x + ny * w - z)];
  // 浪脚熔金线（贴地、连续 2 格）：锤子砸出去的那一道冲击沿地面跑
  if (f < 2) for (let w = -S; w <= S; w += 0.5) {
    const k = 1 - (w / S) * (w / S), x = bulge * k + 0.5;
    const [X, Y] = P(x, w, 0);
    p.px(X, Y, f === 0 ? WHITE : el >= 2 ? ACC : C[n - 2]);
    p.px(X, Y - 1, f === 0 ? C[n - 2] : C[n - 3]);
  }
  // 土浪：沿浪线一团团被掀起的土（大小不一、中间高两头低），有受光顶
  const step = 3;
  for (let w = -S + 1; w <= S - 1; w += step) {
    const sd = Math.round(w * 7.3);
    const k = 1 - (w / S) * (w / S);
    if (f === 2 && nz(sd, o.seed + 1403) < 0.5) continue;                 // 碎开
    const x0 = bulge * k - 1.5, z0 = Hm * Math.sqrt(k) * (0.55 + 0.45 * nz(sd, o.seed + 1401)) * (f === 2 ? 0.7 : 1);
    const rr = 2 + (k > 0.55 ? 1 : 0) + (f === 1 ? 1 : 0) - (f === 2 ? 1 : 0);
    for (let dz = -rr; dz <= rr; dz++) for (let dw = -rr; dw <= rr; dw++) {
      if (dz * dz + dw * dw > rr * rr + 0.5) continue;
      const [X, Y] = P(x0, w + dw, z0 * 0.6 + dz);
      let c = dz > rr * 0.3 ? DU[4] : dz > -rr * 0.3 ? DU[3] : DU[2];
      if (dz >= rr - 0.5 && f === 0) c = C[n - 2];                         // 出手那一拍：顶上一线金
      p.px(X, Y, c);
    }
    for (let z = 0; z < z0 * 0.6 - rr; z += 1) { const [X, Y] = P(x0, w, z); p.px(X, Y, DU[2]); }   // 土柱根
  }
  // 碎石：土浪上方蹦起（精一起更多、精二带熔金）
  const NR = 3 + 3 * el;
  if (f < 2) for (let i = 0; i < NR; i++) {
    const w = S * (nz(i * 2.3, o.seed + 1411) * 1.8 - 0.9), z = Hm + 2 + 7 * nz(i * 3.1, o.seed + 1413) + (f === 1 ? 4 : 0);
    const x = bulge * (1 - (w / S) * (w / S)) - 1 - 3 * nz(i, o.seed + 1415);
    const [X, Y] = P(x, w, z);
    p.px(X, Y, el >= 2 && i % 3 === 0 ? ACC : ST[4]); p.px(X + 1, Y, ST[2]); p.px(X, Y + 1, ST[2]);
  }
}

function qiGd(p, t, o, C, ACC, ST, DU) {
  const SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, S = +o.S;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const f = Math.min(2, Math.round(t * 15));
  const bulge = S * 0.4, Lt = 14 + 5 * el + S * 0.4;
  for (let w = -S; w <= S; w += 1) {                                          // 浪脚的影子
    const k = 1 - (w / S) * (w / S);
    for (let d = 0; d < 3; d++) p.dot(Math.round(fx * (bulge * k - d) + nx * w), Math.round(fy * (bulge * k - d) + ny * w + 1), DU[0], f === 2 ? 0.25 : 0.5);
  }
  let y = 0;                                                                  // 身后裂痕：一道锯齿细裂往后拖，越远越暗
  for (let s = 0; s < Lt; s += 1) {
    y += (nz(s * 0.4, o.seed + 1421) - 0.5) * 1.1; y *= 0.9;
    if (f === 2 && nz(s * 0.7, o.seed + 1423) < 0.5) continue;
    const x = -s, q = s / Lt;
    let c = q < 0.3 ? (f === 0 ? WHITE : el >= 2 ? ACC : C[n - 3]) : q < 0.6 ? C[n - 5] : DU[1];
    p.px(Math.round(fx * x + nx * y), Math.round(fy * x + ny * y), c);
    if (q < 0.5) p.px(Math.round(fx * x + nx * y), Math.round(fy * x + ny * y) + 1, DU[0]);
  }
}

// ---------------------------------------------------------------- 技能连携 v2「冲阵」尾锤（link/v2 缺省开时实际出的连携，skill_link.gd l_siege）：
// 冲到区域中心一锤砸地：大砸坑（深色坑 + 坑口受光土）+ 不规整裂网 + 冲击环 + 碎石顶起落回（大小不一、少数高飞）+ 两层尘墙。和 S2 区分：没有冲柱，坑大、碎石多
function linkUp(p, t, o, C, ACC, ST, DU) {
  flash(p, t, C, 14, 5, 4, 0.0);
  streaks(p, t, o, C, 10, 150, o.seed + 41, 0.0, 70);
  rubble(p, t, o, ST, DU, 18, 40, o.seed + 43, 0.03, null);
  dustWall(p, t, o, DU, 42, 18, 12, o.seed + 45, 0.05);
  dustWall(p, t, o, DU, 26, 12, 7, o.seed + 47, 0.12);
}
function linkGd(p, t, o, C, ACC, DU) {
  const SY = +o.SY;
  crater(p, t, o, DU, 18, SY, 0.8);
  ring(p, t, o, C, 46, SY, 0.0, 3);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, 44, 9, o.seed + 49), SY, false, 0.0);
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), DU = fit(o.dust, 5), ST = fit(o.stone, 6), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "arc": return gd ? undefined : arc(p, t, o, C, ACC);
    case "imp": return gd ? impGd(p, t, o, C, ACC, DU) : impUp(p, t, o, C, ACC, ST, DU);
    case "s3": return gd ? s3Gd(p, t, o, C, ACC, DU) : s3Up(p, t, o, C, ACC, ST, DU);
    case "slam": return gd ? slamGd(p, t, o, C, ACC, DU) : slamUp(p, t, o, C, ACC, ST, DU);
    case "quake": return gd ? quake(p, t, o, C, ACC, DU) : undefined;
    case "crush": return gd ? crushGd(p, t, o, C, ACC, DU) : crushUp(p, t, o, C, ACC, ST, DU);
    case "crash": return gd ? crashGd(p, t, o, C) : crashUp(p, t, o, C);
    case "fis": return gd ? fisGd(p, t, o, C, ACC, DU) : fisUp(p, t, o, C, ACC, ST);
    case "s1cast": return gd ? s1castGd(p, t, o, C, ACC, DU) : s1castUp(p, t, o, C, ACC, DU);
    case "cmd": return gd ? cmdGd(p, t, o, C, ACC, DU) : undefined;
    case "s3cast": return gd ? s3castGd(p, t, o, C, ACC, DU) : s3castUp(p, t, o, C, ACC);
    case "s3aura": return gd ? s3aura(p, t, o, C, ACC) : undefined;
    case "qi": return gd ? qiGd(p, t, o, C, ACC, ST, DU) : qiUp(p, t, o, C, ACC, ST, DU);
    case "link": return gd ? linkGd(p, t, o, C, ACC, DU) : linkUp(p, t, o, C, ACC, ST, DU);
  }
}
