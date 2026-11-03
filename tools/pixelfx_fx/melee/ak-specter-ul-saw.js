// 归溟幽灵鲨「锯刃」放开版（docs/242，开关 fx/px_unleashed）：贴身 360° 环斩，俯视地面透视（y × SY），原点 = 锯环圆心（脚底 + (0, -10) 世界像素）。
// 原作参照（build/ark_ref/specter_unchained，只作参照）：普攻 attack_start_01 = 锯头处一圈红橙火星锯齿；技能 3 skill_03_* = 深海蓝水带盘旋上卷 + 红锯。
// 本作配色：锯身钢蓝灰（武器 #A9A19B 偏冷）、水带取 PRTS 饰「蓝披带」#152E57 的海军蓝（和敌弹青 #33ceff 靠饱和 / 明度拉开）、
// S3 血锯取瞳色 #E4625C 压暗到 0–3° 色相（和敌方危险色 #ff2667 的 342° 品红拉开）。
// move：basic = 普攻环斩（E0 / E1 / E2 分档）；s3 = 生存的重压（只有 E2）。
//   E0：钢蓝锯痕一圈 + 锯头一段不等距锯齿 + 少量红橙火星。
//   E1：加「卷刃」——外圈一道海军蓝细水带螺旋向内收进锯痕（docs/91 精一卷刃：把外圈敌人吸近）。
//   E2：卷刃水带变成撕裂的宽水带，绕锯盘旋并往上卷起（原作 S3 的蓝水带盘旋），锯头白热齿光。
//   s3：锯身变厚、血红刃口、重齿、慢转 0.9 圈 + 宽水带 + 地面短撕痕（血红冷却成暗红）。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

// 真半透明着色（blendPx）：p.shade 的 out.a < 1 会抖成棋盘点，这里一律走 blendPx
const shadeB = (p, x0, y0, x1, y1, fn) => {
  const o = { c: 0, a: 1 };
  p.each(x0, y0, x1, y1, (x, y, sx, sy) => { o.c = 0; o.a = 1; const c = fn(x, y, o) || o.c; if (c && o.a > 0) p.blendPx(sx, sy, c, Math.min(1, o.a)); });
};

export const meta = {
  name: "Specter saw ring unleashed",
  desc: "A ground-level 360-degree saw sweep: a steel cutting trace with uneven teeth at the head, navy water ribbons curling in, and a blood-red heavy saw for the pressure skill.",
  tags: ["melee", "saw", "spin", "water", "topdown", "one-shot"],
  size: [240, 180],
  origin: [120, 100],
  duration: 0.9,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    steel: ["#0b1222", "#1a2740", "#33476a", "#5d7396", "#93a8c4", "#cfdbe9", "#ffffff"],
    navy: OP.specter_unchained,   // 海军蓝七阶取 house.js（PRTS 饰「蓝披带」#152E57，组长 11-04 批）
    blood: ["#100403", "#2a0906", "#4a1108", "#741a0c", "#962614", "#b4482c", "#e0b8a8"],   // 暗血红（组长 C 11-04：色相压到 ≥ 8°、明度降一档，和危险色 #ff2667 拉开）
    spark: ["#ffffff", "#ffd8b8", "#ff8a4a", "#e2502a"],
    ember: ["#160605", "#3e0e08", "#7a1e0c", "#b8361a", "#e45a2a", "#ffa47a", "#fff0e6"],   // 方案甲：照原作普攻的红橙火星锯（色相 8–18°，避开危险色 342° 与结晶淡金）
    tone: "steel",    // steel = 冷钢蓝（方案乙）/ ember = 红橙火星（方案甲）
    radius: 51,       // 判定半径 / PX（reach 102 → 51；s3 × 1.5 → 76.5），由 targets 的 judge 传
    sy: 0.55,         // 地面透视
    move: "basic",
    elite: 2,
    quick: 0,         // 1 = 队友版（余韵减半）
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const s1 = o.move === "s1", s2 = o.move === "s2";
  // S2「生存的渴望」换冷钢（和普攻红橙一眼分开）
  const ST = fit(o.tone === "ember" && !s2 ? o.ember : o.steel, 7), NV = fit(o.navy, 7), BL = fit(o.blood, 7), SPK = fit(o.spark, 4);
  const Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), s3 = o.move === "s3", quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const R = +o.radius, SY = +o.sy;
  const DL = (s3 ? 1 : [0.45, 0.7, 1][el]) * (quick ? 0.5 : 1);     // 装饰余韵（docs/242 §10）
  const GK = s3 ? 1 : [0.35, 0.7, 1][el];                            // 光晕
  const PM = s3 ? 1.1 : [0.5, 0.8, 1][el];                           // 颗粒量
  const HOT = s3 ? 2 : [0.8, 1.6, 2.4][el];                          // 白热
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [SPK[0], SPK[1], SPK[2], SPK[3]], haze: NV[4] }), lights = new Lights();
  const dir = Rg.chance(0.5) ? 1 : -1;                              // 旋向（游戏里按朝向镜像）
  const SPIN = s3 ? 0.24 : 0.16;                   // 锯头转完的时长
  const TURN = s3 ? 0.9 : 1.12;                                      // 锯头转过的圈数
  const a0 = Rg.range(0, TAU);
  const BR = s3 ? R * 0.46 : R;                                     // 锯痕半径（S3 红锯在中心，外圈是浪墙）
  const W = BR * (s3 ? 0.42 : [0.24, 0.27, 0.3][el]);   // 拖影宽（锯头后的扇形运动模糊）
  const RAMP = s3 ? BL : ST;
  // 锯齿：不等距（jitter 步长）、大小不一、沿切向斜
  const teeth = [];
  for (let u = Rg.range(0, 0.1); u < 1; u += Rg.range(0.05, 0.11) * (s3 ? 1.3 : 1)) teeth.push({ u, h: Rg.range(0.7, 1.3) * (s3 ? 6 : 5), w: Rg.range(0.06, 0.1) });
  const at = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * SY];      // 地面椭圆上的点
  const depth = (a) => 0.5 + 0.5 * Math.sin(a);                      // 近（下半）亮、远（上半）暗
  const headAng = (t) => a0 + dir * TAU * TURN * ease.outCubic(clamp(t / SPIN));
  // 水带（E1 细、E2 / s3 宽且上卷）：螺旋从外圈 rOut 收到 R，绕 span 圈；lift = 往上卷的高度
  const ribs = [];
  if (el >= 1 || s2) ribs.push({
    span: s3 ? 0.95 : el === 1 ? 0.62 : 0.8, rOut: R * 0.98, rIn: R * (s3 ? 0.5 : el === 1 ? 0.62 : 0.55), w: s3 ? 6 : el === 1 ? 3.4 : 4.8,   // 核心不出判定：从刃口往里卷
    lift: s3 ? R * 0.26 : s2 ? R * 0.3 : el === 1 ? 0 : R * 0.22, b0: a0 - dir * Rg.range(0.6, 1.0), seed: o.seed + 21, t0: s3 ? 0.03 : 0.04, dur: s3 ? 0.3 : 0.24,
  });
  if (s2 && ribs.length) ribs.push(Object.assign({}, ribs[0], { b0: ribs[0].b0 + Math.PI + Rg.range(-0.4, 0.4), seed: o.seed + 27, w: ribs[0].w * 0.85, t0: 0.07, rIn: R * 0.48 }));   // S2：第二道水带从对面缠进来（原作 skill_02 蓝水带缠身）
  // S1「生存的技巧」：沿锯痕窜起的火舌（灯火越暗越拼命），位置不等距
  const flames = [];
  if (s1) for (let u = Rg.range(0, 0.06); u < 0.95; u += Rg.range(0.07, 0.15)) flames.push({ u, h: Rg.range(14, 26) * [0.75, 0.9, 1.1][el], w: Rg.range(2.4, 3.6), s: Rg.range(0, 99) });
  const scars = [];   // s3 地面撕痕：短而不规整，方向沿切线 ± 抖动
  if (s3) for (let a = Rg.range(0, 1); a < TAU - 0.3; a += Rg.range(0.8, 1.6)) scars.push({ a, L: Rg.range(10, 20), r: R * Rg.range(0.82, 1.02), tw: Rg.range(-0.5, 0.5) });
  // S3 浪墙（组长审片 11-04：照原作一整圈海军蓝浪墙把人包住）：沿螺旋从 0.72R 推进到 R，立起粗浪身，浪顶细亮线 + 断续白沫，开一道缺口；
  // 近侧（下半）画在红锯前面、远侧画在后面；不画外扩环——量级靠浪身体量和高度
  const WALL = s3 ? { span: 1.0, b0: a0 + dir * Rg.range(0.3, 0.8), gap: Rg.range(0.5, 0.62), seed: o.seed + 51 } : null;
  const wallR = (f) => R * (0.6 + 0.4 * ease.outCubic(f));
  const wallH = (f, k) => R * (0.12 + 0.3 * Math.sin(Math.PI * Math.min(1, f * 1.1))) * k * (0.7 + 0.45 * noise(f * 7, o.seed + 53) + 0.2 * noise(f * 19, o.seed + 57));
  // E2 浪尖（审片：E2 只是水带变宽不够）：卷刃水带的头立起成一道浪尖，往外卷翻、浪唇白沫，拍下时碎成飞沫
  const CREST = !s3 && !s2 && !s1 && el >= 2 && ribs.length ? { seed: o.seed + 61 } : null;
  let t = 0, passed = 0, landed = false, crested = false;

  function wall(p, t, side) {
    if (!WALL) return;
    const grow = ease.outCubic(clamp(t / 0.26)), gone = smooth(0.34, 0.72 * (0.6 + 0.4 * DL), t), rise = ease.outBack(clamp(t / 0.14)), fall = 1 - smooth(0.4, 0.75, t);
    if (grow - gone < 0.01) return;
    const N = Math.ceil(WALL.span * TAU * R / 0.45);
    for (let i = 0; i <= N; i++) {
      const f = i / N;
      if (f > grow || f < gone || Math.abs(f - WALL.gap) < 0.045) continue;   // 缺口
      const a = WALL.b0 + dir * WALL.span * TAU * f, sn = Math.sin(a);
      if ((side === "near") !== (sn > 0)) continue;
      const r = wallR(f), [gx, gy] = at(a, r), dk = depth(a);
      const head = clamp((grow - f) / 0.08), tail = clamp((f - gone) / 0.12);
      const H = wallH(f, rise * fall) * Math.min(1, head * 1.5 + 0.3) * Math.min(1, tail * 1.5 + 0.2);
      if (H < 1) continue;
      const lean = dir * 0.25 * H;   // 浪顶顺推进方向前倾
      const tx = -Math.sin(a), ty = Math.cos(a) * SY;
      for (let d = 0; d < H; d += 0.5) {
        const v = d / H, x = gx + tx * lean * v * v, y = gy - d + ty * lean * v * v;
        const top = d > H - 1.2, foam = top && noise(f * 23, WALL.seed) > -0.15;
        const streak = noise(f * 41 + v * 2, WALL.seed + 3) + 0.5 * noise(f * 97, WALL.seed + 5);   // 竖向水纹（浪身不是平涂）
        const ci = foam ? 6 : top ? 5 : clamp(Math.round(0.6 + 2.2 * v + 0.9 * dk + 1.1 * streak), 1, 4);
        p.blendPx(p.cellX(x, y), p.cellY(x, y), NV[ci], v < 0.15 ? 0.75 : 0.95);
      }
    }
  }

  function crest(p, t) {   // E2 浪尖：在卷刃水带的头部立起、往外卷翻
    if (!CREST) return;
    const rb = ribs[0], aE = rb.b0 + dir * rb.span * TAU * 0.85, [bx, by] = at(aE, R * 0.92);
    const u = t - 0.1, rise = ease.outCubic(clamp(u / 0.1)), brk = smooth(0.1, 0.22, u), k = 1 - smooth(0.2, 0.34, u);
    if (u < 0 || k <= 0.02) return;
    const H = R * 0.6 * rise, ox = Math.cos(aE), oy = Math.sin(aE) * SY, ol = Math.hypot(ox, oy) || 1;
    const dx = ox / ol, dy = oy / ol;   // 往外
    for (let s = 0; s <= 1; s += 0.012) {
      // 浪身：从地面立起，到顶往外卷（唇 = s > 0.7 往外再往下）
      const up = H * Math.sin(Math.PI / 2 * Math.min(1, s / 0.75));
      const curl = s > 0.7 ? (s - 0.7) / 0.3 : 0;
      const x = bx + dx * (H * 0.35 * s + H * 0.45 * curl + 6 * brk), y = by + dy * H * 0.35 * s - up + H * 0.5 * curl * curl * (0.6 + brk);
      const w = (5.6 * (1 - s * 0.75) + 0.7) * k;
      for (let d = -w; d <= w; d += 0.5) {
        const e = Math.abs(d) / w, lip = s > 0.82 && d > w - 1.2;
        const ci = lip ? 6 : clamp(Math.round(1.8 + 2.6 * s + (1 - e)), 1, 5);
        p.blendPx(p.cellX(x - dy * d, y + dx * d), p.cellY(x - dy * d, y + dx * d), NV[ci], (e > 0.8 ? 0.55 : 0.92) * k);
      }
    }
  }


  function band(p, t) {   // 锯痕：锯头扫过的那段刃迹（头亮尾暗），首帧白热；随时间从尾部收掉
    const head = clamp(t / SPIN), tailK = smooth(SPIN * 0.4, SPIN + 0.22 * (0.6 + 0.4 * DL), t);
    const tot = TAU * TURN * ease.outCubic(head), VIS = TAU * (s3 ? 0.5 : 0.55);   // 只留锯头后约 0.7 圈：读成在转的锯，不读成闭合圆环
    const tl = Math.max(tot - VIS, tot * tailK);
    if (tot - tl < 0.02) return;
    const hot = t < 0.045 ? HOT : t < 0.09 ? 0.4 : 0;
    const B = BR + W + 4;
    shadeB(p, -B, -B * SY - 2, B, B * SY + 2, (x, y, out) => {
      const yy = y / SY, r = Math.hypot(x, yy), ang = Math.atan2(yy, x);
      let u = (dir * (ang - a0)) % TAU;
      if (u < 0) u += TAU;
      // 第二圈的部分（tot > TAU）：取最靠锯头的那一层
      let s = u;
      while (s + TAU <= tot) s += TAU;
      if (s > tot || s < tl) return;
      const v = (s - tl) / Math.max(0.01, tot - tl);                // 0 尾 → 1 头
      const jag = 1.2 * noise(ang * 9, o.seed) + 0.7 * noise(ang * 23, o.seed + 5);
      const w = W * (0.3 + 0.7 * Math.pow(v, 0.9)) + jag * 0.6;
      const q = (BR + 0.5 - r) / Math.max(0.6, w);                   // 0 外缘 → 1 内缘
      if (q < -0.15 || q > 1) return;
      const fib0 = noise(r * 0.32, o.seed + 41) + 0.3 * noise(s * 1.5, o.seed + 43);
      if (q > 0.35 && fib0 < -0.35 + 0.6 * q) return;                // 内侧碎成一条条纤维（不铺实色块）
      const dk = depth(ang);
      if (q < 0.18 && v > 0.15) { out.c = RAMP[hot > 1 ? 6 : v > 0.7 ? 5 : 4]; out.a = 1; return; }   // 外缘 1 格亮刃线
      const fib = noise(r * 1.3, o.seed + 31) + 0.5 * noise(r * 3.1 + s * 2, o.seed + 37);   // 沿转向的纤维纹（运动模糊感），只提亮
      let ci = Math.round(2.2 + 2.8 * v * (0.7 + 0.3 * dk) + hot * 0.8 - q * 1.4 + Math.max(0, fib) * 1.2);
      out.c = RAMP[clamp(ci, 1, 6)];
      out.a = (q > 0.55 ? 0.6 : 0.95) * (0.55 + 0.45 * v);
    });
  }

  function toothPts(p, t) {   // 锯头一段的锯齿：只在锯头附近 0.9 rad 内出现，跟着转
    const hA = headAng(t), k = 1 - smooth(SPIN, SPIN + 0.14, t), span = Math.min(TAU * (s3 ? 0.5 : 0.55), TAU * TURN * ease.outCubic(clamp(t / SPIN)));   // 锯齿铺满可见的拖影段
    if (k <= 0.02) return;
    for (const th of teeth) {
      const a = hA - dir * th.u * span;
      const fade = (1 - th.u * 0.8) * k;
      if (fade < 0.08) continue;
      const h = th.h * (0.6 + 0.4 * fade), dk = depth(a);
      // 三角齿：底在刃线上（宽 th.w rad），尖沿切向前倾、往外 h
      const [bx0, by0] = at(a, BR), [bx1, by1] = at(a - dir * th.w, BR), [tx, ty] = at(a + dir * th.w * 0.8, BR + h);
      const hot = t < 0.05 && th.u < 0.3;
      const steps = Math.ceil(h * 1.6) + 2;
      for (let i = 0; i <= steps; i++) {
        const f = i / steps, lx = bx0 + (tx - bx0) * f, ly = by0 + (ty - by0) * f, rx = bx1 + (tx - bx1) * f, ry = by1 + (ty - by1) * f;
        const n = Math.ceil(Math.hypot(rx - lx, ry - ly) / 0.6) + 1;
        for (let j = 0; j <= n; j++) {
          const g = j / n, x = lx + (rx - lx) * g, y = ly + (ry - ly) * g, edge = j === 0 || f > 0.8;
          const ci = hot ? 6 : clamp(Math.round((edge ? 4 : 2) + 1.5 * dk + fade), 1, s3 ? 5 : 6);
          p.blendPx(p.cellX(x, y), p.cellY(x, y), RAMP[ci], (edge ? 1 : 0.85) * Math.min(1, fade * 1.6));
        }
      }
    }
  }

  function flameDraw(p, t) {   // S1 火舌：锯痕外缘往上窜，底亮梢暗，随锯痕一起收
    const k0 = 1 - smooth(SPIN, SPIN + 0.3 * (0.6 + 0.4 * DL), t), span = Math.min(TAU * 0.55, TAU * TURN * ease.outCubic(clamp(t / SPIN)));
    if (k0 <= 0.02) return;
    const hA = headAng(t);
    for (const fl of flames) {
      const a = hA - dir * fl.u * span, k = k0 * (1 - fl.u * 0.7);
      const H = fl.h * k * (0.7 + 0.3 * noise(t * 18 + fl.s, o.seed + 71));
      if (H < 1.5) continue;
      const [bx, by] = at(a, R - 1), sway = 1.5 * noise(t * 9 + fl.s, o.seed + 73);
      for (let d = 0; d < H; d += 0.5) {
        const f = d / H, hw = fl.w * Math.pow(1 - f, 0.7);
        const ci = clamp(Math.round(5.4 - 3 * f + (t < 0.06 ? 1 : 0)), 2, 6);
        for (let w = -hw; w <= hw; w += 0.55) p.blendPx(p.cellX(bx + w + sway * f, by - d), p.cellY(bx + w + sway * f, by - d), ST[ci], (f > 0.75 ? 0.55 : 0.9) * Math.min(1, k * 1.5));
      }
    }
  }

  function ribbon(p, t, rib) {   // 水带：沿螺旋从外往里收（E1 平铺地面、E2 / s3 往上卷），边缘撕裂（noise），浪尖白沫
    const u = t - rib.t0;
    if (u < 0) return;
    const grow = ease.outCubic(clamp(u / rib.dur)), gone = smooth(rib.dur * 0.6, rib.dur + 0.32 * (0.5 + 0.5 * DL), u);
    if (grow - gone < 0.02) return;
    const N = Math.ceil(rib.span * TAU * rib.rOut / 0.55);
    for (let i = 0; i <= N; i++) {
      const f = i / N;                                               // 0 外端（起点）→ 1 内端
      if (f > grow || f < gone) continue;
      const a = rib.b0 + dir * rib.span * TAU * f, r = rib.rOut + (rib.rIn - rib.rOut) * ease.inOutSine(f);
      const lift = rib.lift * Math.sin(Math.PI * f) * (1 - gone);
      const [cx, cyg] = at(a, r), cy = cyg - lift;
      const head = clamp((grow - f) / 0.12);                           // 水带头部细、身体粗
      const tear = 0.55 + 0.45 * noise(f * 13, rib.seed) + 0.35 * noise(f * 31, rib.seed + 3);
      const w = rib.w * tear * Math.min(1, head * 1.4 + 0.2);
      if (w < 0.4) continue;
      // 法向（地面椭圆上的径向，抬起时偏竖直）
      const nx = Math.cos(a), ny = Math.sin(a) * SY + (rib.lift > 0 ? -0.6 : 0), nl = Math.hypot(nx, ny);
      const dk = depth(a);
      for (let d = -w; d <= w; d += 0.55) {
        const x = cx + nx / nl * d, y = cy + ny / nl * d, e = Math.abs(d) / w;
        const crest = d < -w + 1.1 && noise(f * 19, rib.seed + 7) > -0.1;   // 内侧浪尖白沫（断续）
        const groove = noise(f * 9 + d * 0.4, rib.seed + 11);
        const ci = crest ? (el >= 2 || s3 ? 6 : 5) : clamp(Math.round(1.5 + 2.4 * dk + 1.2 * groove - e * 1.2 + (t < 0.08 ? 1 : 0)), 1, 5);
        p.blendPx(p.cellX(x, y), p.cellY(x, y), NV[ci], (e > 0.8 ? 0.5 : 0.9) * (1 - 0.5 * clamp((f - gone) < 0.1 ? 1 - (f - gone) / 0.1 : 0)));
      }
    }
  }

  function scarDraw(p, t) {   // s3 地面撕痕：落刀处一道道短口子，血红 → 暗红冷却
    for (const s of scars) {
      const u = t - 0.06 - (dir * (s.a - a0) + TAU) % TAU / (TAU * TURN) * SPIN;
      if (u < 0 || u > 0.75) continue;
      const k = 1 - smooth(0.35, 0.75, u), ta = s.a + dir * Math.PI / 2 + s.tw;
      const [x0, y0] = at(s.a, s.r), L = s.L * ease.outCubic(clamp(u / 0.05));
      for (let d = 0; d < L; d += 0.5) {
        const f = d / s.L, x = x0 + Math.cos(ta) * (d - L / 2), y = y0 + Math.sin(ta) * (d - L / 2) * SY;
        const hw = 1.2 * Math.sin(Math.PI * Math.min(1, f)) + 0.3;
        const c = u < 0.08 ? BL[5] : u < 0.2 ? BL[4] : BL[2];
        for (let w = -hw; w <= hw; w += 0.6) p.blendPx(p.cellX(x, y + w), p.cellY(x, y + w), Math.abs(w) > hw - 0.6 ? BL[1] : c, 0.9 * k);
      }
    }
  }

  return {
    update(dt) {
      t += dt;
      // 锯头甩火星：沿切向往外，步长随机（不等距）
      const tot = TURN * ease.outCubic(clamp(t / SPIN));
      while (passed < tot && passed < TURN) {
        const a = a0 + dir * TAU * passed, [x, y] = at(a, BR + 1), tx = -Math.sin(a) * dir, ty = Math.cos(a) * dir * SY;
        if (Rg.chance(0.36 * PM)) {   // 组长 C：数量砍半，只沿切线、贴着锯缘
          const sp = Rg.range(120, 260);
          ps.spawn(P.SPARK, x, y, tx * sp, ty * sp - Rg.range(10, 40), Rg.range(0.1, 0.24) * (0.6 + 0.4 * DL));   // 只沿锯刃切向（docs/242 §14.7：不往外甩）
        }
        if (deco && Rg.chance(0.15 * PM)) ps.spawn(P.MOTE, x, y, tx * Rg.range(20, 50), ty * Rg.range(20, 50) - 8, Rg.range(0.2, 0.4) * DL, (s3 ? BL : NV)[5], Rg.range(0.6, 1.0));
        passed += Rg.range(0.02, 0.07) / (s3 ? 1.2 : 1);
      }
      if (CREST && !crested && t >= 0.32) {   // 浪尖拍下：顺外翻方向碎成飞沫（装饰）
        crested = true;
        const rb = ribs[0], aE = rb.b0 + dir * rb.span * TAU * 0.85, [bx, by] = at(aE, R * 0.95);
        for (let i = 0; i < 8; i++) ps.spawn(i % 3 ? P.MOTE : P.STAR, bx + Rg.range(-5, 5), by - Rg.range(0, 10), Rg.range(-6, 6), -Rg.range(10, 30), Rg.range(0.25, 0.5) * DL, NV[5 + Rg.int(0, 1)], Rg.range(0.7, 1.2));   // 浪尖拍下的白沫原地往上散（§14.7 不往外甩）
      }
      if (WALL && !crested && t >= 0.3) {   // 浪墙塌下：浪顶甩出白沫（步长随机）
        crested = true;
        for (let f = Rg.range(0, 0.05); f < 1; f += Rg.range(0.03, 0.08)) {
          if (Math.abs(f - WALL.gap) < 0.05) continue;
          const a = WALL.b0 + dir * WALL.span * TAU * f, [x, y] = at(a, wallR(f));
          ps.spawn(Rg.chance(0.7) ? P.MOTE : P.STAR, x, y - wallH(f, 1) * 0.8, Rg.range(-6, 6), -Rg.range(15, 40), Rg.range(0.35, 0.7) * DL, NV[5 + Rg.int(0, 1)], Rg.range(0.7, 1.3));   // 浪顶白沫往上散（§14.7 不往外甩）
        }
      }
      if (!landed && t >= SPIN) {
        landed = true;
        const hE = headAng(SPIN);
        if (deco) for (let u = Rg.range(0, 0.15); u < TAU * 0.5; u += Rg.range(0.45, 1.0) / PM) {   // 余韵：只在锯头后半圈拖影上散几点碎光（组长 C：不绕满一圈）
          const a = hE - dir * u, [x, y] = at(a, BR + Rg.range(-2, 2));
          ps.spawn(P.MOTE, x, y, 0, -Rg.range(6, 18), Rg.range(0.3, 0.6) * DL, NV[4 + Rg.int(0, 1)], Rg.range(0.6, 1.0), Rg.range(0, 0.06));   // 原地往上飘（不用 VAPOUR 软圆团；不往外甩，§14.7）
          if (el >= 1 && Rg.chance(0.35)) ps.spawn(P.STAR, x, y - Rg.range(0, 6), 0, -8, Rg.range(0.3, 0.6) * DL, (s3 ? BL : NV)[6], Rg.range(0.8, 1.4), Rg.range(0.03, 0.3) * DL);
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (core) wall(p, t, "far");
      if (core) for (const rb of ribs) ribbon(p, t, rb);
      if (core) band(p, t);
      if (core) toothPts(p, t);
      if (core) wall(p, t, "near");
      if (core) crest(p, t);
      if (core && s1) flameDraw(p, t);
      if (deco && t < SPIN + 0.1) {   // 锯头光：顺锯缘拉长的一段（沿弧几个小光点），不画一团圆光（组长 C 11-04）
        const hA = headAng(t), k = 0.35 * GK * (1 - clamp((t - SPIN) / 0.1));
        for (let i = 0; i < 6; i++) {
          const [x, y] = at(hA - dir * i * 0.07, BR - 1);
          p.glow(x, y, (s3 ? 7 : 5) * (1 - i / 7), s3 ? BL[5] : s2 ? NV[4] : ST[5], k * (1 - i / 6));
        }
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
