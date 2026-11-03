// 逻各斯放开版（docs/242；开关 fx/px_unleashed），按原作 logos.ab 还原（Claude outputs/logos_ref/）的形状、颜色、层次、节奏做像素化：
//   普攻 attack_start / trail / hit_01，S1「提喻」= 原作 S2 skill2_hitloop_01/02（每跳）+ start / buff（锁定）。
// 原作语汇：白色四芒星（首帧白、随后转深蓝再转黑，留一颗暗星）、白色锯齿尖刺（cici）、白色碎字符（flipbook_214）、
//   深蓝黑墨羽（logos_cb，蓝色描边）、白头墨尾的弹体（logos_zidan + 深色拖尾 + 蓝色细芯线）、零星淡星点（star_114）。
// move：atk_start（原点 = 笔尖）/ atk_bolt（弹体循环，原点 = 弹头，正右 = 飞行方向）/ atk_hit（原点 = 命中点，正右 = 弹道方向）/
//       s1_tick（原点 = 目标身体中心，正右 = 从逻各斯指向目标）/ s1_lock（原点 = 目标脚底）。
// 分档（docs/91）：E0 原作基础形；E1「剜魂」加白色字符（碎字符 / 一段字符带）；E2「连缀」质变：深蓝墨羽从命中处甩开 + 暗星更大、紫色重点。
import { Particles, Lights, P, Rng, fit, hex, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos ink unleashed",
  desc: "Logos's attack and skill hits after the original: a solid white four-point star that flashes on contact and cools to a navy star, a few jagged thorns or a solid glyph band, and heavy glyph chunks that drop, bounce once and cool out.",
  tags: ["arcane", "ink", "glyph", "star", "one-shot"],
  size: [200, 160],
  origin: [100, 80],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#07081a", ...OP.logos],   // house.js OP.logos 7 阶（§14，组长 B 11-04），最暗一阶为压暗底色
    accent: "#a487ff",
    move: "atk_hit",
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 3,
  },
};

// 碎字符（照原作 flipbook_214 九格的笔画意思重画，1x 像素，"#" = 白）
const GLY = [
  ["#.#", "#.#", "...", ".#."],
  ["##", "##", "#.", "##"],
  ["#.#", "#.#", "###", "#.#"],
  ["##.", "#.#", "###"],
  [".#", "##", "#."],
  ["###", "#..", "###"],
  ["#", "##", "#", "#"],
  ["###", ".#.", ".#."],
  ["##", "#.", "##", ".#"],
];
// 一段字符带（原作 logos_zifu_01：一行白色字符）
const BAND = ["#.#.##.#..###.#.#.##..#.##.#", "###.#..##.#.#.##..#.#.#..###", "#.#.##.#..#.#.#.##.##.#.#..#"];

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0, mv = o.move || "atk_hit";
  const core = o.layer !== "deco", deco = o.layer !== "core", ACC = hex(o.accent);
  const TS = [1, 1.25, 1.5][el], TW = [1, 1.3, 1.45][el];   // 分档：主形体量 / 粗细（组长 B 11-04 硬标准：只加在主形上）
  const DL = [0.5, 0.7, 1.15][el] * (quick ? 0.5 : 1), GK = [0.25, 0.42, 0.6][el], PM = [0.6, 0.85, 1.15][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[2] }), lights = new Lights();
  const isS1 = mv.startsWith("s1"), isS2 = mv.startsWith("s2"), isHit = mv === "atk_hit" || mv === "s1_tick" || mv === "s2_hit" || mv === "s2_exec" || mv === "s3_hit" || mv === "ult_burst", isS3 = mv.startsWith("s3"), isBolt = mv === "atk_bolt" || mv === "s3_bolt", isStart = mv === "atk_start" || mv === "s2_cast";
  let t = 0;

  // ---- 四芒星（一招的实心主形，§0.1）：四臂长短不等、根部宽梢尖的实心三角；hot 2 = 定帧爆亮（全白、略大），1 = 冷却中（浅蓝），0 = 原作 AB 暗星（近黑身 + 蓝描边）
  function star(p, x, y, L, k, dark, hot = 1) {
    const arms = [[1, 0, L[0]], [-1, 0, L[1]], [0, -1, L[2]], [0, 1, L[3]]];
    if (el >= 2) {   // E2 质变：四芒星 → 八芒星，斜臂短一截、用 E2 专属紫（先画，被正臂压在下面）
      for (const [ang, len] of [[-0.62, L[0] * 0.85], [-2.3, L[1] * 0.6], [0.95, L[1] * 0.45], [2.55, L[0] * 0.7]]) {   // 斜臂不等角、不等长（规整八芒星过不了放射检查，也显得机械）
        const dx = Math.cos(ang), dy = Math.sin(ang);
        const n = Math.round(len * k), W = Math.max(1.6, len * 0.2) * TW;
        for (let i = 0; i <= n; i++) {
          const v = i / Math.max(n, 1), hw = W * Math.pow(1 - v, 1.3);
          for (let q = -Math.ceil(hw); q <= Math.ceil(hw); q++) {
            if (Math.abs(q) > hw + 0.35) continue;
            const edge = Math.abs(q) > hw - 0.8 || v > 0.85;
            p.px(Math.round(x + dx * i - dy * q), Math.round(y + dy * i + dx * q), dark ? (edge ? ACC : C[1]) : hot >= 2 && !edge ? C[7] : ACC);
          }
        }
      }
    }
    for (const [dx, dy, len] of arms) {
      const n = Math.round(len * k), W = Math.max(1.5, len * 0.17) * (hot >= 2 ? 1.2 : 1) * TW;
      for (let i = 0; i <= n; i++) {
        const v = i / Math.max(n, 1), hw = W * Math.pow(1 - v, 1.3);
        for (let q = -Math.ceil(hw); q <= Math.ceil(hw); q++) {
          if (Math.abs(q) > hw + 0.35) continue;
          const edge = Math.abs(q) > hw - 0.8 || v > 0.85;
          const ci = dark ? (edge ? 3 : v < 0.25 ? 0 : 1) : hot >= 2 ? (edge && v > 0.5 ? 6 : 7) : (edge ? 5 : v < 0.2 && mv !== "ult_burst" ? 7 : 6);   // 冷却中：只留芯一点白
          p.px(x + dx * i + dy * q, y + dy * i + dx * q, C[ci]);
        }
      }
    }
  }
  // ---- 地面受光（Noita：发光照地，§0.2）：命中点下方一片压扁的光斑，随主形冷却变暗
  function groundGlow(p, gy, rx, ry, col, a) {
    if (a <= 0.01) return;
    for (let y = -Math.ceil(ry); y <= Math.ceil(ry); y++) for (let x = -Math.ceil(rx); x <= Math.ceil(rx); x++) {
      const d = (x * x) / (rx * rx) + (y * y) / (ry * ry);
      if (d < 1) p.light(x, gy + y, col, a * 0.6 * (1 - d) * (1 - d));   // 加色照亮（dot 带透明度会抖成棋盘格，脏）
    }
  }
  // ---- 实心字符带（§0.4 不碎：字符做成实心带上的暗色镂空，不再一颗颗散点）：沿椭圆弧 a0 → a1 画宽 w 的带，BAND 图案处挖成暗色
  function glyphBand(p, cx, cy, rx, ry, a0, a1, w, col, cut, prog, fade, seed) {
    const len = Math.abs(a1 - a0) * Math.max(rx, ry), n = Math.max(4, Math.round(len * 1.6));
    for (let i = 0; i <= n * prog; i++) {
      const v = i / n, a = a0 + (a1 - a0) * v, ca = Math.cos(a), sa = Math.sin(a);
      const taper = Math.sin(Math.PI * clamp(v * 0.96 + 0.02)), hw = w * (0.45 + 0.55 * taper);
      for (let q = 0; q < hw; q += 0.5) {
        if (fade > 0 && noise2(i * 0.35, q * 2 + seed, 17) < fade * 2 - 1) continue;
        const ci = Math.floor(i / 1.6) % BAND[0].length, r = q > hw * 0.3 && q < hw * 0.7 && BAND[1][ci] === "#" && BAND[0][ci] === "#";   // 只在带心一行稀疏镂空
        p.px(cx + ca * (rx + q), cy + sa * (ry + q * 0.55), r ? cut : col);
      }
    }
  }
  // ---- 锯齿尖刺（原作 trail_208）：根宽梢尖，一侧锯齿；颜色 白 → 蓝 → 深蓝
  function thorn(p, a, len, w, age, seed) {
    const ca = Math.cos(a), sa = Math.sin(a), B = len + 2;
    const col = age < 0.06 ? 7 : age < 0.14 ? 6 : age < 0.24 ? 5 : 3;
    p.shade(-B, -B, B, B, (x, y, out) => {
      const u = x * ca + y * sa, s = -x * sa + y * ca;
      if (u < 0 || u > len) return;
      const v = u / len, saw = (((u * 0.55 + seed) % 1) + 1) % 1;
      const hw = w * Math.pow(1 - v, 0.9) * (s > 0 ? 1 : 0.55 + 0.45 * saw) + 0.3;
      if (Math.abs(s) > hw) return;
      const edge = Math.abs(s) > hw - 0.7 || v > 0.75;
      out.c = C[edge ? Math.min(7, col) : Math.max(2, col - (v > 0.4 ? 2 : 1))];   // 刺身比描边暗一到两阶（原作灰白刺）
      out.a = 1;
    });
  }
  // ---- 深蓝墨羽（原作 logos_cb）：弯弧主笔、一侧拉出几根倒刺，暗底蓝描边
  function feather(p, f, k, fade) {
    const n = 40, pts = [];
    for (let i = 0; i <= n; i++) {
      const v = i / n, a = f.a + f.bend * (v - 0.5);
      pts.push([f.x + Math.cos(a) * f.L * (v - 0.2) * k + Math.cos(f.a + Math.PI / 2) * Math.sin(v * Math.PI) * f.arc, f.y + (Math.sin(a) * f.L * (v - 0.2) * k + Math.sin(f.a + Math.PI / 2) * Math.sin(v * Math.PI) * f.arc) * 0.6]);
    }
    for (let i = 0; i < n; i++) {
      const v = i / n, [x, y] = pts[i], [x2, y2] = pts[i + 1], w = f.w * Math.sin(Math.PI * clamp(v * 0.95 + 0.03)) * (1 - fade * 0.5);
      let nx = -(y2 - y), ny = x2 - x; const nl = Math.hypot(nx, ny) || 1; nx /= nl; ny /= nl;
      for (let q = -w; q <= w; q += 0.5) {
        const edge = q > w - 0.8;
        if (fade > 0 && noise2(i * 0.7, q * 2, f.s) < fade * 2 - 1) continue;
        p.px(x + nx * q, y + ny * q, edge ? (el >= 2 && v > 0.6 ? ACC : C[4]) : C[q < 0 ? 0 : 1]);
      }
      if (i % f.barbEvery === f.barbOff && v > 0.25 && v < 0.85) {   // 倒刺
        for (let j = 0; j < f.barb * (1 - fade); j++) p.px(x + nx * (w + j) - (x2 - x) * j * 0.8, y + ny * (w + j) - (y2 - y) * j * 0.8, C[j < 1 ? 4 : 1]);
      }
    }
  }
  function glyph(p, g, x, y, col) {
    const rows = GLY[g];
    for (let r = 0; r < rows.length; r++) for (let c = 0; c < rows[r].length; c++) if (rows[r][c] === "#") p.px(x + c, y + r, col);
  }

  // ---------------- 命中（普攻 hit_01 / S1 hitloop）
  const S1R = isS1 ? 1.15 : mv === "s2_exec" ? 1.3 : mv === "s3_hit" ? 1.35 : mv === "ult_burst" ? 2.2 : 1;
  const SL = [Rg.range(17, 22), Rg.range(13, 17), Rg.range(10, 14), Rg.range(9, 12)].map((v) => v * 0.78 * TS * S1R);   // 四臂：横长竖短（原作 star_06 / 164）
  // §0.4 不碎：一招同时 ≤3 种元素。主形 = 实心四芒星；第二种 = 尖刺（普攻 E0–E1 / S3）或墨羽（普攻 E2 质变）或字符带 / 符文条（S1 / S2 / 终结技）；
  // 第三种 = 有重量的字符碎块（落地弹一下、慢慢冷却熄灭，§0.2）。放射细光、淡星点、旋涡细段、下落细光都删了（满屏细线细点）
  const isAtk = mv === "atk_hit";
  const thorns = [];
  for (let i = 0, n = isAtk ? Rg.int(2, 3) : mv === "s3_hit" ? 3 : 0; i < n; i++)   // 尖刺是陪衬：比主形短、按档同比放大
    thorns.push({ a: Rg.range(0, TAU), len: Rg.range(9, 13) * TS * S1R, w: Rg.range(2.2, 2.8) * TW, d: Rg.range(0.02, 0.05), s: Rg.range(0, 1) });
  const GY = mv === "ult_burst" ? 22 : isS1 ? 12 : 10;   // 地面（命中点 = 目标身体中心，往下约半个身高是脚底）
  const chunks = [];   // 字符碎块：贴着命中点小幅弹起、落地、弹一次、躺着冷却（不往外甩，§14.7）
  const nCh = !isHit ? 0 : mv === "ult_burst" ? 7 : mv === "s3_hit" || mv === "s2_exec" ? 4 : [2, 3, 3][el];
  for (let i = 0; i < nCh; i++) {
    const side = i % 2 ? 1 : -1;
    chunks.push({ g: Rg.int(0, GLY.length - 1), x: Rg.range(-3, 3), y: Rg.range(-4, 2), vx: side * Rg.range(12, 32) * (mv === "ult_burst" ? 1.8 : 1), vy: -Rg.range(40, 85), d: Rg.range(0.03, 0.09), rest: 0, cool: Rg.range(0.35, 0.55) });
  }
  const feathers = [];
  if (false) for (let i = 0, n = Rg.int(2, 3); i < n; i++) {   // 普攻 E2 墨羽：分档新规只加在主形上，停用
    const a = (i % 2 ? Math.PI : 0) + Rg.range(-0.5, 0.5);
    feathers.push({ x: Rg.range(-4, 4), y: Rg.range(4, 10), a, bend: Rg.range(-0.6, 0.6), L: Rg.range(26, 36), arc: Rg.range(-7, 7), w: Rg.range(1.8, 2.6), barb: Rg.int(3, 5), barbEvery: Rg.int(5, 8), barbOff: Rg.int(0, 4), s: Rg.int(1, 999), d: Rg.range(0.03, 0.08) });
  }
  const band = { a: Rg.range(-0.35, 0.35), r: Rg.range(15, 19), d: 0.05 };   // E1+ S1：绕目标的一段实心字符带（原作 hit_03 / buff_03 字环的意思，半圈不闭合）

  // S2「殁亡」= 原作 skill1：技能期间命中多一圈字符环（原作 hit_01 ring_01 (2)/(3)：logos_zifu 网格环，白 → 褐 → 深蓝，转成本作白 → 灰蓝 → 深蓝），
  // 处决 = 原作 hit_03：竖立的白色符文柱（fuwen，3–4 根，位置 / 高低 / 先后都随机）+ 往下落的白色细光（lizi）+ 暗旋涡（wenli），不出尖刺
  const ring = { a0: Rg.range(0, TAU), span: Rg.range(3.8, 4.6), r: mv === "s2_exec" ? 18 : 20 };   // 技能期间命中的字符环比普攻大一圈，一眼和普攻分开（§12.1）
  const pillars = [];
  if (mv === "s2_exec" || mv === "ult_burst") {
    let x = Rg.range(-15, -11) * (mv === "ult_burst" ? 2 : 1);
    for (let i = 0, n = mv === "ult_burst" ? 5 : el >= 2 ? 3 : 2; i < n; i++) { pillars.push({ x: Math.round(x), h: Rg.int(6, 9), tilt: (i % 2 ? 1 : -1) * Rg.range(0.25, 0.5), d: Rg.range(0.02, 0.1), g0: Rg.int(0, 8) }); x += Rg.range(9, 14) * (mv === "ult_burst" ? 1.4 : 1); }   // 原作 fuwen：斜立的长条符文，互相交叉
  }
  // ---------------- 普攻起手：笔尖白弧 + 暗弧挥过，收笔处一颗四芒星（原作 attack_start_01 / 03）
  const swing = { a0: Rg.range(-1.3, -1.1), span: Rg.range(1.5, 1.8), R: Rg.range(14, 16), cx: -9, cy: 8 };   // 原作挥笔弧：从头右上往身前左下挥一道月牙（11-04 录像里整圈 3 rad 读成人物身边的白圈，§12.3，收到 1.5–1.8 rad）
  // ---------------- 弹体：白色菱形笔尖 + 深色墨尾 + 蓝色细芯线（原作 logos_zidan + trail_ds / zs / xian）
  const BOLT_T = 0.25;

  // S3 开启（原作 skill3_start_02）：一团实心暗墨往笔尖收（蓄势 0–0.45 s）→ 白色四芒星爆亮 → 字符碎块落下冷却
  if (mv === "s3_cast") for (let i = 0; i < 4; i++) { const side = i % 2 ? 1 : -1; chunks.push({ g: Rg.int(0, GLY.length - 1), x: Rg.range(-3, 3), y: Rg.range(-3, 1), vx: side * Rg.range(14, 30), vy: -Rg.range(45, 80), d: 0.46 + Rg.range(0, 0.05), rest: 0, cool: Rg.range(0.3, 0.45) }); }
  const CAST_GY = 14;
  let burst = false;
  return {
    update(dt) {
      t += dt;
      if (!burst && t >= 0.0 && isHit) {
        burst = true;
        if (deco) {
          lights.add(0, 0, 7 * S1R, C[6], GK * 1.2, 0.08);   // 命中点光：小而短、不随档变大（大圆光读成孤立圆，组长 B 11-04）
          for (let i = 0; i < 1 + (el >= 1 ? 1 : 0); i++) ps.spawn(P.SMOKE, Rg.range(-4, 4), Rg.range(-2, 2), Rg.range(-8, 8), Rg.range(-10, -4), Rg.range(0.45, 0.7) * DL + 0.15, C[1], Rg.range(3.5, 5.5) * Math.min(S1R, 1.6), 0.08);   // 一两团暗墨烟慢慢升起散掉（原作 glow_andi；Noita 烟会散）
        }
      }
      for (const c of chunks) {   // 字符碎块：重力下落、落地弹一次、躺着冷却
        if (t < c.d) continue;
        if (c.rest > 0) { c.rest += dt; continue; }
        c.vy += 520 * dt; c.x += c.vx * dt; c.y += c.vy * dt; c.vx -= c.vx * 1.5 * dt;
        const gy = mv === "s3_cast" ? CAST_GY : GY;
        if (c.y >= gy) { c.y = gy; if (c.vy > 70) { c.vy = -c.vy * 0.3; c.vx *= 0.5; } else { c.vy = 0; c.rest = dt; } }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (!deco) return;
      if (isHit) {
        const k = 1 - smooth(0.02, 0.2 + 0.15 * DL, t);
        if (k > 0 && !isS1) { const L = [10, 12, 14][el] * S1R; p.glowLine(-L, 0, L, 0, 3, C[5], GK * k); p.glowLine(0, -L * 0.7, 0, L * 0.7, 3, C[5], GK * k * 0.8); }   // 十字星芒自带的短光（不用圆晕：E1 / E2 正圆光晕随档变大读成孤立圆，组长 B 11-04）
        const dk = smooth(0.05, 0.12, t) * (1 - smooth(0.25, 0.25 + 0.4 * DL, t));
        if (dk > 0) p.glow(0, 0, [10, 14, 18][el] * S1R, C[0], 0.5 * dk);   // 暗晕（AB 黑）
        const gk = 1 - smooth(0.04, 0.3 + 0.2 * DL, t);   // 地面受光：爆亮时最亮，跟主形一起冷却
        groundGlow(p, GY, 16 * Math.min(S1R, 1.6), 3.2, C[5], (0.55 + 0.15 * el) * gk);
      }
      if (isBolt) p.glowLine(isS3 ? -40 : -26, 0, 0, 0, isS3 ? 9 : 6, C[3], 0.25), p.glow(0, 0, isS3 ? 10 : 7, C[6], 0.35);
      if (mv === "s3_cast") {
        const b = t - 0.45, k = b < 0 ? 0.25 * clamp(t / 0.45) : 1 - smooth(0, 0.35, b);
        if (k > 0 && b < 0) p.glow(0, 0, 18, C[2], 0.4 * k);   // 蓄势时的暗晕；爆亮后不画圆光（读成孤立圆），只照地面
        if (b >= 0) groundGlow(p, CAST_GY, 18, 3.5, C[5], 0.7 * (1 - smooth(0.02, 0.4, b)));
      }
      if (isStart) { const k = smooth(0.12, 0.16, t) * (1 - smooth(0.2, 0.45, t)); if (k > 0) p.glow(0, 0, [8, 10, 13][el], C[5], GK * k); }
      ps.draw(p, "back");
    },
    draw(p) {
      if (core && isHit) {
        // 1) 四芒星：0–0.05 s 白，之后暗星（原作 glow_star_add → glow_star_ab）
        // 节奏（§0.1）：接触即定帧爆亮（0–0.05 s 全白、略大）→ 冷却成浅蓝（0.05–0.1 s）→ 暗星余韵慢慢缩淡
        const hot = t < 0.05 || (el >= 1 && t >= 0.1 && t < 0.13) ? 2 : t < (el >= 1 ? 0.17 : 0.1) ? 1 : 0, dark = hot === 0;   // E1 / E2 二连爆亮（多一拍）
        const fade = smooth(0.2, 0.25 + 0.4 * DL, t);
        const SLd = SL.map((v, i) => v * (i < 2 ? 1.5 : 1.25));   // 暗星比白星大（原作 glow_star_ab 1.14 × 1.3）
        if (fade < 1) star(p, 0, 0, hot === 2 ? SL.map((v) => v * 1.12) : dark ? SLd : SL, dark ? 1 - fade * 0.45 : 1, dark, hot);
        // 2) 白色锯齿尖刺（原作 cici：白 → 蓝 → 深蓝，0.3–0.4 s）
        for (const th of thorns) {
          const u = t - th.d;
          if (u <= 0) continue;
          const k = ease.outQuart(clamp(u / 0.06)), f = smooth(0.12, 0.12 + 0.2 * DL, u);
          if (f < 1) thorn(p, th.a, th.len * k * (1 - f * 0.3), th.w * (1 - f * 0.5), u, th.s);
        }
        // 3) 字符碎块（E0 一块，E1 / E2 三四块）：白热落下 → 落地弹一次 → 躺着冷却成蓝再熄灭（余烬慢灭，§0.2）
        for (const c of chunks) {
          if (t < c.d) continue;
          const cl = c.rest > 0 ? c.rest / c.cool : 0;
          if (cl >= 1) continue;
          const ci = cl < 0.55 ? 6 : cl < 0.8 ? 5 : 4;
          if (cl > 0.8 && ((Math.round(t * 30) + c.g) % 3 === 0)) continue;   // 熄灭前闪两下
          glyph(p, c.g, Math.round(c.x) - 1, Math.round(c.y) - (GLY[c.g].length - 1), el >= 2 && c.g % 3 === 1 && cl < 0.55 ? ACC : C[ci]);
        }
        // 3b) S2：实心字符带（四分之三圈椭圆、不闭合、原地写出不外扩，用户 11-04），白 → 灰蓝 → 深蓝后溶掉；E2 镂空透紫
        if (isS2 && mv !== "s2_exec") {
          const u = t - 0.02, k = ease.outCubic(clamp(u / 0.08)), f = smooth(0.3 * DL + 0.1, 0.55 * DL + 0.2, u);
          if (u > 0 && f < 1) glyphBand(p, 0, 2, ring.r, ring.r * 0.42, ring.a0, ring.a0 + ring.span, 3.2, C[u < 0.2 ? 6 : 4], el >= 2 ? ACC : C[1], k, f, 3);
        }
        // 3c) 处决 / 终结技：斜立的实心符文条（原作 fuwen）从脚下往上写出，条身白、字符镂空，停一会儿转暗溶掉
        for (const pl of pillars) {
          const u = t - pl.d;
          if (u <= 0) continue;
          const k = ease.outCubic(clamp(u / 0.15)), f = smooth(0.35 * DL + 0.15, 0.6 * DL + 0.3, u), H = pl.h * 5 * k;
          const col = C[u < 0.3 ? 6 : 4], cut = el >= 2 ? ACC : C[1], sx = Math.sin(pl.tilt), cy = Math.cos(pl.tilt);
          for (let j = 0; j < H; j++) for (let q = -2; q <= 2; q++) {
            if (noise2(pl.x + j * 0.4, q + u * 12, 33) < f * 2 - 1) continue;
            const hw = j > H - 3 ? 1 : 2;   // 梢头收窄
            if (Math.abs(q) > hw) continue;
            const r = q === 0 && j > 1 && j < H - 3 && BAND[1][(j + pl.g0) % BAND[0].length] === "#" && BAND[0][(j + pl.g0) % BAND[0].length] === "#";   // 只在条心一列镂空、稀疏（满格镂空读成碎点，§0.4）
            p.px(Math.round(pl.x + sx * j + cy * q), Math.round(GY - cy * j + sx * q), r ? cut : col);
          }
        }
        // 4) S1 E1+：一条直的实心字符带从逻各斯那侧穿过目标（原作 hitloop 的横向白色字符线；弯成弧会读成月牙，§12.1）
        if (isS1) {   // 三档都有，粗细 / 长度按档
          const u = t - band.d;
          if (u > 0 && u < 0.5 * DL + 0.2) {
            const k = ease.outExpo(clamp(u / 0.08)), f = smooth(0.25 * DL + 0.1, 0.5 * DL + 0.2, u), x0 = Math.round(-24 * TS), x1 = Math.round(6 * TS), xe = x0 + (x1 - x0) * k;
            for (let x = x0; x <= xe; x++) {
              const v = (x - x0) / (x1 - x0), hw = v < 0.15 ? 1 : el >= 1 ? 2 : 1, ci = (x - x0 + 40) % BAND[0].length;
              for (let q = -hw; q <= hw - 1; q++) {
                if (f > 0 && noise2(x * 0.4, q + u * 10, 7) < f * 2 - 1) continue;
                const cut = q === 0 && hw === 2 && BAND[0][ci] === "#" && BAND[1][ci] === "#";
                p.px(x, band.a * 6 - 3 + q, cut ? (el >= 2 ? ACC : C[2]) : v < 0.3 ? C[6] : C[7]);
              }
            }
          }
        }
        // 5) E2：深蓝墨羽从命中处甩开（原作 logos_cb）
        for (const f of feathers) {
          const u = t - f.d;
          if (u <= 0) continue;
          const k = ease.outCubic(clamp(u / 0.1)), fd = smooth(0.2, 0.25 + 0.4 * DL, u);
          if (fd < 1) feather(p, f, k, fd);
        }
      }
      if (core && isBolt) {
        // 墨尾：深色宽尾（近黑）→ 中段深蓝，中间一条蓝色细芯线，弹头白色菱形笔尖；S3（原作 skill3_trail：粗墨蛇 + 蓝色碎字符斑）更长更粗
        const BL = isS3 ? 44 : 30, BW = isS3 ? 5.5 : 2.6;
        for (let x = -BL; x <= 0; x++) {
          const v = (x + BL) / BL, w = 0.5 + v * BW + noise(x * 0.4 + t * 40, 3) * (isS3 ? 1.1 : 0.6);
          for (let y = -w; y <= w; y += 0.5) {
            if (v < 0.35 && noise2(x * 0.5 + t * 30, y, 5) < 0.1 - v) continue;   // 尾梢散成墨絮
            let ci = Math.abs(y) > w - 0.6 ? 2 : v > 0.6 ? 1 : 0;
            if (isS3 && v > 0.2 && noise2(x * 0.7 - t * 50, y * 0.9, 13) > 0.62) ci = noise2(x, y, 4) > 0 ? 5 : 4;   // 墨身里的蓝色碎字符斑
            p.px(x, y, C[ci]);
          }
          if (v > 0.45) p.px(x, Math.round(noise(x * 0.3 + t * 20, 9) * 0.6), C[v > 0.85 ? 5 : 3]);   // 芯线（只在前半段亮）
        }
        const HK = isS3 ? 1.6 : 1;
        for (const [dx, dy, c] of [[0, 0, 7], [1, 0, 7], [2, 0, 7], [3, 0, 6], [-1, 0, 7], [0, -1, 7], [0, 1, 7], [1, -1, 6], [1, 1, 6], [-2, 0, 6], [-1, -1, 5], [-1, 1, 5], [4, 0, 5]]) {
          p.px(Math.round(dx * HK), Math.round(dy * HK), C[c]);
          if (isS3) p.px(Math.round(dx * HK) + 1, Math.round(dy * HK), C[c]);
        }
      }
      if (core && mv === "s3_cast") {
        // 原作 skill3_start_02：暗色旋涡往笔尖收（0–0.45 s），收满后白色四芒星爆亮 + 碎字符；两手各一小圈字符环（start_01_L / R）
        // 蓄势：一团实心暗墨（近黑身、蓝色毛边）从大往笔尖收紧，越收越快；收满 → 四芒星定帧爆亮 → 字符碎块落下冷却（§0.1 / §0.4 三种元素）
        const u = t, b = u - 0.45;
        if (b < 0) {
          const k = ease.inCubic(clamp(u / 0.45)), R = 15 * (1 - 0.8 * k) + 2;
          for (let y = -Math.ceil(R); y <= Math.ceil(R); y++) for (let x = -Math.ceil(R); x <= Math.ceil(R); x++) {
            const a = Math.atan2(y, x), rr = R * (0.8 + 0.25 * noise(a * 2 + u * 9, 6)), d = Math.hypot(x, y * 1.35);
            if (d > rr) continue;
            p.px(x, y, C[d > rr - 1.2 ? 4 : d > rr * 0.55 ? 1 : 0]);
          }
        }
        if (b >= 0 && b < 0.4) { const hot = b < 0.05 ? 2 : b < 0.1 ? 1 : 0; star(p, 0, 0, [16, 13, 11, 9].map((v) => v * (hot === 2 ? 1.12 : 1) * 0.8), hot ? 1 : 1 - smooth(0.12, 0.4, b) * 0.5, !hot, hot); }
        for (const c of chunks) {
          if (t < c.d) continue;
          const cl = c.rest > 0 ? c.rest / c.cool : 0;
          if (cl >= 1 || (cl > 0.8 && ((Math.round(t * 30) + c.g) % 3 === 0))) continue;
          glyph(p, c.g, Math.round(c.x) - 1, Math.round(c.y) - (GLY[c.g].length - 1), C[cl < 0.25 ? 7 : cl < 0.55 ? 6 : cl < 0.8 ? 5 : 4]);
        }
      }
      if (core && isStart) {
        // 挥笔：外圈白弧 + 内侧暗弧（原作 dg：robrta_slash 白 + wisdel 暗），0.05 s 扫过、0.25 s 溶掉；收笔处四芒星
        const head = ease.outExpo(clamp(t / 0.07)), tail = smooth(0.1, 0.32, t);
        // 分档：E1 弧更粗更大；E2 质变成双笔（第二笔同向、在内侧错开、晚 0.04 s，外缘 E2 专属紫；反向两笔会合成头顶拱圈，§12.3）
        for (const [sg, dl, sx] of el >= 2 ? [[1, 0, 0], [-1, 0.04, 3]] : [[1, 0, 0]]) {
          const hd = ease.outExpo(clamp((t - dl) / 0.07)), tl = smooth(0.1 + dl, 0.32 + dl, t), R = swing.R * Math.sqrt(TS) * (sg < 0 ? 0.68 : 1);
          if (hd > 0.15) for (let s = tl; s <= hd; s += 0.008) {
            const a = swing.a0 + (sg < 0 ? 0.35 : 0) - swing.span * s, w = 1.8 * TW * Math.pow(Math.sin(Math.PI * clamp((s - tl) / Math.max(hd - tl, 0.01))), 1.5);   // 两头收尖
            for (let q = -w; q <= w; q += 0.5) {
              const r = R + q, inner = q < -w * 0.3;
              if (noise2(s * 30, q * 3, 2 + sx) < tl * 2 - 1) continue;
              p.px(swing.cx + sx + Math.cos(a) * r, swing.cy + sx + Math.sin(a) * r, inner ? C[1] : q > w - 0.7 ? (sg < 0 ? ACC : C[7]) : C[6]);
            }
          }
        }
        // E1+：胸前浮起一段白色字符带（原作 attack_start_02 字环）：碎字符沿前半圈椭圆排开、逐个写出，E2 每隔一个紫
        if (el >= 1 || mv === "s2_cast") {
          const u = t - 0.06, f = smooth(0.24, 0.42, u);
          if (u > 0 && f < 1) glyphBand(p, swing.cx, swing.cy - 2, 12, 4, Math.PI * 0.05, Math.PI * 0.95, 2.6, C[7], el >= 2 ? ACC : C[2], ease.outCubic(clamp(u / 0.12)), f, 5);   // 实心字符带、镂空字符（不再一颗颗散点，§0.4）
        }
        const u = t - 0.14;
        if (u > 0 && u < 0.42) star(p, 0, 0, [9, 7, 6, 5].map((v) => v * TS * (mv === "s2_cast" ? 1.35 : 1)), u < 0.05 ? 0.6 + 0.4 * ease.outCubic(u / 0.05) : 1 - smooth(0.15, 0.42, u) * 0.6, u > 0.1);
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
