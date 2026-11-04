// 星熊「转平面」（docs/254，开关 fx/px_plane，照 docs/246 斯卡蒂的做法）：pixelfx 画法，按本作俯视斜角重画。
// 一个文件按 part 出各件；每件分两层（layer）：
//   up 立起层 —— 离地的东西（腰高盾斧刀痕、下劈弧、地刺、飞盾、锯线火花、剑气浪墙、推挡大盾），原点 = 脚底地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（投影、裂网冲击环、热砂、撕裂沟），已按 SY（0.72）压扁，画在地面层。
// 1 像素 = 1 美术像素 = 2 世界像素，游戏里只按 2 倍整数放大、不旋转；方向件按 dir（−90 / −45 / 0 / 45 / 90°）逐向生成，另一半水平翻转。
// view: "raw" 出「旧做法」对照：正俯视 / 正圆、光晕烤进颜色，游戏里旋转 + 小数缩放贴。
// 色：PRTS 发色青绿 #58C4AB 一组（原作攻击 / S3 鬼火同色）；盾 / 地刺钢灰；S2 热砂琥珀；精二点缀暖金 #f2bf4c（原作 S3 命中火星色）。不用危险红。
import { fit, clamp, smooth, ease, noise, noise2, TAU, hex, WHITE } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma plane",
  desc: "Hoshiguma's shield-axe sweeps, shield slam, thorn spikes, heat sand, saw rip, thrown spinning shield, shield shockwaves and shield shove redrawn for a 3/4 top-down plane.",
  tags: ["melee", "slash", "topdown", "hoshiguma", "one-shot"],
  size: [300, 260],
  origin: [150, 150],
  duration: 1.6,   // 最长一件（举盾 1.5 秒）；各件实际帧数由 tools/pxplane_bake.py 按件截
  loop: false,
  fps: 15,   // 统一动画时钟：本作特效帧条一律 15 fps
  bg: "dark",
  options: {
    palette: ["#050f0c", "#0b1e19", "#123a31", "#1d5e50", "#2f8a76", "#58c4ab", "#b4f0e2", "#ffffff"],
    steel: ["#141519", "#262a31", "#3f4652", "#646d7c", "#98a2b2", "#d6dce6"],
    amber: ["#2a1a08", "#5a3610", "#94601a", "#d2922a", "#f2bf4c", "#fbe3a6"],
    dust: ["#1a1712", "#2e2920", "#4a4234", "#6e6450", "#968a70"],
    accent: "#f2bf4c",
    part: "sweep",
    layer: "up",
    view: "plane",
    R: 47, span: 2.44, dir: 0, H0: 12, W: 11, H: 40, L: 110, el: 0, SY: 0.72, dur: 0.32, seed: 3,
  },
};

const D2R = Math.PI / 180;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1

// ---------------------------------------------------------------- 盾斧斩（普攻）：腰高水平刀痕，盾缘那一头是钝的（不是针尖），中段最厚
function sweepT(t, span) {
  const a0 = -span / 2;
  const head = a0 + span * (0.6 + 0.4 * clamp(t / 0.067));
  const tail = a0 + span * 0.25 * smooth(0.07, 0.3, t);
  return [a0, head, tail];
}

function sweep(p, t, o, C, ACC, ST) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : +o.H0, th = +o.dir * D2R, el = +o.el, n = C.length;
  const span = +o.span, [a0, head, tail] = sweepT(t, span);
  const hot = t < 0.067, cool = smooth(0.07, +o.dur, t);
  if (head - tail < 0.05 || cool >= 0.75) return;
  const R = +o.R, Wr = +o.W * (1 - 0.65 * cool), B = R + 3;
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY, r = Math.hypot(x, pz);
    if (r > R + 1.5 || r < R - Wr - 1) return;
    let a = Math.atan2(pz, x) - th;
    a = ((a - a0) % TAU + TAU) % TAU + a0;
    if (a < tail || a > head) return;
    const u = (a - tail) / Math.max(0.001, head - tail);
    // 钝头：刀尾慢慢变厚，到刀头前一直保持厚度，盾缘处方头收 1 格
    let wr = Wr * Math.min(1, Math.pow(u / 0.55, 0.8)) * (u > 0.97 ? 0.8 : 1);
    if (wr < 0.8) return;
    const q = (R + 0.7 * nz(a * 15, o.seed + 3) - r) / wr;
    if (q < 0 || q > 1) return;
    let ci;
    if (q < 0.14) ci = hot ? n - 1 : n - 2;          // 外缘白刃
    else if (q < 0.36) ci = n - 3;
    else if (q < 0.62) ci = n - 4;
    else if (q < 0.86) ci = n - 5;
    else { ci = n - 6; out.a = 0.55; }
    if (q > 0.2 && q < 0.86 && nz(r * 0.9 + o.seed, o.seed + 91) > 0.7) ci += 1;   // 速度纹
    if (hot && u > 0.88 && q < 0.3) ci = n - 1;     // 盾缘热白（只一小截）
    ci = clamp(ci - Math.round(cool * 2.5) - (u < 0.2 ? 1 : 0), 1, n - 1);
    out.c = C[ci];
    if (out.a === undefined) out.a = cool > 0.6 ? 0.6 : 1;
    if (el >= 2 && !hot && q > 0.14 && q < 0.27) out.c = ACC;   // 精二：白刃内侧暖金副刃
  });
  if (raw) {
    for (let a = tail; a <= head; a += 0.12) p.light(Math.cos(a + th) * R * 0.9, Math.sin(a + th) * R * 0.9, C[n - 2], 0.35 * (1 - cool));
    return;
  }
  // 出手第一帧：盾缘一道径向刃光
  if (hot) {
    const ha = head + th;
    for (let d = R * 0.55; d <= R + 1; d += 0.5) {
      const x = Math.cos(ha) * d, y = Math.sin(ha) * d * SY - H0;
      p.px(Math.round(x), Math.round(y), d > R * 0.8 ? WHITE : C[n - 2]);
      p.px(Math.round(x - Math.sin(ha)), Math.round(y + Math.cos(ha) * SY), C[n - 2]);
    }
  }
  // 精一起：盾缘崩出钢屑（2 格碎片，顺切线甩出、受重力落下）；精二混入暖金火星
  if (el >= 1 && t > 0.02 && t < 0.3) {
    const ha = head + th, tx = -Math.sin(ha), ty = Math.cos(ha) * SY, hx = Math.cos(ha) * R, hy = Math.sin(ha) * R * SY - H0;
    const N = el >= 2 ? 12 : 8, u = t - 0.02;
    for (let i = 0; i < N; i++) {
      const sp = 90 + 110 * nz(i * 3.1, o.seed + 201), da = (nz(i * 1.7, o.seed + 203) - 0.5) * 1.6;
      const dx = tx * Math.cos(da) - ty * Math.sin(da), dy = tx * Math.sin(da) + ty * Math.cos(da);
      const x = hx + dx * sp * u + Math.cos(ha) * sp * 0.3 * u, y = hy + dy * sp * u - 30 * u + 300 * u * u;
      const X = Math.round(x), Y = Math.round(y);
      const gold = el >= 2 && i % 3 === 0;
      const c = gold ? (u < 0.15 ? WHITE : ACC) : (u < 0.1 ? ST[5] : u < 0.2 ? ST[4] : ST[3]);
      p.px(X, Y, c);
      if (!gold) p.px(X + 1, Y, u < 0.2 ? ST[3] : ST[2]);
    }
  }
}

// 地面：刀痕投影 + 盾缘落处一小团尘（Noita 尘点，往外散、越来越稀）
function sweepGround(p, t, o, C, ACC, ST, AM, DU) {
  if (o.view === "raw") return;
  const R = +o.R, W = +o.W, SY = +o.SY, th = +o.dir * D2R, el = +o.el;
  const [a0, head, tail] = sweepT(t, +o.span);
  const cool = smooth(0.07, +o.dur, t);
  if (head - tail >= 0.05 && cool < 0.75) for (let a = tail; a <= head; a += 0.4 / R) {
    const u = (a - tail) / Math.max(0.001, head - tail);
    const wr = W * 0.5 * Math.min(1, Math.pow(u / 0.55, 0.8));
    for (let d = 0; d < wr; d += 1) {
      const rr = R - d;
      p.dot(Math.round(Math.cos(a + th) * rr), Math.round(Math.sin(a + th) * rr * SY), C[0], 0.45 * (1 - cool));
    }
  }
  // 尘：刀头最后落处（弧末端）
  const ha = a0 + +o.span + th, cx = Math.cos(ha) * R * 0.95, cy = Math.sin(ha) * R * 0.95 * SY;
  const u = t - 0.05;
  if (u > 0 && u < 0.32) {
    const N = 7 + 4 * el;
    for (let i = 0; i < N; i++) {
      const a = TAU * nz(i * 2.7, o.seed + 501), sp = 20 + 30 * nz(i * 1.3, o.seed + 503);
      const x = cx + Math.cos(a) * sp * u * 1.3, y = cy + Math.sin(a) * sp * u * SY - 10 * u;
      if (nz(i * 5.1 + u * 9, o.seed + 507) < u * 2.2) continue;   // 越来越稀
      p.px(Math.round(x), Math.round(y), u < 0.1 ? DU[4] : DU[3]);
    }
  }
}

// ---------------------------------------------------------------- S1 战意：举盾下劈（立起的竖直弧，朝 +x，左侧游戏里翻转）+ 碎石 / 尘墙
function chop(p, t, o, C, ACC, ST, AM, DU) {
  const raw = o.view === "raw", el = +o.el, n = C.length, SY = +o.SY;
  const Rv = [44, 48, 52][el], Wv = [12, 14, 17][el], cx = 8, zc = 26;
  const A0 = 115 * D2R, A1 = -25 * D2R;                    // 从头后上方劈到身前地面
  const headA = A0 + (A1 - A0) * (0.6 + 0.4 * clamp(t / 0.067));
  const tailA = A0 + (A1 - A0) * 0.3 * smooth(0.07, 0.34, t);
  const hot = t < 0.067, cool = smooth(0.07, 0.4, t);
  if (cool < 0.75) {
    const B = Rv + 4;
    p.shade(cx - B, -(zc + B), cx + B, -(zc - B), (x, y, out) => {
      const dx = x - cx, dz = -y - zc, r = Math.hypot(dx, dz);
      const W = Wv * (1 - 0.6 * cool);
      if (r > Rv + 1.5 || r < Rv - W - 1) return;
      const a = Math.atan2(dz, dx);
      if (a > tailA || a < headA) return;
      const u = (tailA - a) / Math.max(0.001, tailA - headA);  // 0 刀尾 → 1 刀头（落地端）
      const wr = W * Math.min(1, Math.pow(u / 0.5, 0.8));
      const q = (Rv - r) / Math.max(0.8, wr);
      if (q < 0 || q > 1 || wr < 0.8) return;
      let ci = q < 0.16 ? (hot ? n - 1 : n - 2) : q < 0.4 ? n - 3 : q < 0.66 ? n - 4 : n - 5;
      if (hot && u > 0.88 && q < 0.35) ci = n - 1;
      if (q > 0.86) out.a = 0.55;
      ci = clamp(ci - Math.round(cool * 2.5), 1, n - 1);
      out.c = C[ci];
      if (out.a === undefined) out.a = 1;
      if (el >= 2 && !hot && q > 0.16 && q < 0.3) out.c = ACC;
    });
  }
  if (raw) { p.light(cx + Rv * 0.7, -zc, C[n - 2], 0.6 * (1 - cool)); return; }
  // 碎石：从落点和冲击环边顶起的地块（2–3 格，受重力落回）；精一加尘墙（环边一圈往上冒的尘团）
  const R = +o.R, u = t - 0.04;
  if (u > 0) {
    const N = 10 + 4 * el;
    for (let i = 0; i < N; i++) {
      const a = TAU * nz(i * 2.3, o.seed + 601), rr = R * (0.25 + 0.6 * nz(i * 1.9, o.seed + 603));
      const vy = 70 + 90 * nz(i * 3.7, o.seed + 605), vr = 15 + 25 * nz(i * 4.3, o.seed + 607);
      const gx = Math.cos(a) * (rr + vr * u), gy = Math.sin(a) * (rr + vr * u) * SY;
      const z = vy * u - 330 * u * u;
      if (z < 0) continue;
      const sz = nz(i * 6.1, o.seed + 609) > 0.55 ? 3 : 2, X = Math.round(gx), Y = Math.round(gy - z);
      for (let dx = 0; dx < sz; dx++) for (let dy = 0; dy < sz - (dx === sz - 1 ? 1 : 0); dy++) p.px(X + dx, Y + dy, dy === 0 ? DU[4] : DU[2]);
    }
  }
  if (el >= 1 && u > 0 && u < 0.45) {   // 精一起：尘墙——环边一圈尘团往上冒、慢慢散（团块，不撒细点）
    const m = 12 + 4 * el;
    for (let j = 0; j < m; j++) {
      const a = TAU * (j + nz(j * 1.3, o.seed + 611) * 0.7) / m;
      const h = (5 + 7 * nz(j * 2.1, o.seed + 613)) * ease.outCubic(clamp(u / 0.2));
      const gx = Math.cos(a) * R * (0.9 + 0.1 * nz(j, o.seed + 615)), gy = Math.sin(a) * R * SY;
      const rr = 2 + (nz(j * 3.7, o.seed + 619) > 0.5 ? 1 : 0) - (u > 0.3 ? 1 : 0);
      for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr; dx <= rr; dx++) {
        if (dx * dx + dy * dy > rr * rr + 0.5) continue;
        if (u > 0.25 && ((dx + dy + j) & 1)) continue;                 // 散掉前抖动变稀
        p.px(Math.round(gx + dx), Math.round(gy - h + dy), dy < 0 ? DU[4] : DU[3]);
      }
    }
  }
}

// 裂网冲击环（贴地）：环边（断续、不规整）+ 一圈深色内边；落点往外跑不规整分叉裂缝，先亮后冷；精二裂缝芯熔成暖金、冷得慢
function crackPaths(o) {
  const R = +o.R, el = +o.el, N = [5, 7, 9][el];
  const paths = [];
  const P = [16, 0];
  for (let j = 0; j < N; j++) {
    let a = TAU * (j + (nz(j * 1.7, o.seed + 701) - 0.5) * 0.7) / N, x = P[0] + Math.cos(a) * 7, y = P[1] + Math.sin(a) * 7;
    const L = R * (0.5 + 0.45 * nz(j * 2.9, o.seed + 703));
    const pts = [[x, y, 0]];
    let s = 0;
    while (s < L) {
      a += (nz(s * 0.25 + j * 11, o.seed + 705) - 0.5) * 0.32;
      x += Math.cos(a) * 1; y += Math.sin(a) * 1; s += 1;
      pts.push([x, y, s / L]);
    }
    paths.push(pts);
    if (nz(j * 4.1, o.seed + 707) > 0.4) {   // 分叉
      const k = Math.floor(pts.length * (0.35 + 0.3 * nz(j * 5.3, o.seed + 709)));
      let [bx, by] = pts[k], ba = a + (nz(j * 6.7, o.seed + 711) > 0.5 ? 0.8 : -0.8);
      const bp = [[bx, by, pts[k][2]]], BL = L * 0.4;
      for (let s2 = 0; s2 < BL; s2++) { ba += (nz(s2 * 0.3 + j * 7, o.seed + 713) - 0.5) * 0.35; bx += Math.cos(ba); by += Math.sin(ba); bp.push([bx, by, pts[k][2] + s2 / L]); }
      paths.push(bp);
    }
  }
  return paths;
}

function quake(p, t, o, C, ACC, ST, AM, DU) {
  const R = +o.R, SY = o.view === "raw" ? 1 : +o.SY, el = +o.el, n = C.length;
  ring(p, t, o, C, ACC, DU);
  if (o.view === "raw") return;
  const grow = clamp(t / 0.12), fade = smooth(0.2, 0.6, t);
  if (fade >= 0.99) return;
  for (const pts of crackPaths(o)) {
    for (const [x, y, f] of pts) {
      if (f > grow * 1.05) break;
      if (nz(f * 40 + x, o.seed + 715) < fade * 0.9) continue;   // 冷了以后断成一节节
      const X = Math.round(x), Y = Math.round(y * SY);
      let c;
      if (el >= 2) c = t < 0.07 ? WHITE : t < 0.3 ? ACC : t < 0.45 ? AM[3] : DU[1];
      else c = t < 0.07 ? WHITE : t < 0.2 ? C[n - 2] : t < 0.35 ? C[n - 4] : DU[1];
      p.px(X, Y, c);
      if (f < 0.5 && t < 0.35) p.px(X, Y + 1, DU[0]);           // 近落点那一半裂缝更宽（下沿压暗）
    }
  }
  // 落点压暗的坑
  if (fade < 0.95) p.shade(4, -6, 28, 6, (x, y, out) => {
    const d = Math.hypot((x - 16) / 10, y / (10 * SY));
    if (d > 1) return;
    out.c = DU[0]; out.a = 0.5 * (1 - fade) * (1 - d * 0.5);
  });
}

// ---------------------------------------------------------------- 贴地冲击环（般若之重 / 盾墙反震 / 战意 / 力之锯起手）
function ring(p, t, o, C, ACC, DU) {
  const R = +o.R, SY = o.view === "raw" ? 1 : +o.SY, el = +o.el, n = C.length;
  const g = ease.outCubic(clamp(t / 0.2)), r = R * (0.4 + 0.6 * g), fade = smooth(0.16, 0.5, t);
  if (fade >= 0.995) return;
  const th = (el >= 1 ? 3 : 2) + (1 - g) * 2, m = Math.ceil(r * TAU * 1.3);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, ca = Math.cos(a), sa = Math.sin(a);
    const rr = r + 1.6 * nz(a * 5, o.seed + 11) + 1.0 * nz(a * 13, o.seed + 17);
    if (nz(a * 3.1, o.seed + 23) < 0.18 + fade * 0.5) continue;   // 断口
    for (let k = 0; k < th; k += 0.5) {
      const q = k / th;
      let ci = q < 0.3 ? n - 2 : q < 0.7 ? n - 3 : n - 5;
      if (t < 0.07 && q < 0.4) ci = n - 1;
      if (sa < -0.2) ci -= 1;
      ci = clamp(ci - Math.round(fade * 2.5), 1, n - 1);
      p.dot(Math.round(ca * (rr - k)), Math.round(sa * (rr - k) * SY), C[ci], 1 - fade * 0.6);
    }
  }
  if (fade < 0.7) for (let j = 0; j < m; j++) {   // 一圈 2 格深色内边
    const a = (j / m) * TAU;
    if (nz(a * 3.1, o.seed + 23) < 0.18 + fade * 0.5) continue;
    const rr = r + 1.6 * nz(a * 5, o.seed + 11) - th - 1;
    for (let k = 0; k < 2; k += 0.5) p.px(Math.round(Math.cos(a) * (rr - k)), Math.round(Math.sin(a) * (rr - k) * SY), C[1]);
  }
  if (o.view === "raw") p.glowRing && p.glowRing(0, 0, r, 3, C[n - 2], 0.4 * (1 - fade));
}

// ---------------------------------------------------------------- S2 荆棘：身边一圈地刺破土（钢灰，刺尖琥珀；精二两圈、更高、刺尖白热转暖金）
function spikes(o) {
  const el = +o.el, rows = el >= 2 ? [[20, 9], [34, 12]] : [[24, 10]];
  const out = [];
  rows.forEach(([rr, N], ri) => {
    for (let i = 0; i < N; i++) {
      const sd = ri * 31 + i;
      const a = TAU * (i + nz(sd * 1.3, o.seed + 801) * 0.6) / N + ri * 0.4;
      const r = rr * (0.85 + 0.3 * nz(sd * 2.1, o.seed + 803));
      const h = (el >= 2 ? 22 : 16) * (0.55 + 0.6 * nz(sd * 3.3, o.seed + 805)) * (ri === 1 ? 0.85 : 1);
      out.push({ gx: Math.cos(a) * r, gy: Math.sin(a) * r * +o.SY, h, w: 3 + Math.round(2 * nz(sd * 4.7, o.seed + 807)), lean: Math.cos(a) * 0.35, d: 0.025 * nz(sd * 5.9, o.seed + 809) + ri * 0.04 });
    }
  });
  return out.sort((A, B) => A.gy - B.gy);
}

function thorns(p, t, o, C, ACC, ST, AM) {
  const raw = o.view === "raw", el = +o.el, half = o.half || "all";
  for (const s of spikes(o)) {
    if (half === "back" && s.gy >= 0) continue;
    if (half === "front" && s.gy < 0) continue;
    const u = t - s.d;
    if (u < 0) continue;
    const up = ease.outBack ? ease.outBack(clamp(u / 0.08)) : ease.outCubic(clamp(u / 0.08));
    const sink = ease.inQuad(clamp((u - 0.36) / 0.2));
    const h = s.h * up * (1 - sink);
    if (h < 1) continue;
    const hot = u < 0.12;
    for (let z = 0; z <= h; z += 0.5) {
      const k = z / h, hw = s.w * (1 - k);
      const cx = s.gx + s.lean * z;
      for (let x = Math.round(cx - hw); x <= Math.round(cx + hw); x++) {
        const sd = (x - cx) / Math.max(0.5, hw);        // 光从左上来
        let c = sd < -0.3 ? ST[4] : sd < 0.3 ? ST[3] : ST[1];
        if (k > 0.78) c = hot ? WHITE : el >= 2 ? (sd < 0 ? AM[5] : AM[4]) : AM[3];   // 刺尖
        else if (k > 0.6 && sd < 0.3) c = el >= 2 ? AM[3] : ST[4];
        if (raw) c = sd < 0 ? ST[4] : ST[2];
        p.px(x, Math.round(s.gy - (raw ? 0 : z)), c);
      }
    }
    if (raw) p.light(Math.round(s.gx), Math.round(s.gy), AM[3], 0.25);
  }
}

function thornsGround(p, t, o, C, ACC, ST, AM, DU) {
  if (o.view === "raw") return;
  const fade = smooth(0.4, 0.62, t), SY = +o.SY;
  if (fade >= 0.99) return;
  for (const s of spikes(o)) {   // 每根刺底下一小片破土（深色 + 两三道短裂）
    const u = t - s.d;
    if (u < 0) continue;
    for (let k = 0; k < 3; k++) {
      const a = TAU * nz(s.gx * 3 + k, o.seed + 821), L = 2 + 3 * nz(s.gy * 5 + k, o.seed + 823);
      for (let d = 0; d < L; d++) p.dot(Math.round(s.gx + Math.cos(a) * d), Math.round(s.gy + Math.sin(a) * d * SY), DU[0], 0.8 * (1 - fade));
    }
    for (let x = -s.w - 1; x <= s.w + 1; x++) p.dot(Math.round(s.gx + x), Math.round(s.gy) + 1, C[0], 0.55 * (1 - fade));
  }
}

// ---------------------------------------------------------------- S2 热砂（循环，跟着区域）：只画边 + 内侧淡渐变 + 几点热光
function sand(p, t, o, C, ACC, ST, AM) {
  const R = +o.R, SY = +o.SY, ph = (t / 0.4) * TAU, el = +o.el;
  const rad = (a) => R * (0.82 + 0.18 * nz(a * 1.4 + 3, o.seed + 901));
  const m = Math.ceil(R * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU, r = rad(a), ca = Math.cos(a), sa = Math.sin(a);
    if (nz(a * 2.6, o.seed + 905) < 0.22) continue;   // 边断续
    p.px(Math.round(ca * r), Math.round(sa * r * SY), sa < 0 ? AM[2] : AM[3]);
    p.px(Math.round(ca * (r - 1)), Math.round(sa * (r - 1) * SY), AM[1]);
  }
  // 内侧：一圈 2 格暗琥珀内边（颜色阶代替透明度网点，docs/246 §4 同理）
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 2.6, o.seed + 905) < 0.22) continue;
    const r = rad(a) - 2;
    for (let k = 0; k < 2; k += 0.5) p.dot(Math.round(Math.cos(a) * (r - k)), Math.round(Math.sin(a) * (r - k) * SY), AM[0], 0.85);
  }
  // 热光：几点在区域里慢慢闪（精二多一倍）
  const N = el >= 2 ? 10 : 5;
  for (let i = 0; i < N; i++) {
    const a = TAU * nz(i * 2.3, o.seed + 911), d = R * 0.75 * Math.sqrt(nz(i * 3.9, o.seed + 913));
    const b = 0.5 + 0.5 * Math.sin(ph + i * 2.1);
    if (b < 0.35) continue;
    p.px(Math.round(Math.cos(a) * d), Math.round(Math.sin(a) * d * SY - b * 2), b > 0.85 ? AM[5] : AM[4]);
  }
}

// ---------------------------------------------------------------- S3 力之锯：直线撕裂（贴地撕裂沟 + 低处锯线 + 远端暖金火星）
function rip(p, t, o, C, ACC, ST, AM, DU) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, th = +o.dir * D2R, n = C.length, L = +o.L;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, H0 = raw ? 0 : 7;
  const reach = L * (0.65 + 0.35 * clamp(t / 0.067)), tail = L * 0.8 * smooth(0.07, 0.3, t);
  const hot = t < 0.05, cool = smooth(0.05, 0.32, t);
  if (cool < 0.8 && reach - tail > 2) {
    for (let s = Math.max(6, tail); s <= reach; s += 0.5) {
      const u = (s - tail) / Math.max(1, reach - tail);
      const th2 = Math.max(1, (raw ? 6 : 5) * (1 - 0.6 * cool) * Math.min(1, u * 3));
      const tooth = nz(s * 0.45, o.seed + 1001) > 0.55 ? Math.round(1 + 3 * nz(s * 1.7, o.seed + 1003)) : 0;   // 上沿不等距锯齿
      const X = fx * s, Y = fy * s - H0;
      for (let z = -1; z < th2 + tooth; z++) {
        let ci = z < 1 ? n - 1 : z < th2 * 0.5 ? n - 3 : z < th2 ? n - 4 : n - 2;
        if (hot || u > 0.9) ci = z < th2 ? n - 1 : n - 2;
        ci = clamp(ci - Math.round(cool * 3), 1, n - 1);
        p.px(Math.round(X), Math.round(Y - z), C[ci]);
      }
    }
  }
  if (raw) { for (let s = 10; s < L; s += 12) p.light(fx * s, fy * s, C[n - 2], 0.4 * (1 - cool)); return; }
  // 火星：远端与沿途（暖金，受重力）
  const u = t - 0.02;
  if (u > 0 && u < 0.4) for (let i = 0; i < 18; i++) {
    const s0 = i < 8 ? L * (0.9 + 0.1 * nz(i, o.seed + 1011)) : L * nz(i * 2.7, o.seed + 1013);
    const a = TAU * nz(i * 3.1, o.seed + 1015), sp = 50 + 70 * nz(i * 1.9, o.seed + 1017), up = 40 + 70 * nz(i * 4.3, o.seed + 1019);
    const x = fx * s0 + Math.cos(a) * sp * u, gy = fy * s0 + Math.sin(a) * sp * u * SY, z = H0 + up * u - 380 * u * u;
    if (z < 0) continue;
    p.px(Math.round(x), Math.round(gy - z), u < 0.08 ? WHITE : u < 0.22 ? ACC : AM[3]);
  }
}

function ripGround(p, t, o, C, ACC, ST, AM, DU) {
  if (o.view === "raw") return;
  const SY = +o.SY, th = +o.dir * D2R, L = +o.L, W = +o.W, n = C.length;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nxp = -Math.sin(th), nyp = Math.cos(th) * SY;
  const reach = L * (0.65 + 0.35 * clamp(t / 0.067)), fade = smooth(0.25, 0.6, t), hot = t < 0.13;
  if (fade >= 0.99) return;
  for (let s = 6; s <= reach; s += 0.5) {
    const k = s / L;
    if (nz(s * 0.9, o.seed + 1101) < fade * 0.95) continue;    // 冷了断成一节节
    // 沟：中线 2 格暗 + 一格亮芯（刚撕开时青白，冷成暗）
    for (let w = -1; w <= 1; w++) {
      const X = Math.round(fx * s + nxp * w * 0.8), Y = Math.round(fy * s + nyp * w * 0.8);
      p.px(X, Y, w === 0 ? (t < 0.07 ? WHITE : hot ? C[n - 3] : t < 0.3 ? C[3] : DU[0]) : DU[0]);
    }
    // 两侧撕开的翻边：不等距的齿痕，伸到判定宽度
    const e = nz(s * 0.37, o.seed + 1103);
    if (e > 0.5) {
      const side = nz(s * 1.3, o.seed + 1105) > 0.5 ? 1 : -1, len = (W / 2) * (0.35 + 0.65 * nz(s * 2.1, o.seed + 1107)) * Math.min(1, k * 4);
      for (let d = 2; d < len; d += 1) {
        const X = Math.round(fx * (s + d * 0.25) + nxp * side * d), Y = Math.round(fy * (s + d * 0.25) + nyp * side * d);
        p.dot(X, Y, d > len - 2 ? C[2] : DU[1], 0.85 * (1 - fade));
      }
    }
  }
}

// ---------------------------------------------------------------- S3 起手：身边腰高三道青绿弧旋起（原作 S3 buff 鬼火弧）；持续：脚下一圈断续青绿边 + 转动的齿印
function s3swirl(p, t, o, C, ACC) {
  const n = C.length, SY = +o.SY, H0 = 14, R = +o.R;
  const fade = smooth(0.3, 0.55, t);
  if (fade >= 0.99) return;
  for (let k = 0; k < 3; k++) {
    const a0 = k * TAU / 3 + t * 9, span = 1.4;
    for (let a = a0; a < a0 + span; a += 0.6 / R) {
      const u = (a - a0) / span, r = R * (0.85 + 0.25 * u) * (0.6 + 0.4 * ease.outCubic(clamp(t / 0.15)));
      const w = 3 * Math.sin(Math.PI * u);
      for (let d = 0; d < w; d += 0.5) {
        const X = Math.round(Math.cos(a) * (r - d)), Y = Math.round(Math.sin(a) * (r - d) * SY - H0 - 6 * u);
        const ci = clamp((d < 1 ? n - 2 : n - 4) - Math.round(fade * 3) + (u > 0.85 && t < 0.15 ? 1 : 0), 1, n - 1);
        p.px(X, Y, C[ci]);
      }
    }
  }
}

function s3aura(p, t, o, C) {
  const R = +o.R, SY = +o.SY, ph = (t / 0.4) * TAU / 3, n = C.length;
  const m = Math.ceil(R * TAU * 1.2);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 2.0, o.seed + 1201) < 0.3) continue;
    const ca = Math.cos(a), sa = Math.sin(a);
    p.px(Math.round(ca * R), Math.round(sa * R * SY), sa < 0 ? C[3] : C[4]);
    const tooth = ((a + ph) % (TAU / 7)) < 0.12;                  // 转动的齿印
    if (tooth) p.px(Math.round(ca * (R + 1)), Math.round(sa * (R + 1) * SY), C[n - 3]);
  }
}

// ---------------------------------------------------------------- 精二「般若回旋」：横转着飞出去的盾「般若」（循环），腰高；地上影子
// 11-05 用户「星熊飞出去的是盾而不是锯子」：不画锯齿。盾在水平面里转（俯视斜角压扁），轮廓是上宽下收的盾形，
// 钢灰盾面左上受光、浅钢盾缘，盾面中间鬼面（一道亮钢眉 + 两点青绿眼），转到侧面时变窄；外面两道短速度弧。
function saw(p, t, o, C, ACC, ST) {
  const raw = o.view === "raw", SY = raw ? 1 : +o.SY, H0 = raw ? 0 : 11, n = C.length;
  const HW = 9, HH = 13;                                              // 盾的半宽 / 半高（盾自身平面里）
  const ph = (t / 0.4) * TAU;                                         // 0.4 秒转一圈（6 帧）
  const ca = Math.cos(ph), sa = Math.sin(ph);
  const B = 15;
  // 盾自身坐标 (u 横, v 竖) → 水平面 (x, z)：盾平躺在水平面里转（飞盘式），世界 x = u·cos − v·sin，深度 = u·sin + v·cos
  p.shade(-B, -B * SY - H0, B, B * SY - H0, (x, y, out) => {
    const pz = (y + H0) / SY;
    const u = x * ca + pz * sa, v = -x * sa + pz * ca;               // 逆转回盾自身坐标
    const vv = v / HH;
    if (vv < -1 || vv > 1) return;
    const half = HW * (vv < 0 ? 1 - 0.1 * vv * vv : 1 - 0.55 * vv * vv);   // 上宽圆肩、下沿收成钝尖
    if (Math.abs(u) > half) return;
    out.a = 1;
    const edge = half - Math.abs(u) < 1.2 || 1 - Math.abs(vv) < 0.09;
    if (edge) { out.c = ST[4]; if (x + pz < -6) out.c = ST[5]; return; }   // 盾缘（左上那段更亮）
    const lit = (-x - pz) / (B * 1.2);
    out.c = lit > 0.2 ? ST[3] : lit > -0.25 ? ST[2] : ST[1];
    if (Math.abs(vv + 0.15) < 0.09 && Math.abs(u) < half * 0.6) out.c = ST[4];          // 鬼面眉
    if (Math.abs(vv - 0.05) < 0.08 && Math.abs(Math.abs(u) - half * 0.32) < 0.9) out.c = C[n - 2];   // 两点青绿眼
  });
  for (let k = 0; k < 2; k++) {                                       // 速度弧：盾外两道短弧（顺转向）
    const a0 = ph + k * Math.PI;
    for (let a = a0; a < a0 + 1.0; a += 0.12) p.px(Math.round(Math.cos(a) * (B + 1)), Math.round(Math.sin(a) * (B + 1) * SY - H0), a < a0 + 0.4 ? C[n - 2] : C[n - 4]);
  }
  if (raw) p.light(0, 0, C[n - 2], 0.5);
}

function sawGround(p, t, o, C) {
  if (o.view === "raw") return;
  const R = +o.R, SY = +o.SY;
  p.shade(-R, -R * SY, R, R * SY, (x, y, out) => {
    const d = Math.hypot(x / R, y / (R * SY));
    if (d > 1) return;
    if (d > 0.75) return;
    out.c = C[1]; out.a = 1;   // 实色暗椭圆（半透明会被抖成网点）
  });
}

// ---------------------------------------------------------------- 技能连携 v2「举盾」（skill_link cover）：瞬到队长身侧立起鬼面大盾，举 1.0 秒、再 0.5 秒散掉（游戏让盾跟着队长走）
// up：大盾往下一顿立定（第 0 拍白热上沿、落下 4 格），举盾期间盾缘一点亮光沿边慢慢走一圈；最后 0.5 秒抖动变稀散掉。盾面始终朝镜头，dir 只决定左右（翻转）
// gd：立定那一下脚下一小圈冲击环 + 两侧尘；举盾期间盾脚下压暗
function cover(p, t, o, C, ACC, ST, AM, DU) {
  const n = C.length, HW = 14, HH = 32;
  const drop = 4 * (1 - ease.outCubic(clamp(t / 0.1))), fade = smooth(1.0, 1.5, t), hot = t < 0.067;
  if (fade >= 0.99) return;
  const per = 2 * HW + 2 * HH, glint = ((t - 0.1) / 0.9) * per;   // 亮点沿盾缘走的位置
  for (let w = -HW; w <= HW; w += 0.5) {
    const u = Math.abs(w) / HW, top = HH * (1 - 0.35 * u * u), bot = 2 * u;
    for (let z = bot; z <= top; z += 0.5) {
      if (fade > 0.02 && nz(w * 3 + z * 7, o.seed + 1601) < fade) continue;
      const rim = u > 0.86 || z > top - 1.5 || z < bot + 1;
      let c = rim ? C[n - 3] : (w < 0 ? ST[3] : ST[2]);
      if (!rim && Math.abs(z - HH * 0.55) < 3 && u < 0.4) c = ST[4];
      if (!rim && Math.abs(z - HH * 0.42) < 1 && u > 0.12 && u < 0.3) c = C[n - 2];
      if (z > top - 1.5) c = hot ? WHITE : C[n - 2];
      if (rim && t > 0.1 && t < 1.0) {   // 盾缘亮点：沿左边往上、过顶、沿右边往下
        const pos = w < 0 ? (top - z) : (w <= 0 ? 0 : HH + 2 * HW - (top - z));
        const along = z > top - 1.5 ? HH + (w + HW) : pos;
        if (Math.abs(along - glint) < 2.5) c = WHITE;
      }
      p.px(Math.round(w), Math.round(-z - drop), c);
    }
  }
}

function coverGround(p, t, o, C, ACC, ST, AM, DU) {
  const fade = smooth(1.0, 1.5, t), n = C.length, SY = +o.SY;
  if (fade >= 0.99) return;
  for (let w = -14; w <= 14; w += 1) p.dot(Math.round(w), 1, C[0], 0.55 * (1 - fade));   // 盾脚下压暗
  if (t < 0.4) {
    const g = ease.outCubic(clamp(t / 0.2)), r = 10 + 22 * g, f2 = smooth(0.15, 0.4, t);
    const m = Math.ceil(r * TAU);
    for (let j = 0; j < m; j++) {
      const a = (j / m) * TAU;
      if (nz(a * 3.3, o.seed + 1611) < 0.25 + f2 * 0.6) continue;
      p.px(Math.round(Math.cos(a) * r), Math.round(Math.sin(a) * r * SY), t < 0.07 ? C[n - 2] : C[n - 4]);
    }
    for (let i = 0; i < 10; i++) {   // 两侧尘
      const side = i % 2 ? 1 : -1, u = t;
      const x = side * (14 + 50 * u * (0.5 + nz(i, o.seed + 1613))), y = -2 - 20 * u + 60 * u * u;
      if (nz(i * 4 + t * 20, o.seed + 1615) < f2) continue;
      p.px(Math.round(x), Math.round(y), DU[3]);
    }
  }
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), ST = fit(o.steel, 6), AM = fit(o.amber, 6), DU = fit(o.dust, 5), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "sweep": return gd ? sweepGround(p, t, o, C, ACC, ST, AM, DU) : sweep(p, t, o, C, ACC, ST);
    case "slam": return gd ? quake(p, t, o, C, ACC, ST, AM, DU) : chop(p, t, o, C, ACC, ST, AM, DU);
    case "ring": return ring(p, t, o, C, ACC, DU);
    case "thorns": return gd ? thornsGround(p, t, o, C, ACC, ST, AM, DU) : thorns(p, t, o, C, ACC, ST, AM);
    case "sand": return gd ? sand(p, t, o, C, ACC, ST, AM) : undefined;
    case "rip": return gd ? ripGround(p, t, o, C, ACC, ST, AM, DU) : rip(p, t, o, C, ACC, ST, AM, DU);
    case "s3cast": return gd ? ring(p, t, o, C, ACC, DU) : s3swirl(p, t, o, C, ACC);
    case "s3aura": return gd ? s3aura(p, t, o, C) : undefined;
    case "saw": return gd ? sawGround(p, t, o, C) : saw(p, t, o, C, ACC, ST);
    case "qi": return gd ? qiWaveGround(p, t, o, C, ACC, ST, AM, DU) : qiWave(p, t, o, C, ACC, ST, AM, DU);
    case "cover": return gd ? coverGround(p, t, o, C, ACC, ST, AM, DU) : cover(p, t, o, C, ACC, ST, AM, DU);
    case "shove": return gd ? shoveGround(p, t, o, C, ACC, ST, AM, DU) : shove(p, t, o, C, ACC, ST, AM, DU);
  }
}

// ---------------------------------------------------------------- 后期剑气（growth/late_shape 给近战的额外一击，vis_growth._fire_qi）：星熊版 = 盾击冲击波
// 一次出手的几道剑气在游戏里合成一道（S = 横向半宽，按道数 1 / 2 / 3+ 取三档），贴地往前推的一堵矮浪墙：前凸、顶上白唇；
// 精一更高 + 两侧甩钢屑；精二顶上压一道钢灰盾缘 + 暖金火星。三帧：0 热白 / 1 常态 / 2 碎开散掉（游戏按剑气年龄与剩余寿命挑帧）。
function qiWave(p, t, o, C, ACC, ST, AM, DU) {
  const SY = +o.SY, th = +o.dir * D2R, el = +o.el, n = C.length, S = +o.S, H = [7, 9, 10][el];
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const f = Math.min(2, Math.round(t * 15)), brk = f === 2;
  const cols = [];
  for (let w = -S; w <= S; w += 0.5) {
    const u = w / S, k = 1 - u * u;
    if (brk && nz(w * 1.7, o.seed + 1401) < 0.45) continue;            // 碎开：一段段断掉
    const bulge = 5 * k, h = H * Math.pow(k, 0.45) * (0.8 + 0.35 * nz(w * 0.9, o.seed + 1403)) * (brk ? 0.5 : 1);
    cols.push({ w, bulge, h, x: fx * bulge + nx * w, y: fy * bulge + ny * w, u });
  }
  cols.sort((A, B) => A.y - B.y);
  for (const c of cols) {
    for (let d = -3; d <= 0; d++) {   // 墙厚：后面暗两阶 → 前脸
      const hx = c.x + fx * d, hy = c.y + fy * d, hd = c.h * (1 + d * 0.08);
      for (let z = 0; z <= hd; z += 0.5) {
        const q = z / Math.max(1, hd);
        let ci = q > 0.8 ? n - 2 : q > 0.5 ? n - 3 : q > 0.2 ? n - 4 : n - 5;
        if (f === 0 && q > 0.6 && d === 0) ci = n - 1;
        if (brk) ci -= 2;
        ci += d < 0 ? Math.max(-2, d) : 0;
        p.px(Math.round(hx), Math.round(hy - z), C[clamp(ci, 1, n - 1)]);
      }
    }
    if (el >= 2 && !brk) {   // 精二：浪墙顶上压一道钢灰盾缘（盾击的那条边），刚出手一帧白热（11-05 用户：飞出去的是盾，不是锯子，所以不画锯齿）
      p.px(Math.round(c.x), Math.round(c.y - c.h - 1), f === 0 ? WHITE : ST[4]);
      if (Math.abs(c.u) < 0.7) p.px(Math.round(c.x), Math.round(c.y - c.h - 2), ST[3]);
    }
  }
  if (el >= 1) {                                                       // 两侧甩出的钢屑 / 精二暖金火星
    for (let i = 0; i < 6 + 2 * el; i++) {
      const side = i % 2 ? 1 : -1, u = (f + 0.5) / 15;
      const x = side * S * (0.9 + 0.3 * nz(i, o.seed + 1409)) + side * 60 * u, z = 4 + 40 * u - 200 * u * u;
      const X = fx * (2 + 30 * u * nz(i * 3, o.seed + 1411)) + nx * x, Y = fy * (2 + 30 * u) + ny * x - z;
      const gold = el >= 2 && i % 3 === 0;
      p.px(Math.round(X), Math.round(Y), gold ? (f === 0 ? WHITE : ACC) : f === 0 ? ST[5] : ST[3]);
    }
  }
}

function qiWaveGround(p, t, o, C, ACC, ST, AM, DU) {
  const SY = +o.SY, th = +o.dir * D2R, S = +o.S, el = +o.el;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const f = Math.min(2, Math.round(t * 15));
  for (let w = -S; w <= S; w += 0.5) {                                 // 浪墙脚下压暗 + 往后犁出的一截暗沟
    const u = w / S, k = 1 - u * u, bulge = 5 * k;
    for (let s = 0; s < 3 + 9 * k; s += 1) {
      const X = fx * (bulge - s) + nx * w, Y = fy * (bulge - s) + ny * w;
      p.dot(Math.round(X), Math.round(Y), s < 2 ? C[0] : DU[1], (s < 2 ? 0.6 : 0.4) * (f === 2 ? 0.5 : 1));
    }
  }
  for (let i = 0; i < 8; i++) {                                        // 两端甩起的尘点
    const side = i % 2 ? 1 : -1, d = S + 2 + 4 * nz(i, o.seed + 1421) + f * 2;
    p.px(Math.round(nx * side * d - fx * 3 * nz(i * 2, o.seed + 1423)), Math.round(ny * side * d - fy * 3 - f), f === 0 ? DU[4] : DU[3]);
  }
}

// ---------------------------------------------------------------- 连携技「举盾推挡」：冲到队长身边，大盾立在外侧往外一推；以队长为心一圈推开的冲击环 + 放射推痕
// up（方向件，原点 = 盾落点）：一面立起的鬼面大盾（钢灰盾面、青绿盾缘、白热上沿），第 0–1 帧往外推 10 格，前面两道往外扩的气浪弧；之后抖动变稀散掉
// gd（原点 = 队长脚下）：冲击环（半径 70 = 140 世界）+ 16 道不等长放射推痕 + 环边尘团
function shove(p, t, o, C, ACC, ST, AM, DU) {
  const SY = +o.SY, th = +o.dir * D2R, n = C.length;
  const fx = Math.cos(th), fy = Math.sin(th) * SY, nx = -Math.sin(th), ny = Math.cos(th) * SY;
  const push = 10 * ease.outCubic(clamp(t / 0.12)), fade = smooth(0.25, 0.5, t), hot = t < 0.067;
  if (fade >= 0.99) return;
  const HW = 13, HH = 30;
  for (let w = -HW; w <= HW; w += 0.5) {
    const u = Math.abs(w) / HW, top = HH * (1 - 0.35 * u * u), bot = 2 * u;   // 盾形：上宽圆肩、下沿收
    const bx = fx * push + w * (0.75 + 0.25 * Math.abs(Math.cos(th))), by = fy * push;   // 盾面朝镜头，只往外推
    for (let z = bot; z <= top; z += 0.5) {
      if (fade > 0.3 && nz(w * 3 + z * 7, o.seed + 1501) < fade) continue;   // 散掉前抖动变稀
      const rim = u > 0.86 || z > top - 1.5 || z < bot + 1;
      let c = rim ? C[n - 3] : (w < 0 ? ST[3] : ST[2]);
      if (!rim && Math.abs(z - HH * 0.55) < 3 && u < 0.4) c = ST[4];          // 鬼面：盾面中段一道亮钢眉
      if (!rim && Math.abs(z - HH * 0.42) < 1 && u > 0.12 && u < 0.3) c = C[n - 2];   // 两点青绿眼
      if (z > top - 1.5) c = hot ? WHITE : C[n - 2];
      p.px(Math.round(bx), Math.round(by - z), c);
    }
  }
  if (t < 0.3) for (let k = 0; k < 2; k++) {                                // 气浪弧：盾前往外扩
    const d = 6 + push + (t * 140) * (1 + 0.4 * k), span = HW * (1.2 + 0.5 * k);
    for (let w = -span; w <= span; w += 0.5) {
      const u = w / span;
      if (nz(w * 1.3 + k * 9, o.seed + 1503) < 0.25) continue;
      const X = fx * (d - 4 * u * u) + nx * w, Y = fy * (d - 4 * u * u) + ny * w - HH * 0.4 * (1 - u * u);
      p.px(Math.round(X), Math.round(Y), t < 0.14 ? C[n - 2] : C[n - 4]);
    }
  }
}

function shoveGround(p, t, o, C, ACC, ST, AM, DU) {
  const R = +o.R, SY = +o.SY, n = C.length;
  ring(p, t, o, C, ACC, DU);
  const g = ease.outCubic(clamp(t / 0.18)), fade = smooth(0.2, 0.5, t);
  if (fade >= 0.99) return;
  for (let i = 0; i < 16; i++) {                                           // 放射推痕：被推开的敌人在地上拖出的痕
    const a = TAU * (i + nz(i * 1.9, o.seed + 1511) * 0.6) / 16, L = R * (0.25 + 0.3 * nz(i * 2.7, o.seed + 1513));
    const r1 = R * 0.95 * g, r0 = Math.max(R * 0.3, r1 - L);
    for (let r = r0; r <= r1; r += 1) {
      if (nz(r * 0.8 + i * 5, o.seed + 1515) < fade * 0.9) continue;
      const q = (r - r0) / Math.max(1, r1 - r0);
      p.px(Math.round(Math.cos(a) * r), Math.round(Math.sin(a) * r * SY), q > 0.75 ? (t < 0.1 ? C[n - 2] : C[n - 4]) : q > 0.4 ? C[3] : DU[2]);
    }
  }
}
