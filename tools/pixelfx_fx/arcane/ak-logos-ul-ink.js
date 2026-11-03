// 逻各斯放开版（docs/242；开关 fx/px_unleashed），按原作 logos.ab 还原（Claude outputs/logos_ref/）的形状、颜色、层次、节奏做像素化：
//   普攻 attack_start / trail / hit_01，S1「提喻」= 原作 S2 skill2_hitloop_01/02（每跳）+ start / buff（锁定）。
// 原作语汇：白色四芒星（首帧白、随后转深蓝再转黑，留一颗暗星）、白色锯齿尖刺（cici）、白色碎字符（flipbook_214）、
//   深蓝黑墨羽（logos_cb，蓝色描边）、白头墨尾的弹体（logos_zidan + 深色拖尾 + 蓝色细芯线）、零星淡星点（star_114）。
// move：atk_start（原点 = 笔尖）/ atk_bolt（弹体循环，原点 = 弹头，正右 = 飞行方向）/ atk_hit（原点 = 命中点，正右 = 弹道方向）/
//       s1_tick（原点 = 目标身体中心，正右 = 从逻各斯指向目标）/ s1_lock（原点 = 目标脚底）。
// 分档（docs/91）：E0 原作基础形；E1「剜魂」加白色字符（碎字符 / 一段字符带）；E2「连缀」质变：深蓝墨羽从命中处甩开 + 暗星更大、紫色重点。
import { Particles, Lights, P, Rng, fit, hex, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";

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
    palette: ["#07081a", "#11143a", "#1f2560", "#33407f", "#5b67a8", "#9aa3d6", "#dfe3f7", "#ffffff"],   // 原作偏灰的蓝（cici #6472a6、lizi #56629b），不用高饱和
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
  const isS1 = mv.startsWith("s1"), isHit = mv === "atk_hit" || mv === "s1_tick";
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
  const S1R = isS1 ? 1.15 : 1;
  const SL = [Rg.range(17, 22), Rg.range(13, 17), Rg.range(10, 14), Rg.range(9, 12)].map((v) => v * [0.65, 0.72, 0.85][el] * S1R);   // 四臂：横长竖短（原作 star_06 / 164）
  const thorns = [];
  for (let i = 0, n = isS1 ? 2 : Rg.int(3, 4) + (el >= 1 ? 1 : 0); i < n; i++)   // S1 每跳尖刺少而短（原作 hitloop cici 4 根小刺），主形让给放射细光 + 碎字符
    thorns.push({ a: Rg.range(0, TAU), len: Rg.range(13, 21) * (isS1 ? 0.6 : 1), w: Rg.range(2.2, 3.2), d: Rg.range(0.02, 0.06), s: Rg.range(0, 1) });
  const shards = [];
  const nSh = isS1 ? [6, 10, 14][el] : [2, 7, 10][el];   // S1 每跳碎字符一直是主角（原作 hitloop zflizi 10–15 片）
  for (let i = 0; i < nSh; i++) {
    const a = isS1 ? Rg.range(0, TAU) : Rg.range(-1.3, 1.3) + (Rg.chance(0.3) ? Math.PI : 0), sp = Rg.range(35, 95);
    shards.push({ g: Rg.int(0, GLY.length - 1), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.7 - Rg.range(5, 25), d: Rg.range(0.02, 0.1), life: Rg.range(0.35, 0.7) * DL + 0.15 });
  }
  const feathers = [];
  if (el >= 2) for (let i = 0, n = Rg.int(2, 3); i < n; i++) {
    const a = (i % 2 ? Math.PI : 0) + Rg.range(-0.5, 0.5);
    feathers.push({ x: Rg.range(-4, 4), y: Rg.range(4, 10), a, bend: Rg.range(-0.6, 0.6), L: Rg.range(26, 36), arc: Rg.range(-7, 7), w: Rg.range(1.8, 2.6), barb: Rg.int(3, 5), barbEvery: Rg.int(5, 8), barbOff: Rg.int(0, 4), s: Rg.int(1, 999), d: Rg.range(0.03, 0.08) });
  }
  // S1：放射细光（原作 star_79_2 多芒星；角度 / 长短 / 先后都随机，不等距）+ 暗色旋涡残段（原作 flow_203 网格，两三段不闭合）
  const rays = [];
  if (isS1) for (let i = 0, n = Rg.int(6, 8); i < n; i++) rays.push({ a: Rg.range(0, TAU), L: Rg.range(10, 24), d: Rg.range(0, 0.03) });
  const swirl = [];
  if (isS1) for (let i = 0, n = Rg.int(2, 3); i < n; i++) swirl.push({ a0: Rg.range(0, TAU), sp: Rg.range(1.2, 2.0), r: Rg.range(11, 17), w: Rg.range(2, 3.5) });
  const band = { a: Rg.range(-0.35, 0.35), r: Rg.range(15, 19), d: 0.05 };   // E1+ S1：绕目标的一段字符带（原作 hit_03 / buff_03 字环的意思，半圈不闭合）

  // ---------------- 普攻起手：笔尖白弧 + 暗弧挥过，收笔处一颗四芒星（原作 attack_start_01 / 03）
  const swing = { a0: Rg.range(-1.1, -0.9), span: Rg.range(2.9, 3.2), R: Rg.range(13, 15), cx: -9, cy: 8 };   // 原作挥笔弧：从头右上绕到身体左下（笔尖在右手）
  // ---------------- 弹体：白色菱形笔尖 + 深色墨尾 + 蓝色细芯线（原作 logos_zidan + trail_ds / zs / xian）
  const BOLT_T = 0.25;

  let burst = false;
  return {
    update(dt) {
      t += dt;
      if (!burst && t >= 0.0 && isHit) {
        burst = true;
        if (deco) {
          lights.add(0, 0, [12, 16, 22][el] * S1R, C[6], GK * 1.6, 0.12 + 0.06 * el);
          for (let i = 0, n = Math.round(12 * PM); i < n; i++) {   // 墨点：顺弹道方向喷（原作 lizi_ab，黑 → 深蓝）
            const a = isS1 ? Rg.range(0, TAU) : Rg.range(-0.5, 0.5), sp = Rg.range(60, 200);
            ps.spawn(P.STREAK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp * 0.8, Rg.range(0.15, 0.35) * DL + 0.05, C[i % 3 ? 1 : 3], Rg.range(0.7, 1.1));
          }
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
        if (k > 0) p.glow(0, 0, [12, 16, 22][el] * S1R, C[5], GK * k);
        const dk = smooth(0.05, 0.12, t) * (1 - smooth(0.25, 0.25 + 0.4 * DL, t));
        if (dk > 0) p.glow(0, 0, [10, 14, 18][el] * S1R, C[0], 0.5 * dk);   // 暗晕（AB 黑）
      }
      for (const w of swirl) {   // 暗色旋涡残段（装饰层，AB 深蓝黑）
        const k = smooth(0.03, 0.12, t) * (1 - smooth(0.2, 0.2 + 0.35 * DL, t));
        if (k <= 0) continue;
        const rot = t * 3;
        for (let s2 = 0; s2 <= w.sp; s2 += 0.05) {
          const a = w.a0 + rot + s2, rr = w.r * (0.8 + 0.4 * smooth(0, 0.3, t)) + noise(a * 3, 4) * 2;
          p.disc(Math.cos(a) * rr, Math.sin(a) * rr * 0.6, w.w * Math.sin(Math.PI * s2 / w.sp), C[1], 0.45 * k);
        }
      }
      if (mv === "atk_bolt") p.glowLine(-26, 0, 0, 0, 6, C[3], 0.25), p.glow(0, 0, 7, C[6], 0.35);
      if (mv === "atk_start") { const k = smooth(0.12, 0.16, t) * (1 - smooth(0.2, 0.45, t)); if (k > 0) p.glow(0, 0, [8, 10, 13][el], C[5], GK * k); }
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
          const v = u / s.life, x = s.vx * u * (1 - v * 0.4), y = s.vy * u + 30 * u * u;
          if (v > 0.6 && ((Math.round(u * 40) + s.g) % 3 === 0)) continue;   // 消失前闪烁
          glyph(p, s.g, x - 1, y - 2, v < 0.5 ? C[7] : C[6]);
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
      if (core && mv === "atk_bolt") {
        // 墨尾：深色宽尾（近黑）→ 中段深蓝，中间一条蓝色细芯线，弹头白色菱形笔尖
        for (let x = -30; x <= 0; x++) {
          const v = (x + 30) / 30, w = 0.5 + v * 2.6 + noise(x * 0.4 + t * 40, 3) * 0.6;
          for (let y = -w; y <= w; y += 0.5) {
            if (v < 0.35 && noise2(x * 0.5 + t * 30, y, 5) < 0.1 - v) continue;   // 尾梢散成墨絮
            p.px(x, y, C[Math.abs(y) > w - 0.6 ? 2 : v > 0.6 ? 1 : 0]);
          }
          if (v > 0.45) p.px(x, Math.round(noise(x * 0.3 + t * 20, 9) * 0.6), C[v > 0.85 ? 5 : 3]);   // 芯线（只在前半段亮）
        }
        for (const [dx, dy, c] of [[0, 0, 7], [1, 0, 7], [2, 0, 7], [3, 0, 6], [-1, 0, 7], [0, -1, 7], [0, 1, 7], [1, -1, 6], [1, 1, 6], [-2, 0, 6], [-1, -1, 5], [-1, 1, 5], [4, 0, 5]]) p.px(dx, dy, C[c]);
      }
      if (core && mv === "atk_start") {
        // 挥笔：外圈白弧 + 内侧暗弧（原作 dg：robrta_slash 白 + wisdel 暗），0.05 s 扫过、0.25 s 溶掉；收笔处四芒星
        const head = ease.outExpo(clamp(t / 0.07)), tail = smooth(0.1, 0.32, t);
        if (head > 0.15) for (let s = tail; s <= head; s += 0.008) {
          const a = swing.a0 - swing.span * s, w = 2.0 * Math.sin(Math.PI * clamp((s - tail) / Math.max(head - tail, 0.01)));
          for (let q = -w; q <= w; q += 0.5) {
            const r = swing.R + q, inner = q < -w * 0.3;
            if (noise2(s * 30, q * 3, 2) < tail * 2 - 1) continue;
            p.px(swing.cx + Math.cos(a) * r, swing.cy + Math.sin(a) * r, C[inner ? 1 : q > w - 0.7 ? 7 : 6]);
          }
        }
        // E1+：胸前浮起一段白色字符带（原作 attack_start_02 字环）：碎字符沿前半圈椭圆排开、逐个写出，E2 每隔一个紫
        if (el >= 1) {
          const u = t - 0.06, f = smooth(0.24, 0.42, u);
          if (u > 0 && f < 1) for (let i = 0, n = 9; i < n; i++) {
            if (i / n > ease.outCubic(clamp(u / 0.12)) || noise2(i, u * 12, 9) < f * 2 - 1) continue;
            const a = Math.PI * 0.05 + (i / (n - 1)) * Math.PI * 0.9;
            glyph(p, (i * 4 + 1) % GLY.length, Math.round(swing.cx + Math.cos(a) * 13) - 1, Math.round(swing.cy - 2 + Math.sin(a) * 4), el >= 2 && i % 2 ? ACC : C[7]);
          }
        }
        const u = t - 0.14;
        if (u > 0 && u < 0.42) star(p, 0, 0, [9, 7, 6, 5].map((v) => v * [0.9, 1, 1.15][el]), u < 0.05 ? 0.6 + 0.4 * ease.outCubic(u / 0.05) : 1 - smooth(0.15, 0.42, u) * 0.6, u > 0.1);
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
