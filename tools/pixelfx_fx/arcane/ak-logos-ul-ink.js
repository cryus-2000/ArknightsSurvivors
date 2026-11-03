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
  desc: "Logos's attack and Synecdoche ticks after the original: a white four-point star that darkens to a navy star, jagged white thorns, flying white glyph shards and navy ink feathers.",
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
  const DL = [0.5, 0.75, 1][el] * (quick ? 0.5 : 1), GK = [0.25, 0.42, 0.6][el], PM = [0.6, 0.85, 1.15][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[2] }), lights = new Lights();
  const isS1 = mv.startsWith("s1"), isS2 = mv.startsWith("s2"), isHit = mv === "atk_hit" || mv === "s1_tick" || mv === "s2_hit" || mv === "s2_exec" || mv === "s3_hit" || mv === "ult_burst", isS3 = mv.startsWith("s3"), isBolt = mv === "atk_bolt" || mv === "s3_bolt", isStart = mv === "atk_start" || mv === "s2_cast";
  let t = 0;

  // ---- 四芒星：四臂长短不等（不规整），首帧白，之后臂身转深蓝、再转近黑；dark = 原作 AB 暗星
  function star(p, x, y, L, k, dark) {
    const arms = [[1, 0, L[0]], [-1, 0, L[1]], [0, -1, L[2]], [0, 1, L[3]]];
    for (const [dx, dy, len] of arms) {
      const n = Math.round(len * k);
      for (let i = 0; i <= n; i++) {
        const v = i / Math.max(n, 1);
        if (v > 0.55 && ((i * 7 + Math.round(len)) % 3 === 0) && k < 0.9) continue;   // 臂梢断续（原作贴图臂梢是虚的）
        const ci = dark ? clamp(Math.round(2 - v * 2.5 - (1 - k) * 2), 0, 2) : clamp(Math.round(7 - v * 3.5), 4, 7);
        p.px(x + dx * i, y + dy * i, C[ci]);
        if (i < n * 0.3) p.px(x + dx * i + dy, y + dy * i + dx, C[Math.max(0, ci - 1)]), p.px(x + dx * i - dy, y + dy * i - dx, C[Math.max(0, ci - 1)]);   // 根部加粗成菱形芯
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
  const SL = [Rg.range(17, 22), Rg.range(13, 17), Rg.range(10, 14), Rg.range(9, 12)].map((v) => v * [0.65, 0.72, 0.85][el] * S1R);   // 四臂：横长竖短（原作 star_06 / 164）
  const thorns = [];
  for (let i = 0, n = mv === "s2_exec" ? 0 : isS1 ? 2 : mv === "s3_hit" ? Rg.int(6, 7) : mv === "ult_burst" ? 8 : Rg.int(3, 4) + (el >= 1 ? 1 : 0); i < n; i++)   // S1 每跳尖刺少而短（原作 hitloop cici 4 根小刺），主形让给放射细光 + 碎字符
    thorns.push({ a: Rg.range(0, TAU), len: Rg.range(13, 21) * (isS1 ? 0.6 : 1), w: Rg.range(2.2, 3.2), d: Rg.range(0.02, 0.06), s: Rg.range(0, 1) });
  const shards = [];
  const nSh = mv === "ult_burst" ? 22 : mv === "s3_hit" ? 14 : mv === "s2_exec" ? 3 : isS1 ? [6, 10, 14][el] : [2, 7, 10][el];   // S1 每跳碎字符一直是主角（原作 hitloop zflizi 10–15 片）
  for (let i = 0; i < nSh; i++) {
    const a = isS1 ? Rg.range(0, TAU) : Rg.range(-1.3, 1.3) + (Rg.chance(0.3) ? Math.PI : 0), sp = Rg.range(35, 95);
    shards.push({ g: Rg.int(0, GLY.length - 1), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.7 - Rg.range(5, 25), d: Rg.range(0.02, 0.1), life: Rg.range(0.35, 0.7) * DL + 0.15 });
  }
  const feathers = [];
  if (el >= 2 && mv !== "s3_cast") for (let i = 0, n = Rg.int(2, 3); i < n; i++) {
    const a = (i % 2 ? Math.PI : 0) + Rg.range(-0.5, 0.5);
    feathers.push({ x: Rg.range(-4, 4), y: Rg.range(4, 10), a, bend: Rg.range(-0.6, 0.6), L: Rg.range(26, 36), arc: Rg.range(-7, 7), w: Rg.range(1.8, 2.6), barb: Rg.int(3, 5), barbEvery: Rg.int(5, 8), barbOff: Rg.int(0, 4), s: Rg.int(1, 999), d: Rg.range(0.03, 0.08) });
  }
  // S1：放射细光（原作 star_79_2 多芒星；角度 / 长短 / 先后都随机，不等距）+ 暗色旋涡残段（原作 flow_203 网格，两三段不闭合）
  const rays = [];
  const rayA = Rg.range(0, TAU);   // S1 放射细光偏向一侧成簇（不绕整圈，避开规整放射 §9.3）
  if (isS1) for (let i = 0, n = Rg.int(4, 5); i < n; i++) rays.push({ a: rayA + Rg.range(-1.5, 1.5), L: Rg.range(10, 24), d: Rg.range(0, 0.03) });
  const swirl = [];
  if (isS1 || mv === "s2_exec" || mv === "ult_burst") for (let i = 0, n = Rg.int(2, 3); i < n; i++) swirl.push({ a0: Rg.range(0, TAU), sp: Rg.range(1.2, 2.0), r: Rg.range(11, 17) * (mv === "ult_burst" ? 2 : 1), w: Rg.range(2, 3.5) * (mv === "ult_burst" ? 1.6 : 1) });
  const band = { a: Rg.range(-0.35, 0.35), r: Rg.range(15, 19), d: 0.05 };   // E1+ S1：绕目标的一段字符带（原作 hit_03 / buff_03 字环的意思，半圈不闭合）

  // S2「殁亡」= 原作 skill1：技能期间命中多一圈字符环（原作 hit_01 ring_01 (2)/(3)：logos_zifu 网格环，白 → 褐 → 深蓝，转成本作白 → 灰蓝 → 深蓝），
  // 处决 = 原作 hit_03：竖立的白色符文柱（fuwen，3–4 根，位置 / 高低 / 先后都随机）+ 往下落的白色细光（lizi）+ 暗旋涡（wenli），不出尖刺
  const ring = { a0: Rg.range(0, TAU), span: Rg.range(3.8, 4.6), r: mv === "s2_exec" ? 18 : 20 };   // 技能期间命中的字符环比普攻大一圈，一眼和普攻分开（§12.1）
  const pillars = [];
  if (mv === "s2_exec" || mv === "ult_burst") {
    let x = Rg.range(-15, -11) * (mv === "ult_burst" ? 2 : 1);
    for (let i = 0, n = mv === "ult_burst" ? 5 : el >= 2 ? 3 : 2; i < n; i++) { pillars.push({ x: Math.round(x), h: Rg.int(6, 9), tilt: (i % 2 ? 1 : -1) * Rg.range(0.25, 0.5), d: Rg.range(0.02, 0.1), g0: Rg.int(0, 8) }); x += Rg.range(9, 14) * (mv === "ult_burst" ? 1.4 : 1); }   // 原作 fuwen：斜立的长条符文，互相交叉
  }
  const falls = [];
  if (mv === "s2_exec") for (let i = 0; i < 6 + 2 * el; i++) falls.push({ x: Rg.range(-14, 14), y0: Rg.range(-34, -16), L: Rg.range(5, 12), sp: Rg.range(90, 170), d: Rg.range(0, 0.06) });
  // ---------------- 普攻起手：笔尖白弧 + 暗弧挥过，收笔处一颗四芒星（原作 attack_start_01 / 03）
  const swing = { a0: Rg.range(-1.3, -1.1), span: Rg.range(1.5, 1.8), R: Rg.range(14, 16), cx: -9, cy: 8 };   // 原作挥笔弧：从头右上往身前左下挥一道月牙（11-04 录像里整圈 3 rad 读成人物身边的白圈，§12.3，收到 1.5–1.8 rad）
  // ---------------- 弹体：白色菱形笔尖 + 深色墨尾 + 蓝色细芯线（原作 logos_zidan + trail_ds / zs / xian）
  const BOLT_T = 0.25;

  const castSwirl = [], castShards = [];
  if (mv === "s3_cast") {
    for (let i = 0; i < 3; i++) castSwirl.push({ a0: Rg.range(0, TAU), sp: Rg.range(1.4, 2.2), r: Rg.range(16, 24), w: Rg.range(1, 2) });
    for (let i = 0; i < 10; i++) { const a = Rg.range(0, TAU), sp = Rg.range(40, 90); castShards.push({ g: Rg.int(0, GLY.length - 1), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.7 - 15, d: Rg.range(0, 0.06), life: Rg.range(0.25, 0.4) }); }
  }
  let burst = false;
  return {
    update(dt) {
      t += dt;
      if (!burst && t >= 0.0 && isHit) {
        burst = true;
        if (deco) {
          lights.add(0, 0, 7 * S1R, C[6], GK * 1.2, 0.08);   // 命中点光：小而短、不随档变大（大圆光读成孤立圆，组长 B 11-04）
          for (let i = 0, n = Math.round([3, 5, 7][el] * (isS1 ? 1.3 : 1)); i < n; i++) {   // 淡星点（原作 xxlizi；改冷白，避开结晶暖金）
            const a = Rg.range(0, TAU), r = Rg.range(6, 22);
            ps.spawn(P.STAR, Math.cos(a) * r, Math.sin(a) * r * 0.7, Rg.range(-6, 6), Rg.range(-14, -2), Rg.range(0.3, 0.7) * DL + 0.1, i % 2 ? C[6] : C[7], Rg.range(0.8, 1.2), 0.15 + Rg.range(0, 0.15));
          }
          for (let i = 0; i < 2 + el; i++) ps.spawn(P.VAPOUR, Rg.range(-5, 5), Rg.range(-3, 3), Rg.range(-10, 10), Rg.range(-8, 0), Rg.range(0.4, 0.8) * DL + 0.1, C[1], Rg.range(4, 8));   // 暗墨雾（原作 glow_andi）
        }
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
      }
      for (const w of swirl) {   // 暗色旋涡残段（装饰层，AB 深蓝黑；半径固定只转不外扩，用户 11-04）
        const k = smooth(0.03, 0.12, t) * (1 - smooth(0.2, 0.2 + 0.35 * DL, t));
        if (k <= 0) continue;
        const rot = t * 3;
        for (let s2 = 0; s2 <= w.sp; s2 += 0.05) {
          const a = w.a0 + rot + s2, rr = w.r + noise(a * 3, 4) * 2;
          p.disc(Math.cos(a) * rr, Math.sin(a) * rr * 0.6, w.w * Math.sin(Math.PI * s2 / w.sp), C[1], 0.45 * k);
        }
      }
      for (const fl of falls) {   // 处决：往下落的白色细光（装饰层）
        const u = t - fl.d;
        if (u <= 0 || u > 0.3) continue;
        const y = fl.y0 + fl.sp * u, a = 1 - u / 0.3;
        for (let i = 0; i < fl.L; i++) p.dot(fl.x, y - i, C[i < 2 ? 7 : 5], a * (1 - i / fl.L));
      }
      if (isBolt) p.glowLine(isS3 ? -40 : -26, 0, 0, 0, isS3 ? 9 : 6, C[3], 0.25), p.glow(0, 0, isS3 ? 10 : 7, C[6], 0.35);
      if (mv === "s3_cast") { const b = t - 0.45, k = b < 0 ? 0.25 * clamp(t / 0.45) : 1 - smooth(0, 0.35, b); if (k > 0) p.glow(0, 0, 22, b < 0 ? C[2] : C[6], (b < 0 ? 0.4 : 0.6) * k); }
      if (isStart) { const k = smooth(0.12, 0.16, t) * (1 - smooth(0.2, 0.45, t)); if (k > 0) p.glow(0, 0, [8, 10, 13][el], C[5], GK * k); }
      ps.draw(p, "back");
    },
    draw(p) {
      if (core && isHit) {
        // 1) 四芒星：0–0.05 s 白，之后暗星（原作 glow_star_add → glow_star_ab）
        const grow = 0.65 + 0.35 * ease.outCubic(clamp(t / 0.05)), dark = t >= 0.08;   // 首帧就是白色十字星（不出孤立白点）
        const fade = smooth(0.2, 0.25 + 0.4 * DL, t);
        if (fade < 1) star(p, 0, 0, dark ? SL.map((v, i) => v * (i < 2 ? 1.7 : 1.35)) : SL, dark ? (1 + 0.1 * el) * (1 - fade * 0.4) : grow, dark);   // 暗星比白星大（原作 glow_star_ab 1.14 × 1.3）
        for (const r of rays) {
          const u = t - r.d, f = smooth(0.04, 0.16, u);
          if (u < 0 || f >= 1) continue;
          const L = r.L * ease.outCubic(clamp(u / 0.05)) * (1 - f * 0.3);
          for (let i = 3; i <= L; i++) if (!(i > L * 0.6 && i % 2)) p.px(Math.cos(r.a) * i, Math.sin(r.a) * i * 0.85, C[clamp(Math.round(7 - (i / L) * 3 - f * 3), 3, 7)]);
        }
        // 2) 白色锯齿尖刺（原作 cici：白 → 蓝 → 深蓝，0.3–0.4 s）
        for (const th of thorns) {
          const u = t - th.d;
          if (u <= 0) continue;
          const k = ease.outQuart(clamp(u / 0.06)), f = smooth(0.12, 0.12 + 0.2 * DL, u);
          if (f < 1) thorn(p, th.a, th.len * k * (1 - f * 0.3), th.w * (1 - f * 0.5), u, th.s);
        }
        // 3) E1+：白色碎字符飞散（原作 zflizi），E0 只有两三片
        for (const s of shards) {
          const u = t - s.d;
          if (u <= 0 || u > s.life) continue;
          const v = u / s.life, x = s.vx * 0.14, y = s.vy * 0.14 + 6 * v;   // 原地浮现、微沉后闪灭，不往外飞（§14.7）
          if (v > 0.6 && ((Math.round(u * 40) + s.g) % 3 === 0)) continue;   // 消失前闪烁
          glyph(p, s.g, x - 1, y - 2, v < 0.5 ? C[7] : C[6]);
        }
        // 3b) S2：字符环（四分之三圈，不闭合，原地写出不外扩：用户 11-04 否决往外扩散的光环），白 → 灰蓝 → 深蓝后碎掉
        if (isS2) {
          const u = t - 0.02, k = ease.outCubic(clamp(u / 0.08)), f = smooth(0.3 * DL + 0.1, 0.55 * DL + 0.2, u);
          if (u > 0 && f < 1) for (let i = 0, n = Math.round(ring.span * ring.r / 5); i < n; i++) {
            const a = ring.a0 + (i / n) * ring.span * k, ci = u < 0.08 ? 7 : u < 0.2 ? 5 : 3;
            if (noise2(i, u * 14, 21) < f * 2 - 1) continue;
            glyph(p, (i * 5 + 2) % GLY.length, Math.round(Math.cos(a) * ring.r) - 1, Math.round(Math.sin(a) * ring.r * 0.42) + 2, el >= 2 && i % 3 === 1 ? ACC : C[ci]);
          }
        }
        // 3c) 处决：符文柱从脚下往上写出，停一会儿转暗、碎散
        for (const pl of pillars) {
          const u = t - pl.d;
          if (u <= 0) continue;
          const k = ease.outCubic(clamp(u / 0.15)), f = smooth(0.35 * DL + 0.15, 0.6 * DL + 0.3, u), n = Math.ceil(pl.h * k);
          for (let j = 0; j < n; j++) {
            if (noise2(pl.x + j * 3, u * 12, 33) < f * 2 - 1) continue;
            const ci = u < 0.1 ? 7 : u < 0.3 ? 6 : 4;
            glyph(p, (pl.g0 + j * 4) % GLY.length, Math.round(pl.x + Math.sin(pl.tilt) * (j + 1) * 5) - 1, Math.round(10 - Math.cos(pl.tilt) * (j + 1) * 5), el >= 2 && j === n - 1 ? ACC : C[ci]);
          }
        }
        // 4) S1 E1+：绕目标半圈白色字符带（不闭合）
        if (isS1 && el >= 1) {
          const u = t - band.d;
          if (u > 0 && u < 0.5 * DL + 0.2) {
            const k = ease.outCubic(clamp(u / 0.1)), f = smooth(0.25 * DL + 0.1, 0.5 * DL + 0.2, u), span = 2.6 * k;
            const cols = BAND[0].length;
            for (let c = 0; c < cols; c++) {
              const a = band.a - span / 2 + (c / cols) * span;
              if (c / cols > k) break;
              for (let r = 0; r < 3; r++) if (BAND[r][c] === "#" && noise2(c, r + u * 10, 7) > f * 2 - 1)
                p.px(Math.cos(a) * (band.r + r) * 1.0, Math.sin(a) * (band.r + r) * 0.55 - 4, el >= 2 ? (r === 1 ? ACC : C[7]) : C[7]);
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
        const u = t;
        for (const w of castSwirl) {
          const k = clamp(u / 0.45), rr = w.r * (1 - 0.85 * k);
          if (k >= 1) continue;
          for (let s2 = 0; s2 <= w.sp; s2 += 0.06) {
            const a = w.a0 + u * 6 + s2, x = Math.cos(a) * rr, y = Math.sin(a) * rr * 0.7;
            p.px(x, y, C[s2 > w.sp - 0.2 ? 4 : 1]);
            if (w.w > 1.5) p.px(x + 0.5, y + 0.5, C[1]);
          }
        }
        for (const hd of [-1, 1]) {
          const k = smooth(0.05, 0.2, u) * (1 - smooth(0.45, 0.6, u));
          if (k <= 0) continue;
          for (let i = 0; i < 7; i++) {
            const a = (i / 7) * Math.PI * 2 * k + u * 3 * hd;
            glyph(p, (i * 3 + (hd > 0 ? 1 : 4)) % GLY.length, Math.round(-10 + hd * 4 + Math.cos(a) * 7) - 1, Math.round(10 + Math.sin(a) * 3) - 2, C[i % 3 ? 6 : 7]);
          }
        }
        const b = u - 0.45;
        if (b >= 0 && b < 0.4) star(p, 0, 0, [16, 13, 11, 9], b < 0.05 ? 0.6 + 0.4 * (b / 0.05) : 1 - smooth(0.12, 0.4, b) * 0.5, b > 0.1);
        if (b >= 0) for (const s3s of castShards) {
          const v = b - s3s.d;
          if (v <= 0 || v > s3s.life) continue;
          glyph(p, s3s.g, Math.round(s3s.vx * 0.25) - 1, Math.round(s3s.vy * 0.25 + 10 * v) - 2, v < s3s.life * 0.5 ? C[7] : C[5]);
        }
      }
      if (core && isStart) {
        // 挥笔：外圈白弧 + 内侧暗弧（原作 dg：robrta_slash 白 + wisdel 暗），0.05 s 扫过、0.25 s 溶掉；收笔处四芒星
        const head = ease.outExpo(clamp(t / 0.07)), tail = smooth(0.1, 0.32, t);
        if (head > 0.15) for (let s = tail; s <= head; s += 0.008) {
          const a = swing.a0 - swing.span * s, w = 1.8 * Math.pow(Math.sin(Math.PI * clamp((s - tail) / Math.max(head - tail, 0.01))), 1.5);   // 两头收尖成月牙
          for (let q = -w; q <= w; q += 0.5) {
            const r = swing.R + q, inner = q < -w * 0.3;
            if (noise2(s * 30, q * 3, 2) < tail * 2 - 1) continue;
            p.px(swing.cx + Math.cos(a) * r, swing.cy + Math.sin(a) * r, C[inner ? 1 : q > w - 0.7 ? 7 : 6]);
          }
        }
        // E1+：胸前浮起一段白色字符带（原作 attack_start_02 字环）：碎字符沿前半圈椭圆排开、逐个写出，E2 每隔一个紫
        if (el >= 1 || mv === "s2_cast") {
          const u = t - 0.06, f = smooth(0.24, 0.42, u);
          if (u > 0 && f < 1) for (let i = 0, n = 9; i < n; i++) {
            if (i / n > ease.outCubic(clamp(u / 0.12)) || noise2(i, u * 12, 9) < f * 2 - 1) continue;
            const a = Math.PI * 0.05 + (i / (n - 1)) * Math.PI * 0.9;
            glyph(p, (i * 4 + 1) % GLY.length, Math.round(swing.cx + Math.cos(a) * 13) - 1, Math.round(swing.cy - 2 + Math.sin(a) * 4), el >= 2 && i % 2 ? ACC : C[7]);
          }
        }
        const u = t - 0.14;
        if (u > 0 && u < 0.42) star(p, 0, 0, [9, 7, 6, 5].map((v) => v * [0.9, 1, 1.15][el] * (mv === "s2_cast" ? 1.35 : 1)), u < 0.05 ? 0.6 + 0.4 * ease.outCubic(u / 0.05) : 1 - smooth(0.15, 0.42, u) * 0.6, u > 0.1);
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
