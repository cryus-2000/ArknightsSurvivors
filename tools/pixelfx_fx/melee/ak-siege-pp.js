// 推进之王「转平面」（docs/264，开关 fx/px_plane，照 docs/246 斯卡蒂 / docs/254 星熊的做法）：pixelfx 画法，按本作俯视斜角重画。
// 一个文件按 part 出各件；每件分两层（layer）：
//   up 立起层 —— 离地的东西（下砸锤弧、落点白闪、火星线、碎石、尘墙、岩刺、冲柱），原点 = 脚底 / 落点地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（裂网、砸坑、冲击环、地裂、尘印），已按 SY（0.72）压扁，画在地面层。
// 1 像素 = 1 美术像素 = 2 世界像素，游戏里只按 2 倍整数放大、不旋转；方向件按 dir（−90 / −45 / 0 / 45 / 90°）逐向生成，另一半水平翻转。
// view: "raw" 出「旧做法」对照：正俯视 / 正圆、光晕烤进颜色，游戏里旋转 + 小数缩放贴。
// 色：本人金（游戏代表色 #ffc759 一组，熔金 8 阶；不用危险红）；尘 / 碎石暖土；精二点缀白金熔芯 #fff1b8（裂缝冷得慢、一直透亮）。
// 11-05 第二轮（用户「是不是都是裂地有点太重复」）：裂地（裂地 v3 的分叉裂网）只留给最重的——S3 碎颅、精二破阵、路线「再跃·裂地」；
// 普攻 = 金属火花 + 空气压缩白弧 + 小凹痕；S1 = 战旗 + 狮吼声浪；S2 = 残影弧 + 环形尘浪；熔铁飞溅是她独有的质感（精一起）。
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

// ---------------------------------------------------------------- 熔铁质感（她的锤是锻铁）：通红的熔铁飞溅——白热出锤、受重力落地、落地成一点暗红慢慢冷掉
function spatter(p, t, o, C, ACC, N, spd, sd, t0, white) {
  const n = C.length, SY = +o.SY;
  for (let i = 0; i < N; i++) {
    const u = t - (t0 || 0) - 0.008 * (i % 4);
    if (u <= 0) continue;
    const a = TAU * nz(i * 2.9, sd + 1601), v = spd * (0.5 + 0.7 * nz(i * 3.7, sd + 1603)), vz = 70 + 90 * nz(i * 5.1, sd + 1605);
    const tl = (vz + Math.sqrt(vz * vz + 4 * 300 * 6)) / (2 * 300);   // 落地时刻（z = 6 起抛）
    const ul = Math.min(u, tl);
    const gx = Math.cos(a) * v * ul, gy = Math.sin(a) * v * ul * SY, z = Math.max(0, 6 + vz * ul - 300 * ul * ul);
    const X = Math.round(gx), Y = Math.round(gy - z);
    if (u < tl) {
      const c = u < 0.067 ? WHITE : u < 0.2 ? (white ? ACC : C[n - 2]) : C[n - 3];
      p.px(X, Y, c);
      if (u < 0.15) p.px(X, Y + 1, C[n - 4]);                                // 拖一格
    } else {
      const k = u - tl;                                                       // 落地：一点熔铁冷掉
      if (k > 0.45) continue;
      p.px(X, Y, k < 0.12 ? C[n - 3] : k < 0.28 ? C[n - 5] : C[n - 6]);
    }
  }
}

// 空气压缩环：锤面撞地那一下把空气锤开——一圈细的白弧（1 格，断续），很快扩开、两拍就没（不是贴地冲击环：细、白、离地一点）
function compress(p, t, o, C, R0, R1, z, t0, gold) {
  const n = C.length, SY = +o.SY, u = t - (t0 || 0);
  if (u < 0 || u >= 0.2) return;
  const k = ease.outCubic(clamp(u / 0.2)), r = R0 + (R1 - R0) * k;
  const m = Math.ceil(r * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 4.1 + (t0 || 0) * 9, o.seed + 1621) < 0.18 + u * 2.5) continue;
    const sa = Math.sin(a);
    const c = u < 0.067 ? WHITE : gold ? (sa > 0 ? C[n - 2] : C[n - 3]) : (sa > 0 ? C[n - 1] : C[n - 2]);
    p.px(Math.round(Math.cos(a) * r), Math.round(sa * r * SY - z), c);
    if (u < 0.067 && sa > 0.2) p.px(Math.round(Math.cos(a) * r), Math.round(sa * r * SY - z + 1), C[n - 3]);
  }
}

// 狮吼声波环：2 格粗的金色弧，从 c 往外推，n 道错开 0.06 秒；span = 半张角（π = 整圈，贴地）；vertical = 竖直面（立起层，「)」形）
function roarRings(p, t, o, C, ACC, cx, cz, R0, R1, n, span, vertical, white, t0) {
  const N = C.length, SY = +o.SY;
  for (let w = 0; w < n; w++) {
    const u = t - (t0 || 0) - 0.06 * w;
    if (u < 0 || u > 0.34) continue;
    const r = R0 + (R1 - R0) * ease.outCubic(clamp(u / 0.34)), fd = smooth(0.18, 0.34, u);
    for (let a = -span; a <= span; a += 0.5 / r) {
      if (nz(a * 6 + w * 5, o.seed + 1641) < 0.08 + fd * 0.7) continue;
      const ca = Math.cos(a), sa = Math.sin(a);
      const c = u < 0.067 ? WHITE : white && w === 0 ? ACC : Math.abs(a) < span * 0.5 ? C[N - 2] : C[N - 3];
      for (let k = 0; k < 2; k++) {
        const rr = r - k;
        const X = vertical ? cx + ca * rr : ca * rr, Y = vertical ? -cz + sa * rr * 0.85 : sa * rr * SY - cz;
        p.px(Math.round(X), Math.round(Y), k === 0 ? c : C[N - 4]);
      }
    }
  }
}

function dent(p, t, o, DU, rx) {
  const SY = +o.SY, fade = smooth(0.2, 0.6, t);
  if (fade >= 0.97) return;
  p.shade(-rx - 1, -rx * SY - 1, rx + 1, rx * SY + 1, (x, y, out) => {
    const d = Math.hypot(x / rx, y / (rx * SY));
    if (d > 1) return;
    out.c = d > 0.7 && y < 0 ? DU[3] : DU[0];
    out.a = 0.55 * (1 - fade);
  });
}

// ---------------------------------------------------------------- 普攻落点（不开裂）：锤面撞击的金属火花 + 一圈空气压缩白弧 + 小凹痕和几块碎石
// 精一：熔铁飞溅（通红的锤头余温）+ 碎石多；精二：飞溅白金、两圈压缩弧——精二的裂地只给「破阵」地裂
// S1「号令一锤」：两圈压缩弧（白、金，错开一拍）更大 + 金色号令声浪往前一推，同样不开裂
function impUp(p, t, o, C, ACC, ST, DU) {
  const el = +o.el, s1 = o.style === "s1", k = s1 ? 1.35 : 1;
  flash(p, t, C, (5 + el) * k, (2 + el) * k, 3, 0.0);
  streaks(p, t, o, C, ([8, 10, 12][el] + (s1 ? 4 : 0)), 150 * k, o.seed, 0.0, 80);   // 金属火花（细长、会落）
  compress(p, t, o, C, 6, (22 + 4 * el) * k, 3, 0.0, false);
  if (el >= 2 || s1) compress(p, t, o, C, 4, (16 + 3 * el) * k, 5, 0.067, true);
  if (el >= 1 || s1) spatter(p, t, o, C, ACC, (s1 ? 8 : 4) + 3 * el, 70 * k, o.seed + 9, 0.02, el >= 2);
  rubble(p, t, o, ST, DU, (el >= 1 ? 5 : 3) + (s1 ? 3 : 0), (8 + 2 * el) * k, o.seed + 5, 0.03, null);
  if (s1) roarFwd(p, t, o, C, ACC, el);
}

function impGd(p, t, o, C, ACC, DU) {
  const el = +o.el, s1 = o.style === "s1", raw = o.view === "raw";
  if (raw) {   // 旧做法对照：正圆 + 光晕
    crater(p, t, o, DU, 6 + 2 * el, 1, 0.6);
    p.glow && p.glow(0, 0, 24, C[C.length - 2], 0.6 * (1 - smooth(0.05, 0.3, t)));
    return;
  }
  dent(p, t, o, DU, (5 + el) * (s1 ? 1.4 : 1));
}

// 号令一锤：落点往四周一推的金色声浪（同 S1 号令的狮吼弧，压低到地面高度）
function roarFwd(p, t, o, C, ACC, el) {
  const n = C.length, SY = +o.SY;
  for (let w = 0; w < 2; w++) {
    const u = t - 0.04 - 0.07 * w;
    if (u < 0 || u > 0.3) continue;
    const r = 12 + 140 * u * (1 - u), fade = smooth(0.15, 0.3, u), m = Math.ceil(r * TAU);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 5.3 + w * 7, o.seed + 1631) < 0.35 + fade * 0.55) continue;
      const sa = Math.sin(a);
      p.px(Math.round(Math.cos(a) * r), Math.round(sa * r * SY - 8), u < 0.067 ? WHITE : el >= 2 && w === 0 ? ACC : sa > 0 ? C[n - 2] : C[n - 4]);
      p.px(Math.round(Math.cos(a) * (r - 1)), Math.round(sa * (r - 1) * SY - 8), C[n - 4]);
    }
  }
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

// ---------------------------------------------------------------- S2 跃空锤（重点在「跃」和「落」；11-05 第三轮用户「S2 的裂地感不要去掉」：落点加回小范围放射裂）
// 跃：起跳点 → 落点一道金色残影弧（她在空中抡锤转一圈：弧上三段渐暗残影 + 锤头一道亮线），方向件，原点 = 起跳点，D = 跃出距离
function leapTrail(p, t, o, C, ACC) {
  const SY = +o.SY, th = +o.dir * D2R, n = C.length, D = +o.L, H = 21, el = +o.el;
  const fx = Math.cos(th), fy = Math.sin(th) * SY;
  const T = 0.42, u = clamp(t / T), fade = smooth(T, T + 0.2, t);
  if (fade >= 0.99) return;
  const head = u, tail = Math.max(0, u - 0.55) + fade * u;
  for (let s = tail; s <= head; s += 0.5 / Math.max(1, D)) {
    const x = D * s, z = 4 * H * s * (1 - s) + 16;                        // 身体中心高度走抛物线
    const q = (s - tail) / Math.max(0.001, head - tail);                  // 0 尾 → 1 头
    const w = 1 + Math.round(2 * q);
    for (let k = -w; k <= w; k++) {
      const e = Math.abs(k) / (w + 0.5);
      let ci = q > 0.85 ? (e < 0.5 ? n - 1 : n - 2) : q > 0.5 ? (e < 0.5 ? n - 2 : n - 3) : (e < 0.5 ? n - 3 : n - 5);
      ci = clamp(ci - Math.round(fade * 3), 1, n - 1);
      if (q < 0.4 && ((Math.round(s * D * 2) + k) & 1)) continue;          // 尾巴抖动变稀
      p.px(Math.round(fx * x), Math.round(fy * x - z + k), el >= 2 && q > 0.5 && e < 0.4 ? ACC : C[ci]);
    }
  }
  // 抡锤一圈：锤头那一点绕身体转（四拍一圈），留一小截亮弧
  if (u < 1) for (let a = 0; a < 1.2; a += 0.08) {
    const ang = u * TAU * 1.2 - a, x = D * u + Math.cos(ang) * 10, z = 4 * H * u * (1 - u) + 16 + Math.sin(ang) * 10;
    p.px(Math.round(fx * x), Math.round(fy * x - z), a < 0.3 ? WHITE : a < 0.7 ? C[n - 2] : C[n - 4]);
  }
}

// 落点放射裂：从落点往外的短直裂（几乎不拐、少分叉），长短不一——和 S3 碎颅的向前大裂扇（熔芯、深）区分
function radialCracks(o, R, N, sd) {
  const paths = [];
  for (let j = 0; j < N; j++) {
    let a = TAU * (j + (nz(j * 1.7, sd + 731) - 0.5) * 0.5) / N, x = Math.cos(a) * 3, y = Math.sin(a) * 3;
    const L = R * (0.45 + 0.55 * nz(j * 2.9, sd + 733));
    const pts = [[x, y, 0]];
    for (let s2 = 0; s2 < L; s2 += 1) {
      a += (nz(s2 * 0.3 + j * 11, sd + 735) - 0.5) * 0.16;
      x += Math.cos(a); y += Math.sin(a);
      pts.push([x, y, s2 / L]);
    }
    paths.push(pts);
    if (nz(j * 4.1, sd + 737) > 0.7) {   // 少数末端一个小叉
      const k = Math.floor(pts.length * 0.6);
      let [bx, by] = pts[k], ba = a + (j % 2 ? 0.6 : -0.6);
      const bp = [[bx, by, pts[k][2]]];
      for (let s2 = 0; s2 < L * 0.3; s2++) { bx += Math.cos(ba); by += Math.sin(ba); bp.push([bx, by, pts[k][2] + s2 / L]); }
      paths.push(bp);
    }
  }
  return paths;
}

// 落：一圈环形尘浪（贴地往外滚的尘团，有受光顶、越滚越矮）+ 碎石飞起再落下 + 落点白闪与浅坑；精二：尘浪两圈、熔铁飞溅白金
function dustWave(p, t, o, DU, C, R, m, hMax, sd, t0, hot) {
  const SY = +o.SY, u = t - (t0 || 0), n = C.length;
  if (u <= 0 || u > 0.55) return;
  const g = ease.outCubic(clamp(u / 0.35)), r = R * (0.25 + 0.75 * g);
  for (let j = 0; j < m; j++) {
    const a = TAU * (j + nz(j * 1.3, sd + 1701) * 0.6) / m;
    if (u > 0.3 && nz(j * 7.7, sd + 1703) < (u - 0.3) * 4) continue;         // 散掉：整团消失
    const h = hMax * (0.6 + 0.4 * nz(j * 2.1, sd + 1705)) * (1 - 0.6 * g);
    const gx = Math.cos(a) * r, gy = Math.sin(a) * r * SY;
    const rr = 2 + (nz(j * 3.7, sd + 1707) > 0.5 ? 1 : 0) + (u < 0.2 ? 1 : 0);
    for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr - 1; dx <= rr + 1; dx++) {
      if ((dx * dx) / ((rr + 1) * (rr + 1)) + (dy * dy) / (rr * rr) > 1.05) continue;
      let c = dy < -rr * 0.3 ? DU[4] : dy < rr * 0.3 ? DU[3] : DU[2];
      if (hot && u < 0.1 && dy < -rr * 0.3) c = C[n - 3];                   // 落地那一拍：尘浪顶被照亮
      p.px(Math.round(gx + dx), Math.round(gy - h * 0.5 + dy), c);
    }
  }
}

function slamUp(p, t, o, C, ACC, ST, DU) {
  const R = +o.R, el = +o.el;
  if (o.style === "rift") return riftUp(p, t, o, C, ACC, ST, DU);
  flash(p, t, C, 12, 4, 4, 0.0);
  dustWave(p, t, o, DU, C, R, 22 + 4 * el, 12 + 2 * el, o.seed + 3, 0.02, true);
  if (el >= 2) dustWave(p, t, o, DU, C, R * 0.6, 14, 9, o.seed + 4, 0.12, false);
  rubble(p, t, o, ST, DU, 14 + 5 * el, R * 0.45, o.seed + 5, 0.03, el >= 2 ? ACC : null);
}

function slamGd(p, t, o, C, ACC, DU) {
  const R = +o.R, el = +o.el, raw = o.view === "raw", SY = raw ? 1 : +o.SY;
  if (o.style === "rift") return riftGd(p, t, o, C, ACC, DU);
  crater(p, t, o, DU, R * 0.2, SY, 0.6);
  if (!raw) drawCracks(p, t, o, C, ACC, DU, radialCracks(o, R * 0.5, [10, 10, 13][el], o.seed + 63), SY, false, 0.0);   // 落点小范围放射裂（金色、不熔芯）
  if (raw) { ring(p, t, o, C, R, SY, 0.0, 3); p.glow && p.glow(0, 0, R * 0.6, C[C.length - 2], 0.7 * (1 - smooth(0.05, 0.4, t))); return; }
  ring(p, t, o, C, R * 1.02, SY, 0.04, 2);                                 // 尘浪外沿压出的一圈浅印（细、断续）
}

// 路线「再跃·裂地」（名字就是裂地）：竖直冲柱 + 大裂网 + 冲击环 + 碎石 + 尘墙（原作 S2 的裂网，金色）
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

function riftUp(p, t, o, C, ACC, ST, DU) {
  const R = +o.R, el = +o.el;
  pillar(p, t, C, ACC, R * 1.15, 9 + 2 * el, el);
  flash(p, t, C, 11, 4, 4, 0.0);
  streaks(p, t, o, C, 10 + 4 * el, 170, o.seed + 1, 0.0, 90);
  rubble(p, t, o, ST, DU, 12 + 4 * el, R * 0.8, o.seed + 3, 0.03, el >= 2 ? ACC : null);
  dustWall(p, t, o, DU, R * 0.95, 16 + 4 * el, 10 + 3 * el, o.seed + 5, 0.06);
}

function riftGd(p, t, o, C, ACC, DU) {
  const R = +o.R, el = +o.el, SY = +o.SY;
  crater(p, t, o, DU, R * 0.24, SY, 0.7);
  ring(p, t, o, C, R, SY, 0.0, 3);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, R * 0.95, [9, 9, 13][el], o.seed + 61), SY, el >= 2, 0.0);
}

// ---------------------------------------------------------------- 震地 / 狮吼（成长节点）：落点一圈贴地冲击环 + 环边尘团；狮吼双环、更厚、尘多
function quake(p, t, o, C, ACC, DU) {
  const R = +o.R, SY = +o.SY, roar = o.style === "roar";
  ring(p, t, o, C, R, SY, 0.0, roar ? 3 : 2);
  if (roar) ring(p, t, Object.assign({}, o, { seed: +o.seed + 40 }), C, R * 0.7, SY, 0.04, 2);
  if (roar) roarRings(p, t, o, C, C[C.length - 2], 0, 4, R * 0.5, R * 1.45, 2, Math.PI, false, false, 0.02);   // 狮吼：2 格粗的声波环往外推
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

// ---------------------------------------------------------------- 精一「粉碎」：击倒处碎石迸开（立起）+ 小凹痕（贴地，不开裂）
function crushUp(p, t, o, C, ACC, ST, DU) {
  flash(p, t, C, 5, 3, 6, 0.0);
  rubble(p, t, o, ST, DU, 8, 10, o.seed + 21, 0.02, C[C.length - 3]);
}
function crushGd(p, t, o, C, ACC, DU) {
  dent(p, t, o, DU, 5);
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

// ---------------------------------------------------------------- S1 冲锋号令（全队回技力 + 下一锤强化）：狮王号令，不砸地
// 立起：她身后立起一面金色战旗（旗杆拔起、旗面迎风抖三拍、旗上狮纹章）；身前张开一个狮头剪影（金色 2 格描边、内部淡填充）+ 2 格粗的狮吼声波环往前推 + 地上尘土被吹开
// （11-05 第三轮用户「我好像没有看到狮子吼」：第二轮两侧细「)))」去掉）；方向件：朝左时游戏里翻转；
// 贴地：脚下一圈很淡的金色涟漪（细，不是冲击环）。E0 声浪每侧 1 道；E1 2 道 + 旗头王冠尖；E2 3 道 + 旗边白金、王冠亮
function s1castUp(p, t, o, C, ACC, DU) {
  const el = +o.el, SY = +o.SY, n = C.length, waves = el + 1;
  // 战旗：旗杆在她身后偏左，旗面朝右飘
  const rise = ease.outCubic(clamp(t / 0.1)), fade = smooth(0.42, 0.6, t);
  if (fade < 0.99) {
    const px0 = -10, top = 46 + 22 * rise;
    for (let z = 4; z <= top; z++) {
      if (fade > 0.3 && nz(z * 1.7, o.seed + 1801) < fade) continue;
      p.px(px0, Math.round(-z), z > top - 2 ? C[n - 2] : C[n - 5]);
    }
    const FW = 16, FH = 11, f = Math.floor(t * 15);
    for (let x = 1; x <= FW; x++) {
      const wav = Math.round(Math.sin(x * 0.45 - f * 1.3) * 1.5 * (x / FW));
      for (let y = 0; y < FH - Math.round(x / FW * 2); y++) {
        if (fade > 0.3 && nz(x * 3 + y * 7, o.seed + 1803) < fade) continue;
        const edge = y === 0 || x === FW || y === FH - 1 - Math.round(x / FW * 2);
        let c = edge ? (el >= 2 ? ACC : C[n - 2]) : (x + wav) % 6 < 3 ? C[n - 3] : C[n - 4];
        const ex = x - 8, ey = y - 5;                                       // 狮纹章：旗中一块暗色盾形 + 一点亮（狮眼）
        if (Math.abs(ex) + Math.abs(ey) * 0.8 < 3.5) c = C[2];
        if (ex === 0 && ey === -1) c = t < 0.15 ? WHITE : C[n - 2];
        if (t < 0.067) c = edge ? WHITE : C[n - 2];
        p.px(px0 + x, Math.round(-top + 1 + y + wav), c);
      }
    }
    if (el >= 1) {                                                         // 旗头王冠尖（三点）
      const cy = Math.round(-top - 2), cc = el >= 2 && t < 0.3 ? WHITE : C[n - 2];
      for (const dx of [-2, 0, 2]) p.px(px0 + dx, cy - (dx === 0 ? 1 : 0), cc);
      p.px(px0 - 1, cy + 1, C[n - 3]); p.px(px0 + 1, cy + 1, C[n - 3]);
    }
  }
  lionHead(p, t, o, C, ACC, el);
  roarRings(p, t, o, C, ACC, 40, 30, 12, 84, [2, 3, 3][el], 0.95, true, el >= 2, 0.06);
  blowDust(p, t, o, DU, el);
}

// 狮头剪影（侧面，朝 +x，朝左游戏里翻转）：身后一圈尖鬃、头、竖耳、上颚 + 张开的下颚（口里暗）、獠牙、亮眼；
// 鬃毛和脸各一道 2 格金色描边（脸亮、鬃暗一阶），内部真半透明淡填充（不抖网点）。0.1 秒张口到全尺寸，停到 0.3 秒，0.46 秒前淡掉
function lionHead(p, t, o, C, ACC, el) {
  const n = C.length;
  if (t >= 0.46) return;
  const k = 1.25 * (0.65 + 0.35 * ease.outCubic(clamp(t / 0.1))), fa = 1 - smooth(0.3, 0.46, t);
  const cx = 20, cz = 36, open = 0.15 + 0.85 * ease.outCubic(clamp((t - 0.02) / 0.1));
  const mane = (x, y) => {
    const a = Math.atan2(y, x), d = Math.hypot(x, y);
    const tri = Math.abs((((a + 0.3) * 7 / TAU) % 1 + 1) % 1 - 0.5) * 2;   // 7 道尖鬃
    return x < 7 && d < 12 + 5 * tri;
  };
  const face = (x, y) => {
    if (((x - 5) / 9) ** 2 + ((y - 1) / 8) ** 2 < 1) return 1;            // 头
    if (y > 6 && y < 14 && x > -1 && x < 7 && (y - 6) < (x + 1) * 1.6 && (y - 6) < (7 - x) * 1.6) return 1;   // 竖耳
    if (((x - 14) / 7.5) ** 2 + ((y - 2) / 4) ** 2 < 1 && y > -1.2) return 1;   // 上颚
    const jy = -2.5 - 6 * open;                                            // 下颚：张口往下
    if (((x - 12) / 6.5) ** 2 + ((y - jy) / 2.4) ** 2 < 1) return 1;
    if (x > 8 && x < 21 && y < -0.8 && y > jy + 1.5 && (x - 8) > 0) return 2;   // 口里
    return 0;
  };
  const B = 34;
  p.shade(cx - B, -(cz + B), cx + B, -(cz - B), (X, Y, out) => {
    const x = (X - cx) / k, y = (-Y - cz) / k;
    const f = face(x, y), m = mane(x, y);
    if (!f && !m) return;
    const step = 2 / k;
    let fe = false, me = false;
    for (const [ex, ey] of [[step, 0], [-step, 0], [0, step], [0, -step]]) {
      if (f === 1 && face(x + ex, y + ey) !== 1) fe = true;
      if (!f && m && !mane(x + ex, y + ey)) me = true;
    }
    if (f === 2) { p.blend(X, Y, C[1], 0.7 * fa); return; }
    if (fe) { out.c = t < 0.067 ? WHITE : el >= 2 ? ACC : C[n - 2]; out.a = fa >= 0.5 ? 1 : 0; return; }
    if (me) { out.c = t < 0.067 ? C[n - 2] : C[n - 3]; out.a = fa >= 0.5 ? 1 : 0; return; }
    p.blend(X, Y, f ? C[n - 3] : C[n - 4], (f ? 0.38 : 0.28) * fa);
  });
  if (fa > 0.5) {
    const P = (x, y) => [Math.round(cx + x * k), Math.round(-(cz + y * k))];
    const [ex, ey] = P(8, 3.5); p.px(ex, ey, WHITE); p.px(ex + 1, ey, WHITE);           // 眼
    const [nx2, ny2] = P(21, 3); p.px(nx2, ny2, C[1]);                                   // 鼻
    const [f1x, f1y] = P(18, -1.5); p.px(f1x, f1y, WHITE); p.px(f1x, f1y + 1, WHITE);   // 上獠牙
    const [f2x, f2y] = P(16, -2 - 6 * open + 1.5); p.px(f2x, f2y, WHITE); p.px(f2x, f2y - 1, WHITE);   // 下獠牙
  }
}

// 被吼开的尘：她身前地面一排尘团往外吹（贴地、往 +x 滑开、越来越稀）
function blowDust(p, t, o, DU, el) {
  const SY = +o.SY, u = t - 0.05;
  if (u <= 0 || u > 0.45) return;
  const m = 8 + 2 * el;
  for (let j = 0; j < m; j++) {
    const a = (nz(j * 1.9, o.seed + 1651) - 0.5) * 1.6;
    const r0 = 10 + 14 * nz(j * 2.7, o.seed + 1653), r = r0 + 110 * u * (1 - u * 0.7);
    if (u > 0.25 && nz(j * 5.1, o.seed + 1655) < (u - 0.25) * 5) continue;
    const X = Math.round(Math.cos(a) * r), Y = Math.round(Math.sin(a) * r * SY - 2);
    const rr = 2 + (u < 0.2 ? 1 : 0);
    for (let dy = -rr + 1; dy <= rr - 1; dy++) for (let dx = -rr - 1; dx <= rr + 1; dx++) {
      if ((dx * dx) / ((rr + 1) * (rr + 1)) + (dy * dy) / (rr * rr) > 1.05) continue;
      p.px(X + dx, Y + dy, dy < 0 ? DU[4] : DU[3]);
    }
  }
}

function s1castGd(p, t, o, C, ACC, DU) {
  const el = +o.el, SY = +o.SY, n = C.length;
  for (let w = 0; w < 1 + (el >= 1 ? 1 : 0); w++) {                          // 淡金涟漪：1 格细线、断续
    const u = t - 0.1 * w;
    if (u < 0 || u > 0.45) continue;
    const r = 10 + 60 * ease.outCubic(clamp(u / 0.45)), m = Math.ceil(r * TAU);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 3.3 + w * 5, o.seed + 1811) < 0.4 + u) continue;
      p.px(Math.round(Math.cos(a) * r), Math.round(Math.sin(a) * r * SY), u < 0.15 ? C[n - 2] : C[n - 4]);
    }
  }
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

// ---------------------------------------------------------------- 后期剑气（growth/late_shape，钝器）= 锤击甩出去的一道冲击波（用户 11-05「剑气是很弱」：加长到 0.5 秒、体量 2 倍以上）
// 游戏里按出手生成一件、自己往前推（前快后慢，约 0.5 秒推 160 世界像素），同一次出手几道合成一道（S = 横向半宽 18 / 24 / 30，按道数 1 / 2 / 3+）。
// 前沿：一道亮色弧（凸面朝前，白热 → 金，离地低、两头收），弧下一线熔金贴地；身后拖碎石（蹦起落下）和尘团，越往后越稀；最后 2 拍前沿碎开。
// 精一：碎石多 + 前沿外一道细白压缩弧；精二：前沿芯白金、拖一串熔铁飞溅
function qiUp(p, t, o, C, ACC, ST, DU) {
  const SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, S = +o.S;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const P = (x, w, z) => [Math.round(fx * x + nx * w), Math.round(fy * x + ny * w - z)];
  const f = Math.floor(t * 15), N = 8, brk = f >= N - 2, bulge = S * 0.45;
  const Wd = 3 + el;                                                        // 前沿弧厚
  for (let w = -S; w <= S; w += 0.5) {
    const u = w / S, k = 1 - u * u, x0 = bulge * k;
    const zt = 2 + 7 * Math.pow(k, 0.7);                                    // 中间高两头低
    for (let d = 0; d < Wd * Math.max(0.35, k); d += 0.5) {
      if (brk && nz(w * 2.3 + d * 5 + f, o.seed + 1901) < 0.45 + (f - N + 2) * 0.25) continue;
      const q = d / Wd;
      let c = q < 0.3 ? (f === 0 ? WHITE : el >= 2 ? ACC : C[n - 2]) : q < 0.65 ? C[n - 3] : C[n - 4];
      if (f >= 4 && q < 0.3 && el < 2) c = C[n - 3];
      for (let z = 0; z <= zt; z += 1) {
        if (z > 1 && z < zt - 1 && q > 0.3) continue;                         // 中段只画外缘，不平涂成墙
        const [X, Y] = P(x0 - d, w, z);
        p.px(X, Y, z >= zt - 1 ? c : z <= 1 ? (q < 0.5 ? C[n - 2] : C[n - 4]) : C[n - 4]);
      }
    }
  }
  if (el >= 1 && f < 5) for (let w = -S * 1.1; w <= S * 1.1; w += 0.5) {      // 精一：前沿外一道细白压缩弧
    if (nz(w * 1.7 + f * 3, o.seed + 1903) < 0.3) continue;
    const u = w / (S * 1.1), x = bulge * (1 - u * u) + 3;
    const [X, Y] = P(x, w, 5 + 3 * (1 - u * u));
    p.px(X, Y, f < 2 ? WHITE : C[n - 2]);
  }
  // 身后：碎石蹦起落下 + 尘团（相对前沿往后，越往后越稀）
  const NR = 6 + 4 * el;
  for (let i = 0; i < NR; i++) {
    const ph = (nz(i * 1.3, o.seed + 1905) + f * 0.25) % 1;                   // 每颗自己的一跳
    const back = 4 + 26 * nz(i * 2.7, o.seed + 1907), w = S * (nz(i * 3.9, o.seed + 1909) * 1.8 - 0.9);
    const z = 18 * ph * (1 - ph) * 4 * (0.6 + 0.4 * nz(i, o.seed + 1911));
    if (brk && i % 2) continue;
    const [X, Y] = P(bulge * (1 - (w / S) * (w / S)) - back, w, z);
    p.px(X, Y, ST[4]); p.px(X + 1, Y, ST[2]); p.px(X, Y + 1, ST[2]);
  }
  for (let i = 0; i < 7 + 2 * el; i++) {
    const back = 6 + 30 * nz(i * 4.1, o.seed + 1913), w = S * (nz(i * 5.3, o.seed + 1915) * 1.6 - 0.8);
    if (nz(i * 6.7 + f, o.seed + 1917) < back / 50) continue;
    const rr = 2 + (back < 16 ? 1 : 0);
    const [X, Y] = P(bulge * (1 - (w / S) * (w / S)) - back, w, 3 + rr);
    for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr - 1; dx <= rr + 1; dx++) {
      if ((dx * dx) / ((rr + 1) * (rr + 1)) + (dy * dy) / (rr * rr) > 1.05) continue;
      p.px(X + dx, Y + dy, dy < 0 ? DU[4] : DU[3]);
    }
  }
  if (el >= 2 && f < N - 2) for (let i = 0; i < 6; i++) {                    // 精二：前沿甩下的熔铁飞溅（落在身后）
    const back = 2 + 14 * ((nz(i * 2.1, o.seed + 1921) + f * 0.3) % 1), w = S * (nz(i * 3.3, o.seed + 1923) * 1.6 - 0.8);
    const [X, Y] = P(bulge * (1 - (w / S) * (w / S)) - back, w, Math.max(0, 6 - back * 0.4));
    p.px(X, Y, back < 6 ? WHITE : back < 10 ? ACC : C[n - 3]);
  }
}

function qiGd(p, t, o, C, ACC, ST, DU) {
  const SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, S = +o.S;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const f = Math.floor(t * 15), bulge = S * 0.45;
  for (let w = -S; w <= S; w += 1) {                                        // 前沿的影子 + 贴地一线熔金
    const k = 1 - (w / S) * (w / S);
    for (let d = 0; d < 4; d++) p.dot(Math.round(fx * (bulge * k - d) + nx * w), Math.round(fy * (bulge * k - d) + ny * w + 1), DU[0], f >= 6 ? 0.25 : 0.5);
    if (f < 6) p.px(Math.round(fx * (bulge * k + 1) + nx * w), Math.round(fy * (bulge * k + 1) + ny * w), f === 0 ? WHITE : el >= 2 ? ACC : C[n - 3]);
  }
  for (let i = 0; i < 3; i++) {                                              // 身后：被推过的地面三道拖痕
    const w = S * (i - 1) * 0.55;
    for (let s = 0; s < 22 + 4 * el; s++) {
      if (nz(s * 0.9 + i * 11, o.seed + 1931) < 0.35 + s / 40) continue;
      const x = bulge * (1 - (w / S) * (w / S)) - 4 - s;
      p.px(Math.round(fx * x + nx * w), Math.round(fy * x + ny * w), s < 6 ? DU[2] : DU[1]);
    }
  }
}

// ---------------------------------------------------------------- 技能连携 v2「冲阵」尾锤（link/v2 缺省开时实际出的连携，skill_link.gd l_siege）：
// 冲到区域中心一锤砸地：大砸坑（深色坑 + 坑口受光土）+ 冲击环（不开裂） + 碎石顶起落回（大小不一、少数高飞）+ 两层尘墙。和 S2 区分：没有冲柱，坑大、碎石多
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
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), DU = fit(o.dust, 5), ST = fit(o.stone, 6), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "arc": return gd ? undefined : arc(p, t, o, C, ACC);
    case "imp": return gd ? impGd(p, t, o, C, ACC, DU) : impUp(p, t, o, C, ACC, ST, DU);
    case "s3": return gd ? s3Gd(p, t, o, C, ACC, DU) : s3Up(p, t, o, C, ACC, ST, DU);
    case "slam": return gd ? slamGd(p, t, o, C, ACC, DU) : slamUp(p, t, o, C, ACC, ST, DU);
    case "trail": return gd ? undefined : leapTrail(p, t, o, C, ACC);
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
