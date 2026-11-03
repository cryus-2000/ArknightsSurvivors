// 逻各斯放开版：剩余一次性画面（docs/242 §0 + 分档硬标准，组长 B 11-04），同 ak-logos-ul-ink 的语汇：实心主形、定帧爆亮 → 冷却、字符碎块落地、地面受光、一招 ≤3 种元素、不画外扩环。
// move：
//   link     跳转线（S2 殁亡溢出伤害跳转 / 成长「转喻」锁定跳转）：一道实心墨笔从 0 写到 +L（原点 = 起点，正右 = 去向，L = 64 美术像素，游戏里按实际长度缩放），
//            白色笔头扫过、墨身带稀疏字符镂空、落笔处一颗小四芒星；E2 墨身外缘描紫
//   inkpop   消弹（S3 结束清弹 / 连携「消弹」每颗弹）：弹体大小的白点 → 一团实心暗墨收紧 → 一块字符碎块落地弹一次熄灭
//   seal     连携「消弹」中心 / 连携终结技「咒文扩散」：一枚实心暗墨菱形大咒印砸下（1.25 → 1 倍、白边定帧爆亮），咒印中间镂空字符，砸地照亮、两三块碎块落地
//   epitaph  成长「墓志铭」处决后爆开（size 1）/「墓志铭·连锁」击杀处小咒文（size 0.55）：地面一摊实心墨（不规则边，不是圆）爆亮，三根斜立实心符文条从墨里冲起、冷却溶掉
//   resonate 成长「转喻·共振」自身周围震荡：脚下一大摊不规则实心墨潮（满尺寸出现、不外扩），白边爆亮一拍后冷却成深蓝，墨潮里四五处字符镂空闪白
import { Particles, Lights, P, Rng, fit, hex, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos ink marks unleashed",
  desc: "Logos's remaining one-shot marks: a solid ink brush stroke that jumps between targets, an ink pop for cancelled bullets, a heavy diamond seal stamped into the ground, an epitaph burst of tilted rune bars, and a resonating ink tide.",
  tags: ["arcane", "ink", "glyph", "one-shot"],
  size: [220, 170],
  origin: [110, 95],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#07081a", ...OP.logos],   // house.js OP.logos
    accent: "#a487ff",
    move: "seal",
    elite: 2,
    size: 1,
    layer: "all",
    seed: 7,
  },
};

const GLY = [["#.#", "#.#", "...", ".#."], ["##", "##", "#.", "##"], ["#.#", "#.#", "###", "#.#"], ["##.", "#.#", "###"], [".#", "##", "#."], ["###", "#..", "###"], ["#", "##", "#", "#"], ["###", ".#.", ".#."], ["##", "#.", "##", ".#"]];
const BAND = ["#.#.##.#..###.#.#.##..#.##.#", "###.#..##.#.#.##..#.#.#..###", "#.#.##.#..#.#.#.##.##.#.#..#"];

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), ACC = hex(o.accent), el = clamp(Math.round(+o.elite), 0, 2), mv = o.move || "seal", SZ = +o.size || 1;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9 }), lights = new Lights();
  let t = 0, burst = false;

  function glyph(p, g, x, y, col) {
    const rows = GLY[g];
    for (let r = 0; r < rows.length; r++) for (let c = 0; c < rows[r].length; c++) if (rows[r][c] === "#") p.px(x + c, y + r, col);
  }
  function groundGlow(p, gy, rx, ry, col, a) {
    if (a <= 0.01) return;
    for (let y = -Math.ceil(ry); y <= Math.ceil(ry); y++) for (let x = -Math.ceil(rx); x <= Math.ceil(rx); x++) {
      const d = (x * x) / (rx * rx) + (y * y) / (ry * ry);
      if (d < 1) p.light(x, gy + y, col, a * 0.6 * (1 - d) * (1 - d));
    }
  }
  // 小四芒星（落笔 / 消弹的亮点）
  function star(p, x, y, L, hot) {
    for (const [dx, dy, len] of [[1, 0, L], [-1, 0, L * 0.8], [0, -1, L * 0.7], [0, 1, L * 0.6]]) {
      const W = Math.max(1, len * 0.2);
      for (let i = 0; i <= len; i++) {
        const v = i / Math.max(len, 1), hw = W * Math.pow(1 - v, 1.3);
        for (let q = -Math.ceil(hw); q <= Math.ceil(hw); q++) if (Math.abs(q) <= hw + 0.35) p.px(x + dx * i + dy * q, y + dy * i + dx * q, C[hot ? (Math.abs(q) > hw - 0.8 ? 6 : 7) : Math.abs(q) > hw - 0.8 ? 3 : 1]);
      }
    }
  }
  // 不规则实心墨（不是圆）：半径 R、扁 sy，边缘噪声起伏；rim 0..1 = 白边亮度；cuts = 镂空字符位置
  function blot(p, cx, cy, R, sy, seed, rim, fade, fillA = 1) {   // fillA < 1：墨体半透明（只留墨边实色）
    const B = Math.ceil(R * 1.25);
    for (let y = -Math.ceil(B * sy); y <= Math.ceil(B * sy); y++) for (let x = -B; x <= B; x++) {
      const a = Math.atan2(y / sy, x), d = Math.hypot(x, y / sy), rr = R * (0.82 + 0.3 * noise(a * 2.3 + seed, seed)) * (1 - fade);   // 收尾：整摊从边往里收干（不用噪声溶解，碎点脏）
      if (d > rr) continue;
      const edge = d > rr - (R < 9 ? 0.8 : 1.4);
      if (edge) p.px(cx + x, cy + y, C[rim > 0.6 ? 7 : rim > 0.25 ? 5 : 3]);
      else if (fillA < 1) p.blend(cx + x, cy + y, C[d > rr * 0.6 ? 1 : 0], fillA);
      else p.px(cx + x, cy + y, C[d > rr * 0.6 ? 1 : 0]);
    }
  }

  // ---- 字符碎块（同 ink：贴着原点小幅弹起、落地弹一次、躺着冷却）
  const chunks = [];
  const addChunks = (n, gy, d0, spread) => { for (let i = 0; i < n; i++) { const s = i % 2 ? 1 : -1; chunks.push({ g: Rg.int(0, GLY.length - 1), x: Rg.range(-3, 3) * spread, y: Rg.range(-4, 0), vx: s * Rg.range(12, 30) * spread, vy: -Rg.range(40, 80), d: d0 + Rg.range(0, 0.05), gy, rest: 0, cool: Rg.range(0.3, 0.45) }); } };
  if (mv === "inkpop") addChunks(1, 6, 0.08, 0.6);
  if (mv === "seal") addChunks(3, 16, 0.06, 1.4);
  if (mv === "epitaph") addChunks(SZ < 0.8 ? 1 : 3, 10 * SZ, 0.05, SZ);
  const bars = [];
  if (mv === "epitaph") { let x = -14 * SZ; for (let i = 0; i < 3; i++) { bars.push({ x: Math.round(x), h: Rg.int(6, 8) * SZ, tilt: (i % 2 ? 1 : -1) * Rg.range(0.25, 0.45), d: 0.04 + i * 0.03, g0: Rg.int(0, 20) }); x += Rg.range(11, 15) * SZ; } }
  const cuts = [];
  if (mv === "resonate") for (let i = 0; i < 5; i++) { const a = Rg.range(0, TAU), r = Rg.range(15, 60); cuts.push({ x: Math.round(Math.cos(a) * r), y: Math.round(Math.sin(a) * r * 0.45), g: Rg.int(0, GLY.length - 1), d: Rg.range(0.02, 0.2) }); }

  return {
    update(dt) {
      t += dt;
      if (!burst) {
        burst = true;
        if (deco) {
          if (mv === "seal") { lights.add(0, 0, 16, C[6], 0.7, 0.12); ps.spawn(P.SMOKE, -6, 10, -8, -10, 0.7, C[1], 6, 0.1); ps.spawn(P.SMOKE, 8, 10, 8, -8, 0.6, C[1], 5, 0.12); }
          if (mv === "epitaph") { lights.add(0, 0, 10 * SZ, C[6], 0.6, 0.1); ps.spawn(P.SMOKE, 0, 6 * SZ, 0, -10, 0.6, C[1], 5 * SZ, 0.08); }
          if (mv === "resonate") lights.add(0, 0, 28, C[5], 0.5, 0.12);
        }
      }
      for (const c of chunks) {
        if (t < c.d) continue;
        if (c.rest > 0) { c.rest += dt; continue; }
        c.vy += 520 * dt; c.x += c.vx * dt; c.y += c.vy * dt; c.vx -= c.vx * 1.5 * dt;
        if (c.y >= c.gy) { c.y = c.gy; if (c.vy > 70) { c.vy = -c.vy * 0.3; c.vx *= 0.5; } else { c.vy = 0; c.rest = dt; } }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (!deco) return;
      if (mv === "seal") groundGlow(p, 16, 40, 6, C[5], 0.8 * (1 - smooth(0.04, 0.4, t)));
      if (mv === "epitaph") groundGlow(p, 8 * SZ, 26 * SZ, 4 * SZ, C[5], 0.7 * (1 - smooth(0.04, 0.35, t)));
      if (mv === "resonate") groundGlow(p, 0, 80, 24, C[4], 0.5 * (1 - smooth(0.05, 0.45, t)));
      if (mv === "link") { const k = 1 - smooth(0.12, 0.35, t); if (k > 0) p.glowLine(0, 0, 64 * ease.outExpo(clamp(t / 0.08)), 0, 4, C[4], 0.3 * k); }
      ps.draw(p, "back");
    },
    draw(p) {
      if (core && mv === "link") {
        // 实心墨笔：0.08 s 从起点写到终点（笔头白、墨身近黑、蓝描边），停 0.1 s 后从起点往终点溶掉；落笔处小四芒星爆亮
        const L = 64, head = L * ease.outExpo(clamp(t / 0.08)), tail = L * smooth(0.16, 0.42, t);
        for (let x = Math.floor(tail); x <= head; x++) {
          const v = x / L, w = (1.2 + 1.6 * Math.sin(Math.PI * clamp(v * 0.9 + 0.05))) * [1, 1.25, 1.4][el], y0 = Math.sin(v * Math.PI) * -6;   // 微微上拱的一笔
          for (let q = -Math.ceil(w); q <= Math.ceil(w); q++) {
            if (Math.abs(q) > w + 0.3) continue;
            const ci = (x + 40) % BAND[0].length, cut = q === 0 && w > 2 && BAND[0][ci] === "#" && BAND[1][ci] === "#";
            const nearHead = head - x < 5 && t < 0.14, edge = Math.abs(q) > w - 0.8;
            p.px(x, Math.round(y0 + q), nearHead ? C[7] : cut ? C[3] : edge ? (el >= 2 ? ACC : C[4]) : C[q < 0 ? 0 : 1]);
          }
        }
        const u = t - 0.07;
        if (u > 0 && u < 0.35) star(p, L, 0, Math.round((6 + 2 * el) * (u < 0.05 ? 1.15 : 1 - smooth(0.1, 0.35, u) * 0.4)), u < 0.06);
      }
      if (core && mv === "inkpop") {
        // 0–0.04 s 白点（弹体被吃掉的一下）→ 一团实心暗墨从 7 收到 2 → 碎块
        if (t < 0.04) star(p, 0, 0, 4, true);
        else if (t < 0.3) { const k = smooth(0.04, 0.3, t); blot(p, 0, 0, 7 * (1 - 0.75 * k), 1, 4, k < 0.2 ? 0.8 : 0.3, 0); }
      }
      if (core && mv === "seal") {
        // 菱形大咒印：0–0.06 s 从 1.25 倍砸到 1 倍（白边爆亮），0.06–0.5 s 停住、边冷却成蓝，0.5 s 后从下往上溶掉
        const k = t < 0.06 ? 1.25 - 0.25 * ease.inCubic(t / 0.06) : 1, hot = t < 0.1, f = smooth(0.5, 0.85, t), S = 26 * k * (1 - f);   // 收尾整枚往里收
        if (f < 1) for (let y = -Math.ceil(S); y <= Math.ceil(S); y++) for (let x = -Math.ceil(S * 1.3); x <= Math.ceil(S * 1.3); x++) {
          const d = Math.abs(x) / 1.3 + Math.abs(y);
          if (d > S) continue;
          const edge = d > S - 2, inner = Math.abs(d - S * 0.55) < 1;   // 外缘 + 一道内框
          let c = edge ? C[hot ? 7 : 4] : inner ? C[hot ? 6 : 3] : C[d < S * 0.55 ? 0 : 1];
          if (d < S * 0.42 && (y === -2 || y === 2) && BAND[y < 0 ? 0 : 2][(x + 40) % BAND[0].length] === "#" && BAND[1][(x + 40) % BAND[0].length] === "#") c = C[hot ? 7 : 6];   // 中间两行横向字符纹（不拼成可读字母）
          if (d < 3) c = C[hot ? 7 : 5];   // 印心一点
          if (c === C[0] || c === C[1]) p.blend(x, y - 8, c, 0.4);   // 印身暗色填充 40% 半透明，砸下那一下不盖住怪（组长 B 11-04）；外缘 / 内框 / 字符纹实色
          else p.px(x, y - 8, c);
        }
      }
      if (core && mv === "epitaph") {
        // 地面墨摊爆亮 → 三根斜立实心符文条冲起（同 s2exec 的条）→ 冷却溶掉
        const f = smooth(0.4, 0.8, t);
        if (f < 1) blot(p, 0, 8 * SZ, 20 * SZ, 0.32, 11, t < 0.08 ? 1 : t < 0.18 ? 0.4 : 0, f);
        for (const b of bars) {
          const u = t - b.d;
          if (u <= 0) continue;
          const k = ease.outCubic(clamp(u / 0.12)), fb = smooth(0.3, 0.6, u), H = b.h * 5 * k;
          const col = C[u < 0.3 ? 6 : 4], sx = Math.sin(b.tilt), cy = Math.cos(b.tilt), w = SZ < 0.8 ? 1 : 2;
          for (let j = 0; j < H; j++) for (let q = -w; q <= w; q++) {
            if (fb > 0 && noise2(b.x + j * 0.4, q + u * 12, 33) < fb * 2 - 1) continue;
            const hw = j > H - 3 ? Math.max(0, w - 1) : w;
            if (Math.abs(q) > hw) continue;
            const ci = (j + b.g0) % BAND[0].length, cut = q === 0 && w === 2 && j > 1 && j < H - 3 && BAND[0][ci] === "#" && BAND[1][ci] === "#";
            p.px(Math.round(b.x + sx * j + cy * q), Math.round(8 * SZ - cy * j + sx * q), cut ? (el >= 2 ? ACC : C[1]) : col);
          }
        }
      }
      if (core && mv === "resonate") {
        // 满尺寸墨潮：0–0.06 s 白边爆亮，之后边冷却成蓝、0.45 s 后溶掉；墨潮里字符镂空依次闪白
        const f = smooth(0.45, 0.85, t);
        if (f < 1) blot(p, 0, 0, 72, 0.45, 23, t < 0.06 ? 1 : t < 0.15 ? 0.4 : 0, f, 0.4);   // 墨体 40% 半透明，不盖住圈内敌人 / 敌弹（组长 B 11-04）
        for (const c of cuts) {
          const u = t - c.d;
          if (u <= 0 || u > 0.35 || f > 0.3) continue;
          glyph(p, c.g, c.x - 1, c.y - 2, C[u < 0.08 ? 7 : u < 0.2 ? 6 : 4]);
        }
      }
      for (const c of chunks) {
        if (t < c.d) continue;
        const cl = c.rest > 0 ? c.rest / c.cool : 0;
        if (cl >= 1 || (cl > 0.8 && ((Math.round(t * 30) + c.g) % 3 === 0))) continue;
        glyph(p, c.g, Math.round(c.x) - 1, Math.round(c.y) - (GLY[c.g].length - 1), C[cl < 0.55 ? 6 : cl < 0.8 ? 5 : 4]);
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
