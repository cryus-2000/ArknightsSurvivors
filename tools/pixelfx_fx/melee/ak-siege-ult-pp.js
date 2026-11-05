// 推进之王终结技 Q「转平面」（docs/264 §10，开关 ult/px_plane）：高高跃起 → 0.6 秒后巨锤砸落点 → 冲击波横扫、碎石飞溅、敌人震上半空 0.8 秒后落地。
// 只改画面；时序、判定、伤害照 ult_moves_c.gd。画法照 px_plane（1 像素 = 1 美术像素、15 fps、贴地层压扁 0.72），复用 ak-siege-pp.js 的裂网 / 碎石 / 尘墙。
// 裂地照用户认可的「裂地 v3」：不规整分叉裂网、爆亮后冷却、隆起尘墙、预兆余震。配色同推进之王（熔金 8 阶 + 暖土 + 白金熔芯），不用危险红。
// 冲击帧（整屏白 + 黑剪影，ult.gd）不在帧条里，由游戏框架画。
// 件：
//   warn  gd  落点预兆（0.6 秒）：断续金环在判定半径上一闪一闪、落点影子越来越大越来越深、中心细裂一节节冒出来、地面碎屑跳动（预兆余震）
//   charge up 空中蓄力（跟人走）：金色能量线往锤头汇聚，锤头一点白金越来越亮
//   smash up  砸落：白金爆闪 + 竖直冲柱 + 原作火星线 + 碎石高抛落回 + 两圈隆起尘墙
//   smash gd  砸落：分叉大裂网（白热 → 白金熔芯 → 冷成暗土、断节）+ 深坑 + 冲击环 + 四拍余震（0.18 秒一圈往外震，尘浪 + 一节节小裂）
import { fit, clamp, smooth, ease, noise, TAU, hex, WHITE } from "../../core/index.js";
import { nz, crackPaths, drawCracks, crater, ring, streaks, rubble, dustWall, flash, pillar, radialCracks } from "./ak-siege-pp.js";

export const meta = {
  name: "Siege ultimate plane",
  desc: "Siege's ultimate: leap, charge, colossal hammer smash with forked crack net, rising dust walls and four aftershock beats, redrawn for a 3/4 top-down plane.",
  tags: ["melee", "impact", "topdown", "siege", "ultimate", "one-shot"],
  size: [620, 520],
  origin: [310, 330],
  duration: 1.8,
  loop: false,
  fps: 15,
  bg: "dark",
  options: {
    palette: ["#1a0c05", "#3a1c0a", "#6b3812", "#a85e1a", "#e08e26", "#ffbf3c", "#ffe9a0", "#ffffff"],
    dust: ["#1a1510", "#2e261c", "#4a3e2e", "#6e5f48", "#9a8a6a"],
    stone: ["#17130f", "#2b241c", "#463b2e", "#665747", "#8f7f69", "#bcae94"],
    accent: "#fff1b8",
    part: "smash",
    layer: "gd",
    R: 270, SY: 0.72, seed: 31, el: 2,
  },
};

const D2R = Math.PI / 180;

// ---------------------------------------------------------------- 预兆
function warn(p, t, o, C, ACC, DU) {
  const R = +o.R, SY = +o.SY, n = C.length, k = clamp(t / 0.6);
  // 断续金环：判定半径上，一拍亮一拍暗，越到落地越密
  const blink = Math.floor(t * 15) % 2 === 0;
  const m = Math.ceil(R * TAU * 0.9);
  for (let j = 0; j < m; j++) {
    const a = (j / m) * TAU;
    if (nz(a * 7.3 + Math.floor(t * 7.5), +o.seed + 11) < 0.62 - 0.35 * k) continue;
    const sa = Math.sin(a);
    p.px(Math.round(Math.cos(a) * R), Math.round(sa * R * SY), blink ? (sa > 0 ? C[n - 3] : C[n - 4]) : C[n - 5]);
  }
  // 影子：落点一团压暗，越来越大越来越深（真半透明）
  const rs = 15 + 22 * k;
  p.shade(-rs - 1, -rs * SY - 1, rs + 1, rs * SY + 1, (x, y, out) => {
    const d = Math.hypot(x / rs, y / (rs * SY));
    if (d > 1) return;
    p.blend(x, y, DU[0], (0.25 + 0.45 * k) * (1 - d * 0.6));
  });
  // 预兆余震：中心细裂一节节冒出来（暗金，不亮）+ 碎屑在地上跳
  const paths = radialCracks(o, 30 + 40 * k, 9, +o.seed + 21);
  for (const pts of paths) for (const [x, y, f] of pts) {
    if (f > k * 1.1) break;
    if (nz(f * 30 + x, +o.seed + 23) < 0.25) continue;
    p.px(Math.round(x), Math.round(y * SY), k > 0.7 && blink ? C[n - 4] : C[n - 6]);
  }
  for (let i = 0; i < 18; i++) {
    const a = TAU * nz(i * 2.3, +o.seed + 25), r = R * (0.1 + 0.85 * nz(i * 3.1, +o.seed + 27));
    const ph = (t * 7.5 + nz(i, +o.seed + 29) * 3) % 1;
    const z = Math.max(0, 6 * k * Math.sin(ph * Math.PI));
    const X = Math.round(Math.cos(a) * r), Y = Math.round(Math.sin(a) * r * SY - z);
    p.px(X, Y, DU[4]); p.px(X + 1, Y, DU[2]);
  }
}

// ---------------------------------------------------------------- 空中蓄力（原点 = 她脚底；锤头在头顶上方）
function charge(p, t, o, C, ACC) {
  const n = C.length, k = clamp(t / 0.6), hz = 74;
  for (let i = 0; i < 10; i++) {          // 往锤头汇聚的金线
    const a = TAU * (i / 10) + nz(i, +o.seed + 31) * 0.5, ph = (t * 3 + i * 0.13) % 1;
    const r = 46 * (1 - ph);
    const x0 = Math.cos(a) * r, y0 = -hz + Math.sin(a) * r * 0.8;
    const L = 5 + 4 * k;
    for (let s = 0; s < L; s++) {
      const q = s / L, x = x0 + Math.cos(a) * s, y = y0 + Math.sin(a) * s * 0.8;
      p.px(Math.round(x), Math.round(y), q < 0.3 ? (ph > 0.7 ? WHITE : C[n - 2]) : C[n - 4]);
    }
  }
  const rc = 2 + Math.round(4 * k);       // 锤头一点越来越亮
  for (let y = -rc; y <= rc; y++) for (let x = -rc; x <= rc; x++) {
    const d = Math.hypot(x, y) / rc;
    if (d > 1) continue;
    p.px(x, -hz + y, d < 0.45 ? WHITE : d < 0.75 ? ACC : C[n - 3]);
  }
}

// ---------------------------------------------------------------- 砸落（立起层）
function smashUp(p, t, o, C, ACC, ST, DU) {
  const R = +o.R;
  pillar(p, t, C, ACC, 120, 20, 2);
  flash(p, t, C, 46, 15, 6, 0.0);
  streaks(p, t, o, C, 26, 320, +o.seed + 41, 0.0, 160);
  rubble(p, t, o, ST, DU, 30, R * 0.4, +o.seed + 43, 0.03, ACC);
  rubble(p, t, o, ST, DU, 18, R * 0.75, +o.seed + 44, 0.09, null);
  bigWall(p, t, o, C, DU, R * 0.95, 34, 30, +o.seed + 45, 0.05);   // 隆起尘墙：外圈（大团、往上冒、受光顶，散的时候整团缩掉）
  bigWall(p, t, o, C, DU, R * 0.55, 22, 20, +o.seed + 46, 0.14);   // 内圈晚一拍
}

// 终结技尺度的尘墙：每团半径 5–8 美术像素，从地面隆起到 hMax 再缩掉；前半圈压在后半圈前面（按 y 先后画）
function bigWall(p, t, o, C, DU, R, m, hMax, sd, t0) {
  const SY = +o.SY, n = C.length, u = t - t0;
  if (u <= 0 || u > 0.75) return;
  const puffs = [];
  for (let j = 0; j < m; j++) {
    const a = TAU * (j + nz(j * 1.3, sd + 1) * 0.7) / m;
    puffs.push({ a, gx: Math.cos(a) * R * (0.9 + 0.15 * nz(j, sd + 3)), gy: Math.sin(a) * R * SY, j });
  }
  puffs.sort((A, B) => A.gy - B.gy);
  for (const q of puffs) {
    const j = q.j;
    if (u > 0.4 && nz(j * 7.7, sd + 5) < (u - 0.4) * 3) continue;
    const h = hMax * (0.5 + 0.5 * nz(j * 2.1, sd + 7)) * ease.outCubic(clamp(u / 0.22));
    const rr = Math.round((5 + 3 * nz(j * 3.7, sd + 9)) * (u < 0.45 ? 1 : 1 - (u - 0.45) * 2));
    if (rr < 1) continue;
    for (let dy = -rr; dy <= rr; dy++) for (let dx = -rr - 2; dx <= rr + 2; dx++) {
      if ((dx * dx) / ((rr + 2) * (rr + 2)) + (dy * dy) / (rr * rr) > 1.02) continue;
      let c = dy < -rr * 0.4 ? DU[4] : dy < rr * 0.2 ? DU[3] : DU[2];
      if (u < 0.1 && dy < -rr * 0.5) c = C[n - 3];                         // 砸下那一拍：尘墙顶被照亮
      p.px(Math.round(q.gx + dx), Math.round(q.gy - h * 0.6 + dy), c);
    }
  }
}

// ---------------------------------------------------------------- 砸落（贴地层）：大裂网 + 深坑 + 冲击环 + 四拍余震
function beat(p, t, o, C, DU, r, t0, i) {
  const SY = +o.SY, n = C.length, u = t - t0;
  if (u < 0 || u > 0.4) return;
  const g = ease.outCubic(clamp(u / 0.25)), rr = r * (0.85 + 0.15 * g), fd = smooth(0.15, 0.4, u);
  const m = Math.ceil(rr * TAU * 0.8);
  for (let j = 0; j < m; j++) {                 // 尘浪一圈（断续、贴地、外缘受光）
    const a = (j / m) * TAU;
    if (nz(a * 5.7 + i * 3, +o.seed + 51) < 0.3 + fd * 0.6) continue;
    const sa = Math.sin(a);
    for (let k = 0; k < 3; k++) p.px(Math.round(Math.cos(a) * (rr - k)), Math.round(sa * (rr - k) * SY), k === 0 ? (u < 0.067 ? C[n - 3] : DU[4]) : DU[2]);
  }
  for (let q = 0; q < 6 + 2 * i; q++) {         // 环上一节节小裂（爆亮 → 冷）
    const a = TAU * (q + nz(q + i * 9, +o.seed + 53) * 0.7) / (6 + 2 * i);
    let x = Math.cos(a) * rr * 0.92, y = Math.sin(a) * rr * 0.92, aa = a + (nz(q, +o.seed + 55) - 0.5);
    for (let s = 0; s < 10 + 3 * i; s++) {
      aa += (nz(s * 0.4 + q, +o.seed + 57) - 0.5) * 0.4;
      x += Math.cos(aa); y += Math.sin(aa);
      if (s / (10 + 3 * i) > clamp(u / 0.08)) break;
      p.px(Math.round(x), Math.round(y * SY), u < 0.067 ? WHITE : u < 0.2 ? C[n - 3] : DU[1]);
    }
  }
}

function smashGd(p, t, o, C, ACC, DU) {
  const R = +o.R, SY = +o.SY;
  crater(p, t, o, DU, R * 0.14, SY, 0.85);
  ring(p, t, o, C, R, SY, 0.0, 4);
  drawCracks(p, t, o, C, ACC, DU, crackPaths(o, R * 0.95, 14, +o.seed + 61, undefined, undefined, 0.1), SY, true, 0.0);   // 长裂缝：弯曲度 0.1（裂地 v3：不规整、分叉，不绕圈）
  [0.3, 0.55, 0.8, 1.0].forEach((k, i) => beat(p, t, o, C, DU, R * k, 0.18 * i + 0.02, i));
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), DU = fit(o.dust, 5), ST = fit(o.stone, 6), ACC = hex(o.accent);
  const gd = o.layer === "gd";
  switch (o.part) {
    case "warn": return gd ? warn(p, t, o, C, ACC, DU) : undefined;
    case "charge": return gd ? undefined : charge(p, t, o, C, ACC);
    case "smash": return gd ? smashGd(p, t, o, C, ACC, DU) : smashUp(p, t, o, C, ACC, ST, DU);
  }
}
