// 流明「转平面」（docs/255，开关 fx/px_plane，照斯卡蒂 docs/246 的做法）：pixelfx 画法按本作俯视斜角重画。
// 主形参照旧放开版（tools/pixelfx_fx/lumen_ul_ref/，用户 11-05「流明的部分 pixelfx 特效可以留」），S1 用用户 11-04 亲定的 v3（涟漪弧沿判定圈）。
// 一个文件按 part 出各件；每件分两层（layer）：
//   up 立起层 —— 离地的东西（命中水花、雨丝、水柱、四芒灯光、光爆星芒），原点 = 地面点（命中件 = 命中点），进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（湿痕、涟漪弧、光圈边、冲击边），已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转。
// 防整屏发白（用户 11-05）：白只给热芯和第 0 拍；大片区域（光雨范围、灯塔光圈）只画边 + 内侧淡渐变（α ≤ 0.12，抖动），不平涂；亮度靠游戏里的照地光与 emit。
// 色：本人钢蓝 7 阶（house.js OP.lumen）；精二点缀灯火橙（LAMP，只点在主形上）。不用危险红。同一招元素 ≤ 3。
import { fit, clamp, smooth, ease, noise, noise2, TAU, Rng } from "../../core/index.js";
import { OP, LAMP, jitterAngles } from "../house.js";

export const meta = {
  name: "Lumen plane",
  desc: "Lumen's light-and-rain moves redrawn for a 3/4 top-down plane: standing splashes, rain, columns and flares, and squashed ground ripples, wet marks and ring edges.",
  tags: ["water", "light", "topdown", "lumen", "one-shot"],
  size: [272, 320],
  origin: [136, 210],
  duration: 1.2,
  loop: false,
  fps: 15,   // 统一动画时钟（docs/246 §5）
  bg: "dark",
  options: { palette: OP.lumen, part: "hit", layer: "up", el: 0, R: 70, SY: 0.72, seed: 3, dur: 1.2 },
};

const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1
// 半透明一律不用 Bayer 抖动（2 倍下显成网点，斯卡蒂 11-05 用户挑过）：a < 1 时按固定的 2D 噪声成团消散——同一位置的像素按噪声值先后熄掉，淡出像水痕干掉
const D = (p, x, y, c, a = 1) => { if (a >= 0.999 || (a > 0 && noise2(Math.floor(x) * 0.45, Math.floor(y) * 0.45, 77) * 0.5 + 0.5 < a)) p.px(x, y, c); };

// 十字星（原作 shizi）：细十字，m 像素臂长
function cross(p, x, y, m, C) {
  p.px(x, y, C[6]);
  for (let d = 1; d <= m; d++) {
    const c = d <= 1 ? C[6] : C[5];
    p.px(x + d, y, c); p.px(x - d, y, c); p.px(x, y + d, c); p.px(x, y - d, c);
  }
}

// 实心星芒：rays = [[dx, dy, L, 根部半宽]]；白芯只在第 0 拍
function star(p, cx, cy, rays, k, t, C) {
  for (const [dx, dy, L, w0] of rays) {
    const len = L * k;
    for (let s = 0; s <= len; s += 0.5) {
      const v = s / Math.max(len, 1), th = Math.max(0, w0 * (1 - v));
      const c = t < 0.06 ? (v < 0.6 ? C[6] : C[5]) : v < 0.12 ? C[6] : v < 0.6 ? C[5] : C[4];
      for (let q = -th; q <= th; q += 0.5) p.px(cx + dx * s - dy * q, cy + dy * s + dx * q, Math.abs(q) < th * 0.45 ? c : c === C[6] ? C[5] : C[4]);
    }
  }
}

// 贴地边弧：半径 R 上 n 段（段间缺口、长短不等），w 像素厚（外亮内暗，颜色阶代替透明度），a 可见度
function edgeArcs(p, R, SY, segs, w, a, C, seed, t, hot) {
  for (const sg of segs)
    for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.45 / R) {
      const e = 1 - Math.abs(an - sg.c) / sg.half, n = nz(an * 3.1 + t * 1.5, seed + 7);
      const k = a * smooth(0, 0.35, e);
      if (k <= 0.05) continue;
      for (let q = 0; q < w; q++) {
        const r = R - q * 1.1, ci = q === 0 ? (hot ? 6 : n > 0.62 ? 5 : 4) : q === 1 ? (n > 0.7 ? 4 : 3) : 2;
        D(p, Math.cos(an) * r, Math.sin(an) * r * SY, C[ci], k * (q === 0 ? 1 : 0.85));
      }
    }
}

// 内侧淡渐变（抖动 blend，α ≤ amax）：只贴着边往里 band 像素，中心不铺
function innerFade(p, R, SY, band, amax, C, seed) {
  for (let y = -R * SY; y <= R * SY; y += 1)
    for (let x = -R; x <= R; x += 1) {
      const q = Math.hypot(x / R, y / (R * SY));
      if (q > 1 || q < 1 - band / R) continue;
      const u = (q - (1 - band / R)) / (band / R);   // 0 内 → 1 边
      const n = nz(Math.atan2(y, x) * 2.3, seed + 5);
      p.blend(x, y, C[3], amax * u * u * (0.6 + 0.4 * n));
    }
}

function segsOf(Rg, n, cover) {
  const out = [], a0 = Rg.range(0, TAU);
  for (let i = 0; i < n; i++) {
    const w = TAU / n, c = a0 + (i + 0.5 + Rg.range(-0.18, 0.18)) * w;
    out.push({ c, half: w * cover * Rg.range(0.8, 1.15) * 0.5 });
  }
  return out;
}

export function create(o) {
  const C = fit(o.palette, 7), AC = fit([LAMP], 1)[0], E = +o.el, SY = +o.SY, up = o.layer === "up", gd = o.layer === "gd";
  const Rg = new Rng(+o.seed + 17 * E);
  const part = o.part;
  let t = 0;
  const S = {};
  // ---------------------------------------------------------------- 预计算
  if (part === "cleanse") {
    // 连携技「清创光弹」（不分档）：光弹在队长胸口炸成一团大水花（同普攻命中一套画法，体量 ×1.7）+ 几点灯火橙光尘往上飘（灯火回复）；
    // 贴地：半径 R（= 150 / 2）的照亮范围原地闪一下（4 段边弧 + 淡渐变，不外扩）
    S.motes = [];
    for (let i = 0; i < 8; i++) { const a = Rg.range(-Math.PI, Math.PI); S.motes.push({ x: Math.cos(a) * Rg.range(4, 16), y: Rg.range(-4, 6), v: Rg.range(30, 52), d: 0.05 + i * 0.03, w: i % 3 === 0 }); }
    S.segs = segsOf(Rg, 4, 0.62);
  }
  if (part === "hit" || part === "cleanse") {
    // 光弹命中（原作 lumen_attack_01_hit 尖刺水花，旧放开版主形）：实心水团 + 5–7 根粗水刺 + 两三颗落地的水珠。
    // E1 体量 ×1.25、第二拍爆亮；E2 质变：一团变三团 ×1.5、芯一点灯火橙、水团顶上冲起一道竖直灯塔细光（精二灯塔意象）
    S.K = part === "cleanse" ? 2.2 : 1.6 * [1, 1.25, 1.5][E] * (+o.k || 1);   // 11-05：E0 ×1.3 在后期画面里太小，提到 ×1.6
    S.blobs = E === 2 ? [[0, 0, 1], [6, -3, 0.6], [4, 4, 0.5]] : [[0, 0, 1]];
    const n = E === 2 ? 7 : E === 1 ? 6 : 5;
    S.spikes = jitterAngles(Rg, n, -Math.PI, Math.PI, 0.42).map((a, i) => ({ a, L: (5 + 7 * nz(i * 1.7, +o.seed) + 4 * Math.max(0, Math.cos(a))) * S.K }));
    S.drops = S.spikes.filter((q, i) => i % 3 === 0).slice(0, E === 0 ? 2 : 3).map((q) => ({ x: Math.cos(q.a) * q.L * 0.8, y: Math.sin(q.a) * q.L * 0.8, vx: Math.cos(q.a) * 6, vy: -10, b: 0 }));
  }
  if (part === "mend") {
    // 荧光治疗（原作 lumen_buff_01_hit）：一缕水流在队长身前一侧卷上去半圈多 + 顶上一颗十字星；E1 加厚；E2 两缕 + 汇合处灯火橙
    const ES = [1, 1.25, 1.5][E];
    S.H = 52 * ES; S.RX = 11 * ES; S.a0 = Rg.range(0.3, 0.9);
    S.strands = E === 2 ? [S.a0, S.a0 + 2.2] : [S.a0];
    S.TH = [1, 2, 2.5][E];
    S.pt = (u, a1) => { const a = a1 + u * 0.6 * TAU; return [Math.cos(a) * S.RX * (1 - 0.35 * u), -u * S.H + Math.sin(a) * S.RX * 0.4, Math.sin(a)]; };
  }
  if (part === "drizzle") {
    // S1 沐雨 v3（用户 11-04 亲定）：判定半径 R（= rain_r / 2）上 4–6 段涟漪弧，由落在边上的雨点串起来；斜细雨落进法阵；十字星浮起（≤ 3）。
    // E1：一到两道斜光贯穿法阵（折光）；E2：上方照进法阵中心一道钢蓝白光柱（灯塔），雨更密，新落点亮一点灯火橙
    const R = +o.R;
    S.tail = [0.6, 0.8, 1][E];
    S.T_HOLD = 0.35 + 0.35 * S.tail; S.T_END = S.T_HOLD + 0.25;
    S.rain = [];
    for (let i = 0, nR = [12, 16, 22][E]; i < nR; i++) {
      const a = Rg.range(0, TAU), r = Math.sqrt(Rg.range(0.04, 1)) * R * 0.86;
      S.rain.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, t: 0.04 + Rg.range(0, E === 2 ? 0.34 : 0.26), len: Rg.range(12, 20), fall: Rg.range(0.12, 0.17), h: Rg.range(100, 140) });
    }
    S.glints = [];
    for (let i = 0, n = [3, 4, 5][E]; i < n; i++) {
      const a = Rg.range(0, TAU), r = Rg.range(0.15, 0.6) * R;
      S.glints.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, v: Rg.range(26, 46), d: 0.18 + i * 0.13, s: Rg.range(2.4, 3.8), life: 0.4 });
    }
    S.refr = [];
    if (E >= 1) for (let i = 0, n = E === 1 ? 2 : 1; i < n; i++) S.refr.push({ a: Rg.range(0.35, 0.7) * (i % 2 ? -1 : 1), off: Rg.range(-0.25, 0.25) * R, t: 0.2 + i * 0.13 });
    S.segs = [];
    const nSeg = Rg.int(4, 6), a0 = Rg.range(0, TAU);
    for (let i = 0; i < nSeg; i++) {
      const w = TAU / nSeg, c = a0 + (i + 0.5 + Rg.range(-0.18, 0.18)) * w, half = w * Rg.range(0.26, 0.36);
      const drops = [];
      for (let k = 0, n = Rg.int(2, 3); k < n; k++) drops.push({ a: c + Rg.range(-0.8, 0.8) * half, t: 0.05 + Rg.range(0, 0.16) });
      drops.sort((u, v) => u.t - v.t);
      S.segs.push({ c, half, drops, t0: drops[0].t });
    }
  }
  if (part === "rainloop") {
    // 成长「光雨」持续 3 秒的雨区（循环 1.2 秒）：范围只画边（几段暗弧）+ 内侧淡渐变；少而粗的雨点落下，落地一个扁的小水冠
    const R = +o.R;
    S.segs = segsOf(Rg, 5, 0.55);
    S.drops = [];
    for (let i = 0; i < 10; i++) {
      const a = Rg.range(0, TAU), r = Math.sqrt(Rg.range(0.05, 1)) * R * 0.9;
      S.drops.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, ph: i / 10 + Rg.range(-0.03, 0.03), h: Rg.range(70, 95) });
    }
  }
  if (part === "downpour") {
    // S2 沛霖（原作 lumen_skill_02_hit）：头顶一道窄水柱 0.13 秒砸到队长脚下，水冠往上翘；E2 质变一道变三道 + 落点灯火橙
    S.H = 150; S.W = E === 2 ? 6 : 4; S.T_LAND = 0.13;
    S.cols = E === 2 ? [[0, 1, 0], [-12, 0.55, 0.067], [11, 0.5, 0.1]] : [[0, 1, 0]];
    S.crown = jitterAngles(Rg, E === 2 ? 9 : 7, -Math.PI, Math.PI, 0.4).map((a, i) => ({ a, h: (9 + 13 * nz(i * 1.9, +o.seed)) * (E === 2 ? 1.3 : 1), r: 9 + 6 * nz(i * 2.7, +o.seed + 1) }));
    S.glints = [{ x: Rg.range(-10, 10), d: 0.3 }].concat(E === 2 ? [{ x: Rg.range(-12, 12), d: 0.45 }] : []);
  }
  if (part === "s3open") {
    // S3 灯火不灭起手（原作 lumen_skill_03_start）：头顶四芒灯光 + 两道弧形水流卷上去；贴地：灯塔光圈原地亮起（不外扩），边 + 内侧淡渐变
    S.arcs = [];
    for (let i = 0; i < 2; i++) S.arcs.push({ a0: Rg.range(0, TAU), sw: Rg.range(2.2, 3.4) * (i % 2 ? 1 : -1), rx: Rg.range(16, 24), h: Rg.range(50, 72), d: i * 0.067 });
    S.segs = segsOf(Rg, 4, 0.62);
  }
  if (part === "tower") {
    // S3 持续期间的灯塔光圈（贴地，循环）：几段边弧缓慢呼吸 + 内侧淡渐变；立起：几点光尘慢慢往上飘
    S.segs = segsOf(Rg, 4, 0.6);
    S.motes = [];
    for (let i = 0; i < 9; i++) { const a = Rg.range(0, TAU), r = Math.sqrt(Rg.range(0.1, 0.95)) * +o.R; S.motes.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, ph: i / 9, h: Rg.range(26, 44) }); }
  }
  if (part === "burst") {
    // S3 结束光爆：短而粗的双层实心星芒（正十字 + 斜十字）+ 亮芯 + 竖直白光柱；贴地：判定半径上边弧原地闪一下（不外扩）
    S.segs = segsOf(Rg, 3, 0.7);
  }
  const SEG = 1 / 15;
  return {
    update(dt) {
      t += dt;
      if (part === "hit" && t > 0.08) for (const d of S.drops) { d.vy += 260 * dt; d.x += d.vx * dt; d.y += d.vy * dt; if (d.y > 8 && d.vy > 0) { d.y = 8; d.vy *= -0.35; d.vx *= 0.5; d.b++; } }
    },
    draw(p) {
      const R = +o.R;
      // ================================================================ hit
      if (part === "cleanse") {
        if (up)
          for (const m of S.motes) {   // 灯火回复：橙 / 白光尘往上飘，0.5 秒散
            const a = t - m.d;
            if (a <= 0 || a > 0.55) continue;
            const y = m.y - 20 - a * m.v, k = Math.sin((a / 0.55) * Math.PI);
            D(p, m.x, y, m.w ? AC : k > 0.7 ? C[6] : C[5], k + 0.2);
            if (k > 0.5) D(p, m.x, y + 1, m.w ? AC : C[4], k);
          }
        if (gd) {
          const a = t < 0.04 ? 1 : 1 - smooth(0.12, 0.5, t);
          if (a > 0) { innerFade(p, R, SY, 16, 0.12 * a, C, +o.seed); edgeArcs(p, R, SY, S.segs, 3, a, C, +o.seed, t, t < SEG); }
        }
      }
      if (part === "hit" || (part === "cleanse" && up)) {
        const K = S.K;
        if (up) {
          const out = 0.55 + 0.45 * ease.outCubic(clamp(t / 0.05)), back = smooth(0.1, 0.3 + 0.04 * E, t);
          const beat2 = E >= 1 && t > SEG * 0.9 && t < SEG * 1.9;   // E1+：第 1 拍再爆亮一次
          const blob = beat2 ? 0.85 : 1 - smooth(0.04, 0.16 + 0.06 * E, t);
          if (blob > 0)
            for (const [bx, by, bk] of S.blobs)
              for (let an = 0; an < TAU; an += 0.16) {
                const rr = (3 + 2.5 * nz(an * 1.7 + bx, +o.seed)) * K * bk * (0.6 + 0.4 * blob);
                for (let r = 0; r <= rr; r += 0.5) p.px(bx * K + Math.cos(an) * r, by * K + Math.sin(an) * r * 0.85, t < SEG || beat2 ? (r < rr * 0.7 ? C[6] : C[5]) : r < rr * 0.45 ? C[5] : r < rr * 0.8 ? C[4] : C[3]);
              }
          if (E === 2 && t < 0.2) for (let y = -1; y <= 1; y++) for (let x = -1; x <= 1; x++) if (Math.abs(x) + Math.abs(y) <= 1) p.px(x, y, AC);
          if (back < 1)
            for (const s of S.spikes) {
              const L = s.L * out * (1 - 0.7 * back), ca = Math.cos(s.a), sa = Math.sin(s.a);
              for (let d = 1.5; d <= L; d += 0.5) {
                const v = d / Math.max(L, 1), droop = back * 6 * v * v, w = (1.3 + 0.5 * E) * (1 - v) * (1 - 0.5 * back);
                const ci = t < SEG ? (v < 0.6 ? 6 : 5) : v < 0.4 ? 5 : 4;
                for (let q = -w; q <= w; q += 0.5) p.px(ca * d - sa * q, sa * d * 0.85 + ca * q + droop, Math.abs(q) > w - 0.5 && w > 0.6 ? C[Math.max(3, ci - 1)] : C[ci]);
              }
            }
          if (E === 2 && t < 0.2 && !(+o.k < 1) && part === "hit") {   // 竖直灯塔细光：冲上去、往中线收（只给主弹命中；小水花不带，免得多弹叠成一片白）
            const H = 14 * K * ease.outCubic(clamp(t / 0.06)), W = 1.2 * (1 - smooth(0.06, 0.2, t));
            for (let y = 2; y <= H; y += 1) for (let x = -W; x <= W; x += 0.5) D(p, x, -y, Math.abs(x) < 0.6 && t < 0.1 ? C[6] : C[5], clamp(1.3 - y / H));
          }
          if (t > 0.08) for (const d of S.drops) if (d.b < 3 && t < 0.5) { p.px(d.x, d.y, C[5]); p.px(d.x + 1, d.y, C[4]); p.px(d.x, d.y - 1, C[6]); }
        }
        if (gd && part === "hit") {   // 地上一块不规则湿痕（暗钢蓝，抖动变稀），朝镜头一侧几点水光；0.45 秒散掉
          const u = clamp(t / 0.45), r0 = 5.5 * K;
          if (u < 1)
            for (let y = -r0 * SY; y <= r0 * SY; y += 1)
              for (let x = -r0; x <= r0; x += 1) {
                const q = Math.hypot(x / r0, y / (r0 * SY)) * (0.8 + 0.4 * nz(Math.atan2(y, x) * 2.1, +o.seed + 9));
                if (q > 1) continue;
                const rim = q > 0.72 && y > 0 && nz(x * 0.9, +o.seed + 3) > 0.55;
                D(p, x, y, rim ? (u < 0.15 ? C[5] : C[4]) : q > 0.6 ? C[2] : C[1], (1 - u) * (rim ? 1 : 0.7));
              }
        }
      }
      // ================================================================ flare（灯塔光柱出光点 / 折光起点）
      if (part === "flare" && up) {
        const k = 1 - ease.inQuad(clamp(t / 0.22)), sc = +o.k || 1;
        if (k > 0) star(p, 0, 0, [[1, 0, 12 * sc, 1.6], [-1, 0, 12 * sc, 1.6], [0, -1, 8 * sc, 1.3], [0, 1, 6 * sc, 1.2]], k, t, C);
        if (t < 0.13) { p.px(0, 0, AC); p.px(1, 0, AC); }
      }
      // ================================================================ mend
      if (part === "mend" && up) {
        const head = ease.outCubic(clamp(t / 0.25)), tl = clamp((t - 0.12) / (0.3 * [0.88, 0.94, 1][E])), u0 = Math.max(0, head - 0.5) + tl * 0.5;
        if (head > u0)
          for (const a1 of S.strands)
            for (let u = u0; u <= head; u += 0.006) {
              const [x, y, z] = S.pt(u, a1), v = (u - u0) / Math.max(head - u0, 0.01);
              D(p, x, y, z < -0.2 ? C[3] : v > 0.85 ? C[6] : C[5], z < -0.2 ? 0.7 : 1);
              if (v > 0.2) for (let k = 1; k <= S.TH; k += 1) D(p, x + k, y, z < -0.2 ? C[3] : k < S.TH ? C[5] : C[4], z < -0.2 ? 0.6 : 1);
            }
        const top = S.pt(1, S.a0);
        const gl = [{ x: top[0], d: 0.24 }].concat(E === 2 ? [{ x: top[0] + 7, d: 0.34 }] : []);
        for (const g of gl) {
          const a = t - g.d, life = 0.3;
          if (a <= 0 || a > life) continue;
          cross(p, g.x, top[1] - 3 - a * 25, Math.round(3 * Math.sin((a / life) * Math.PI)), C);
        }
        if (E === 2 && t > 0.2 && t < 0.4) for (let y = -1; y <= 1; y++) for (let x = -1; x <= 1; x++) if (Math.abs(x) + Math.abs(y) <= 1) p.px(top[0] + x, top[1] - 3 + y, AC);
      }
      // ================================================================ drizzle（S1 沐雨 v3）
      if (part === "drizzle") {
        const fa = 1 - smooth(S.T_HOLD, S.T_END, t), open = ease.outCubic(clamp((t - 0.04) / 0.12));
        if (gd && fa > 0) {
          // 内侧淡渐变（只贴边，不铺满）
          if (t >= 0.04) innerFade(p, R, SY, 14, 0.12 * fa * open, C, +o.seed);
          for (const sg of S.segs) {
            for (const d of sg.drops) {   // 落点小涟漪：扁的前半圈，不长大
              const u = (t - d.t) / 0.25;
              if (u < 0 || u > 1) continue;
              const x0 = Math.cos(d.a) * R, y0 = Math.sin(d.a) * R * SY;
              for (let an = 0.2; an < Math.PI - 0.2; an += 0.3) D(p, x0 + Math.cos(an) * 4, y0 + Math.sin(an) * 2, u < 0.2 ? C[6] : C[5], 1 - u);
            }
            if (t < sg.t0) continue;
            const lo = sg.c - sg.half, hi = sg.c + sg.half;
            for (let an = lo; an <= hi; an += 0.5 / R) {
              let reach = 0;
              for (const d of sg.drops) if (t > d.t) reach = Math.max(reach, 1 - Math.abs(an - d.a) / (sg.half * 1.6 * ease.outCubic(clamp((t - d.t) / 0.18)) + 1e-3));
              if (reach <= 0) continue;
              const edge = Math.min(an - lo, hi - an) / sg.half, n = nz(an * 3.1 + t * 2.5, +o.seed + 7);
              const k = fa * Math.min(1, reach * 2) * smooth(0, 0.35, edge);
              const fresh = sg.drops.some((d) => t - d.t < 0.07 && Math.abs(an - d.a) < 0.12);
              D(p, Math.cos(an) * R, Math.sin(an) * R * SY, fresh ? C[6] : n > 0.8 ? C[6] : n > 0.5 ? C[5] : C[4], k * (n > 0.4 ? 1 : 0.6));
              for (let th = 1; th <= 1 + E; th++) D(p, Math.cos(an) * (R - th * 1.2), Math.sin(an) * (R - th * 1.2) * SY, th === 1 + E && E === 2 && fresh ? AC : th === 1 ? C[3] : C[2], k * 0.9);   // 深色内边（颜色阶代替透明度）；E1 / E2 各厚一档
            }
          }
          for (const r of S.refr) {   // 折光（E1+）：贴地斜光贯穿法阵，2 像素白芯 + 钢蓝边，0.3 秒
            const a = (t - r.t) / 0.3;
            if (a < 0 || a > 1) continue;
            const ca = Math.cos(r.a), sa = Math.sin(r.a), L2 = R * 1.05, head = -L2 + 2 * L2 * ease.outCubic(clamp(a / 0.3)), fade = 1 - smooth(0.75, 1, a);
            for (let s = -L2; s <= head; s += 0.5) {
              const q = Math.abs(s) / L2, x = -sa * r.off + ca * s, y = (ca * r.off + sa * s) * SY;
              D(p, x, y, q < 0.6 && (a < 0.3 || q < 0.15) ? C[6] : C[5], fade * (1 - 0.7 * q * q));
              D(p, x - sa * 0.8, y + 1, C[4], fade * (1 - q) * 0.8);
            }
          }
        }
        if (up) {
          if (E === 2) {   // 灯塔光柱：上方照进法阵中心，白芯只在前两拍
            const u2 = ease.outCubic(clamp(t / 0.07)), fold = smooth(0.14, 0.4, t), H = 150 * u2, W = 2.8 * (1 - fold);
            if (W > 0.3)
              for (let y = 0; y <= H; y += 1) {
                const v = y / 150, w = W * (0.35 + 0.65 * v), al = clamp(v * 1.6) * (1 - 0.5 * fold);
                for (let x = -w; x <= w; x += 0.5) { const q = Math.abs(x) / Math.max(w, 0.5); D(p, x, -150 + y, q < 0.5 && t < 0.14 ? C[6] : q < 0.5 ? C[5] : C[4], clamp(al * (q < 0.5 ? 1.2 : 0.8))); }
              }
            if (t < 0.2) for (let y = -1; y <= 1; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(x, y - 1, AC);
          }
          for (const d of S.rain) {   // 斜细雨：1 像素线，头亮尾暗，落地即消失（只落不甩）
            const u = (t - d.t) / d.fall;
            if (u < 0 || u > 1) continue;
            const yh = d.y - d.h * (1 - u), xh = d.x - 0.22 * d.h * (1 - u);
            for (let s = 0; s <= d.len; s += 0.5) D(p, xh - 0.22 * s, yh - s, s < 2 ? C[6] : s < d.len * 0.6 ? C[5] : C[4], s < d.len * 0.6 ? 1 : 1.4 - s / d.len);
          }
          for (const g of S.glints) {
            const a = t - g.d;
            if (a <= 0 || a > g.life) continue;
            cross(p, g.x, g.y - 6 - a * g.v, Math.round(g.s * Math.sin((a / g.life) * Math.PI)), C);
          }
        }
      }
      // ================================================================ rainloop（光雨雨区，循环）
      if (part === "rainloop") {
        const P = +o.dur, ph = (t % P) / P;
        if (gd) {
          innerFade(p, R, SY, 12, 0.1, C, +o.seed);
          edgeArcs(p, R, SY, S.segs, 2, 0.8, C, +o.seed, 0, false);
        }
        for (const d of S.drops) {
          const u = ((ph - d.ph) % 1 + 1) % 1;   // 0..1 一个周期
          const fallU = u / 0.55;
          if (up && fallU < 1) {   // 粗雨点：3 像素长、2 格宽的头
            const y = d.y - d.h * (1 - ease.inQuad(fallU));
            for (let s = 0; s < 4; s++) D(p, d.x - s * 0.15, y - s, s === 0 ? C[6] : s < 2 ? C[5] : C[4], 1 - s * 0.15);
            D(p, d.x + 1, y, C[5]);
          }
          const cu = (u - 0.55) / 0.25;
          if (cu >= 0 && cu < 1) {
            if (up) for (const sx of [-1, 1]) for (let s = 0; s < 3 * (1 - cu); s++) D(p, d.x + sx * (1 + s * 0.6 + cu * 2), d.y - s - 1, cu < 0.3 ? C[6] : C[5], 1 - cu);   // 小水冠
            if (gd) for (let an = 0.15; an < Math.PI - 0.15; an += 0.35) D(p, d.x + Math.cos(an) * (2 + cu * 3), d.y + Math.sin(an) * (1 + cu * 1.5), C[4], 1 - cu);   // 落点前半圈涟漪
          }
        }
      }
      // ================================================================ downpour（S2 沛霖）
      if (part === "downpour") {
        if (up) {
          for (const [cx, ck, cd] of S.cols) {
            const tc = t - cd, fall = ease.inQuad(clamp(tc / S.T_LAND)), cut = smooth(0.15, 0.42, tc);
            const yBot = -S.H + S.H * fall, yTop = -S.H + S.H * cut;
            if (tc > 0 && yBot > yTop)
              for (let y = yTop; y <= yBot; y += 1) {
                const v = (y + S.H) / S.H, w = S.W * ck * (0.6 + 0.4 * v) * (0.8 + 0.4 * nz(y * 0.15 + t * 12 + cx, +o.seed));
                for (let x = -w; x <= w; x += 0.5) { const q = Math.abs(x) / w; D(p, cx + x, y, q > 0.75 ? C[3] : q > 0.35 ? C[4] : tc < S.T_LAND + 0.07 ? C[6] : C[5], q > 0.85 ? 0.7 : 1); }   // 柱身钢蓝、只有芯一道亮（防发白）
              }
          }
          if (E === 2 && t > S.T_LAND && t < S.T_LAND + 0.2) for (let y = -1; y <= 1; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(x, y - 1, AC);
          const u = (t - S.T_LAND) / 0.4;
          if (u > 0 && u < 1)
            for (const c of S.crown) {
              const bx = Math.cos(c.a) * c.r * (0.6 + 0.4 * u), by = Math.sin(c.a) * c.r * SY, hh = c.h * Math.sin(Math.min(1, u * 1.6) * Math.PI * 0.5) * (1 - u * u);
              for (let s = 0; s <= hh; s += 0.5) for (const ox of [0, 0.7]) D(p, bx + Math.cos(c.a) * s * 0.35 + ox, by - s, u < 0.15 ? C[6] : s > hh * 0.6 ? C[5] : C[4], 1 - u * 0.5);
            }
          for (const g of S.glints) {
            const a = t - g.d, life = 0.35;
            if (a <= 0 || a > life) continue;
            cross(p, g.x, -14 - a * 30, Math.round(3.5 * Math.sin((a / life) * Math.PI)), C);
          }
        }
        if (gd) {   // 落点湿痕：一圈不规则的暗水边 + 朝镜头一侧水光，0.6 秒散掉
          const u = clamp((t - S.T_LAND + 0.02) / 0.6), r0 = 18 * (E === 2 ? 1.3 : 1);
          if (t > S.T_LAND - 0.02 && u < 1)
            for (let y = -r0 * SY; y <= r0 * SY; y += 1)
              for (let x = -r0; x <= r0; x += 1) {
                const q = Math.hypot(x / r0, y / (r0 * SY)) * (0.82 + 0.36 * nz(Math.atan2(y, x) * 2.4, +o.seed + 4));
                if (q > 1 || q < 0.55) continue;
                const rim = q > 0.85;
                D(p, x, y, rim ? (y > 0 && u < 0.2 ? C[5] : C[3]) : C[2], (1 - u) * (rim ? 1 : 0.55) * (nz(x * 0.7 + y, +o.seed + 8) > (rim ? 0.2 : 0.45) ? 1 : 0));
              }
        }
      }
      // ================================================================ s3open
      if (part === "s3open") {
        const LY = -48;
        if (up) {
          const u = clamp(t / 0.5);
          if (u < 1) star(p, 0, LY, [[1, 0, 44, 1.8], [-1, 0, 44, 1.8], [0, 1, 16, 1.5], [0, -1, 22, 1.5], [0.7, 0.7, 8, 1], [-0.7, 0.7, 8, 1], [0.7, -0.7, 9, 1], [-0.7, -0.7, 9, 1]], 1 - ease.inQuad(u), t, C);
          if (t < 0.27) for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(x, LY + y, Math.abs(x) + Math.abs(y) <= 1 ? AC : C[6]);   // 灯芯一点灯火橙（精二才有 S3）
          const arcPt = (a, w) => { const an = a.a0 + a.sw * w; return [Math.cos(an) * a.rx * (1 - 0.3 * w), -w * a.h + Math.sin(an) * a.rx * 0.35, Math.sin(an)]; };
          for (const a of S.arcs) {
            const h = ease.outCubic(clamp((t - a.d) / 0.3)), tl = clamp((t - a.d - 0.15) / 0.35);
            for (let w = tl; w <= h; w += 0.008) {
              const [x, y, z] = arcPt(a, w), v = (w - tl) / Math.max(h - tl, 0.01);
              const th = z < -0.3 ? 1 : 3.5 * Math.sin(Math.min(1, v * 1.2) * Math.PI * 0.5);
              for (let k = 0; k <= th; k += 0.8) p.px(x, y + k, z < -0.3 ? C[3] : k < 0.8 ? (v > 0.8 ? C[6] : C[5]) : k < 2 ? C[5] : C[4]);
            }
          }
        }
        if (gd) {   // 灯塔光圈原地亮起：边弧 0.07 秒亮满（第 0 拍白），之后交给持续件
          const a = clamp(t / 0.07) * (1 - smooth(0.35, 0.55, t));
          if (a > 0) {
            innerFade(p, R, SY, 18, 0.12 * a, C, +o.seed);
            edgeArcs(p, R, SY, S.segs, 3, a, C, +o.seed, t, t < SEG);
          }
        }
      }
      // ================================================================ tower（灯塔光圈，循环）
      if (part === "tower") {
        const P = +o.dur, ph = (t % P) / P, br = 0.75 + 0.25 * Math.sin(ph * TAU);
        if (gd) {
          innerFade(p, R, SY, 16, 0.09 * br, C, +o.seed);
          edgeArcs(p, R, SY, S.segs, 2, br, C, +o.seed, Math.sin(ph * TAU) * 0.6, false);
        }
        if (up)
          for (const m of S.motes) {
            const u = ((ph - m.ph) % 1 + 1) % 1;
            const y = m.y - u * m.h, a = Math.sin(u * Math.PI);
            D(p, m.x, y, a > 0.8 ? C[6] : C[5], a);
            if (a > 0.6) D(p, m.x, y + 1, C[4], a);
          }
      }
      // ================================================================ burst（S3 光爆）
      if (part === "burst") {
        const LY = -46;
        if (up) {
          const u = clamp(t / 0.45);
          if (u < 1) star(p, 0, LY, [[1, 0, 58, 4], [-1, 0, 58, 4], [0, -1, 44, 4], [0, 1, 30, 3.6], [0.7, 0.7, 30, 3], [-0.7, 0.7, 30, 3], [0.7, -0.7, 33, 3], [-0.7, -0.7, 33, 3]], 1 - ease.inQuad(u), t, C);   // 11-05 实机看偏小：×1.4
          if (t < 0.3) for (let y = -5; y <= 5; y++) for (let x = -5; x <= 5; x++) { const m = Math.abs(x) + Math.abs(y); if (m <= 5) p.px(x, LY + y, m <= 1 ? AC : m <= 2 || t < 0.07 ? C[6] : C[5]); }
          if (t < 0.35) {   // 竖直白光柱：冲上去、往中线收（白芯只在第 0 拍）
            const H = 70 * ease.outCubic(clamp(t / 0.07)), W = 3.5 * (1 - smooth(0.07, 0.35, t));
            for (let y = 0; y <= H; y += 1) for (let x = -W; x <= W; x += 0.5) D(p, x, LY - y, Math.abs(x) < W * 0.45 && t < 0.07 ? C[6] : C[5], clamp(1.2 - y / Math.max(H, 1)) * 0.95);
          }
        }
        if (gd) {
          const a = t < 0.04 ? 1 : 1 - smooth(0.12, 0.47, t);
          if (a > 0) {
            innerFade(p, R, SY, 22, 0.14 * a, C, +o.seed);
            edgeArcs(p, R, SY, S.segs, 4, a, C, +o.seed, t, t < SEG);
          }
        }
      }
    },
  };
}
