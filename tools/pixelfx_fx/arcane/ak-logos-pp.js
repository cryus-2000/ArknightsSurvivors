// 逻各斯「转平面」（docs/258，开关 fx/px_plane，照斯卡蒂 docs/246 / 星熊 254 / 流明 255 的做法）：pixelfx 画法按本作俯视斜角重画。
// 原作参照（本机 Claude outputs/logos_ref/，不进 git）：普攻 = 挥笔白弧 + 墨弧 → 身周字环 → 笔尖出手星芒 → 白头深蓝墨尾彗星 → 命中白色星芒 + 不规整长碎刺 → 地面墨环；
// 原作 S1「殁亡」（= 本作 S2）处决 = 交叉的咒文链 + 竖墨柱；原作 S3「延异视阈」起手 = 双手字环 → 笔尖蓄势 → 开域爆亮。
// 用户对逻各斯的三条（审过旧 pixelfx 与配方版）：咒文一律细字（1 像素笔画，不加粗）；弹头尖细（弹头在游戏里逐格画，这里不出）；咒域只画边 + 淡渐变（游戏里逐格画）。
// 一个文件按 part 出各件；每件分两层（layer）：
//   up 立起层 —— 离地的东西（星芒、碎刺、字环、咒文链、墨柱），进单位层按脚底 y 排序；
//   gd 贴地层 —— 地面上的墨环 / 墨迹，已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转（朝左靠水平翻转）。
// 色：本人 house.js OP.logos 7 阶 + 墨（最暗两阶，压底）；精二点缀紫 #a487ff（只点在主形上）。不用危险红、不用敌弹青、不用结晶暖金。同一招元素 ≤ 3。
import { fit, hex, clamp, smooth, ease, noise, noise2, TAU, Rng } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos plane",
  desc: "Logos's ink-and-glyph moves redrawn for a 3/4 top-down plane: standing white stars with jagged thorns, a pen arc dissolving into a ring of thin glyphs, crossed glyph chains over an ink pillar, and squashed ink rings on the ground.",
  tags: ["arcane", "ink", "glyph", "topdown", "logos", "one-shot"],
  size: [200, 200],
  origin: [100, 130],
  duration: 0.8,
  loop: false,
  fps: 15,   // 统一动画时钟（docs/246 §5）
  bg: "dark",
  options: { palette: OP.logos, part: "hit", layer: "up", el: 0, k: 1, SY: 0.72, seed: 3, dur: 0.8 },
};

const SEG = 1 / 15;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;
// 半透明不用 Bayer 抖动（2 倍下成网点）：按固定 2D 噪声成团消散
const D = (p, x, y, c, a = 1) => { if (a >= 0.999 || (a > 0 && noise2(Math.floor(x) * 0.45, Math.floor(y) * 0.45, 77) * 0.5 + 0.5 < a)) p.px(x, y, c); };

// 细字咒文（1 像素笔画，3×5；原作 zifu 的块状字改成细笔画，用户「咒文必须是细字」）
const GLYPHS = [
  ["111", "010", "010", "010", "011"],
  ["101", "111", "001", "001", "001"],
  ["110", "001", "010", "100", "011"],
  ["010", "111", "010", "010", "110"],
  ["100", "110", "101", "100", "111"],
  ["011", "100", "111", "001", "110"],
  ["101", "101", "010", "101", "101"],
  ["111", "100", "110", "100", "100"],
  ["010", "010", "111", "000", "101"],
  ["110", "101", "110", "100", "100"],
];
function glyph(p, x, y, gi, c, a = 1) {
  const G = GLYPHS[((gi % GLYPHS.length) + GLYPHS.length) % GLYPHS.length];
  for (let r = 0; r < 5; r++) for (let q = 0; q < 3; q++) if (G[r][q] === "1") D(p, Math.round(x) + q - 1, Math.round(y) + r - 2, c, a);
}

// 实心尖臂星芒：rays = [[dx, dy, L, 根部半宽]]；cool 0 → 1：白 → 本色 → 墨（原作首帧白、随后转深蓝再转黑）
function star(p, cx, cy, rays, k, cool, C, INK) {
  for (const [dx0, dy0, L, w0] of rays) {
    const n = Math.hypot(dx0, dy0), dx = dx0 / n, dy = dy0 / n, len = L * k;
    for (let s = 0; s <= len; s += 0.5) {
      const v = s / Math.max(len, 1), th = Math.max(0, w0 * k * Math.pow(1 - v, 1.4));
      for (let q = -th; q <= th; q += 0.5) {
        const edge = Math.abs(q) > th * 0.5;
        let c;
        if (cool < 0.2) c = v < 0.16 && !edge ? C[6] : edge ? C[3] : v < 0.5 ? C[5] : C[4];   // 白只给芯（11-05：怪群里偏白，再收一档）
        else if (cool < 0.55) c = v < 0.2 ? C[6] : edge ? C[2] : C[4];
        else c = v < 0.15 ? C[3] : edge ? INK[0] : INK[1];
        p.px(cx + dx * s - dy * q, cy + dy * s + dx * q, c);
      }
    }
  }
}

// 不规整长碎刺（原作 cici）：一根尖刺带 1–2 处折，根部宽、尖细；ret 0 → 1 从根往尖收（刺尖留到最后）
function thorn(p, cx, cy, a, L, w0, bend, ret, C, hot) {
  const ca = Math.cos(a), sa = Math.sin(a);
  for (let s = L * ret; s <= L; s += 0.5) {
    const v = s / L, kink = Math.sin(v * 5.2 + bend) * bend * 1.6 * v, th = w0 * (1 - v);
    for (let q = -th; q <= th; q += 0.5) {
      const x = cx + ca * s - sa * (q + kink), y = cy + sa * s + ca * (q + kink);
      const c = hot ? (v < 0.18 ? C[6] : Math.abs(q) > th * 0.5 ? C[3] : C[4]) : Math.abs(q) > th * 0.5 ? C[3] : v < 0.25 ? C[5] : C[4];
      p.px(x, y, c);
    }
  }
}

// 地面墨环（贴地，压扁）：半径 R 的细环，按噪声断续；hi 一段高光弧（本色亮阶）
function inkRing(p, R, SY, a, C, INK, seed, hi) {
  if (a <= 0) return;
  for (let an = 0; an < TAU; an += 0.5 / R) {
    const n = nz(an * 2.7, seed);
    if (n < 0.28) continue;
    const x = Math.cos(an) * R, y = Math.sin(an) * R * SY;
    const lit = hi && Math.sin(an) > 0.25 && n > 0.55;
    D(p, x, y, lit ? C[4] : n > 0.7 ? C[2] : INK[1], a);
  }
}

export function create(o) {
  const C = fit(o.palette, 7), E = +o.el, SY = +o.SY, up = o.layer === "up", gd = o.layer === "gd";
  const INK = [hex("#0b0d22"), hex("#161c3e")], AC = hex("#a487ff");
  const Rg = new Rng(+o.seed + 17 * E);
  const part = o.part, kk = +o.k || 1;
  let t = 0;
  const S = {};
  // ---------------------------------------------------------------- 预计算
  if (part === "hit" || part === "tick") {
    // 普攻命中（原作 hit_01）：白色四芒星芒（首帧白 → 深蓝 → 墨）+ 一圈不规整长碎刺（一根特长）；地上一圈墨环。
    // E1：斜向四芒成八芒 + 外圈多 3 根短刺 + 第 1 拍再爆亮；E2 质变：白热八芒星核更大、2 根深蓝墨羽从命中处甩开（羽梢紫）、两块细字碎块落下
    const tk = part === "tick";
    S.K = (tk ? 0.55 : 0.85) * [1, 1.15, 1.3][E] * kk;   // 11-05 第三轮：命中面积收一档（怪群里偏白）
    const n = tk ? 3 + E : [5, 8, 8][E];
    S.th = [];
    for (let i = 0; i < n; i++) {
      const a = (i / n) * TAU + Rg.range(-0.35, 0.35) - Math.PI / 2;
      const longOne = i === 1;
      S.th.push({ a, L: (longOne ? 30 : i >= 5 ? Rg.range(7, 11) : Rg.range(13, 21)) * S.K, w: (longOne ? 2.2 : i >= 5 ? 1.1 : 1.6) * Math.min(1.25, S.K), b: Rg.range(-0.6, 0.6) });
    }
    S.quills = E === 2 && !tk ? [Rg.range(-0.9, -0.4), Rg.range(2.5, 3.1)].map((a) => ({ a, L: Rg.range(18, 24) })) : [];
    S.chips = E === 2 ? [0, 1].map((i) => ({ x: Rg.range(-6, 6), y: -2, vx: (i ? 1 : -1) * Rg.range(18, 30), vy: -Rg.range(40, 60), gi: Rg.int(0, 9) })) : [];
  }
  if (part === "fire" || part === "s3open") {
    // 出手（原作 attack_start）：身前挥出白弧 + 墨弧（笔光）→ 化成一圈细字字环绕身；笔尖四芒星芒（E1 起八芒）。原点 = 脚底，朝右
    const big = part === "s3open";
    S.n = big ? 16 : [8, 11, 14][E];
    S.g = [];
    for (let i = 0; i < S.n; i++) S.g.push({ a: (i / S.n) * TAU + Rg.range(-0.1, 0.1), gi: Rg.int(0, 9), d: Rg.range(0, 0.08) });
    if (big) { S.g2 = []; for (let i = 0; i < 12; i++) S.g2.push({ a: (i / 12) * TAU + 0.2, gi: Rg.int(0, 9), d: 0.12 + Rg.range(0, 0.08) }); }
  }
  if (part === "exec") {
    // 殁亡处决（原作 hit_03）：两道交叉的细字咒文链从上斜插到敌人脚下 + 身后一道竖墨柱；E2 第三道竖链 + 紫字 + 白热八芒
    const H = E >= 2 ? 72 : 62;
    S.H = H;
    S.chains = [[-15, -H, 9, 3], [15, -H, -9, 3]];
    if (E >= 2) S.chains.push([0, -H - 8, 0, 4]);
    S.gl = S.chains.map(() => Array.from({ length: 14 }, () => Rg.int(0, 9)));
  }
  return {
    update(dt) {
      t += dt;
      for (const c of S.chips || []) if (t > 0.08) { c.vy += 300 * dt; c.x += c.vx * dt; c.y += c.vy * dt; if (c.y > 10 && c.vy > 0) { c.y = 10; c.vy *= -0.3; c.vx *= 0.5; } }
    },
    draw(p) {
      // ================================================================ hit / tick
      if (part === "hit" || part === "tick") {
        const K = S.K;
        if (up) {
          const beat2 = E >= 1 && t >= SEG && t < SEG * 2;   // E1 起第 1 拍星芒再撑一下（只撑大小，不再整团转白）
          const small = kk < 1 || part === "tick";
          const cool = Math.max(small ? 0.22 : 0, clamp((t - SEG) / 0.22));
          const sk = t < SEG ? 1 : beat2 ? 0.95 : 1 - 0.55 * smooth(SEG, 0.36, t);
          if (t < 0.36) {
            const rays = [[1, 0, 21, 2.2], [-1, 0, 21, 2.2], [0, -1, 16, 2], [0, 1, 13, 1.8]];
            if (E >= 1) rays.push([1, -1, 10, 1.4], [-1, -1, 10, 1.4], [1, 1, 8, 1.2], [-1, 1, 8, 1.2]);
            star(p, 0, 0, rays, K * sk, cool, C, INK);
            if (E === 2 && t < SEG && !small) for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(x, y, C[6]);
          }
          const ret = t < SEG ? 0 : smooth(SEG, 0.26, t);
          if (ret < 0.98) for (const s of S.th) thorn(p, 0, 0, s.a, s.L, s.w, s.b, ret, C, t < SEG && !small);
          for (const q of S.quills) {   // E2 墨羽：深蓝实心长锋甩开，蓝边，羽梢紫；0.45 秒干涸
            const u = ease.outCubic(clamp(t / 0.1)), dry = smooth(0.2, 0.45, t);
            if (dry >= 1) continue;
            const ca = Math.cos(q.a), sa = Math.sin(q.a);
            for (let s = 4 + q.L * 0.6 * dry; s <= q.L * u; s += 0.5) {
              const v = s / q.L, th = 2.4 * Math.sin(Math.PI * Math.min(1, v * 1.1)), cv = Math.sin(v * 3) * 2;
              for (let w = -th; w <= th; w += 0.5) {
                const c = v > 0.85 ? AC : Math.abs(w) > th - 0.6 ? C[2] : INK[w > 0 ? 0 : 1];
                D(p, ca * s - sa * (w + cv), sa * s + ca * (w + cv), c, 1 - dry * 0.6);
              }
            }
          }
          for (const c of S.chips) if (t > 0.06 && t < 0.6) glyph(p, c.x, c.y, c.gi, t < 0.2 ? C[6] : t < 0.4 ? C[4] : C[2], 1 - smooth(0.4, 0.6, t));
        }
        if (gd && part === "hit") {   // 地面墨环（原作 1.40 s）：E0 一圈、E1 两圈、E2 两圈 + 中心一摊墨
          const u = clamp((t - 0.06) / 0.62);
          if (t > 0.06 && u < 1) {
            const a = 1 - smooth(0.45, 1, u), gr = 1 + 0.25 * ease.outCubic(u);
            inkRing(p, 11 * K * gr, SY, a, C, INK, +o.seed, t < 0.25);
            if (E >= 1) {   // E1 新元素：外圈第二道墨环（亮弧、加一道内墨，1 倍下也看得出是两圈）
              inkRing(p, 17 * K * gr, SY, a, C, INK, +o.seed + 5, true);
              inkRing(p, 16 * K * gr, SY, a * 0.9, C, INK, +o.seed + 6, false);
            }
            if (E === 2) {
              const r0 = 5 * K;
              for (let y = -r0 * SY; y <= r0 * SY; y++) for (let x = -r0; x <= r0; x++) {
                const q = Math.hypot(x / r0, y / (r0 * SY)) * (0.8 + 0.4 * nz(Math.atan2(y, x) * 2, +o.seed + 9));
                if (q <= 1) D(p, x, y, q > 0.7 ? INK[1] : INK[0], a * 0.85);
              }
            }
          }
        }
      }
      // ================================================================ fire / s3open
      if ((part === "fire" || part === "s3open") && up) {
        const big = part === "s3open", RX = big ? 22 : 15, RY = big ? 8 : 5.5, CY = -19;
        // 笔光：身前挥出一道白弧（1 像素）+ 内侧墨弧（2 像素），0.1 秒扫出、0.2 秒散
        const sw = ease.outCubic(clamp(t / 0.1)), fade = 1 - smooth(0.12, 0.24, t);
        if (fade > 0) for (let an = -1.9; an <= -1.9 + 3.0 * sw; an += 0.03) {
          const x = 4 + Math.cos(an) * 15, y = CY + Math.sin(an) * 13;
          D(p, x, y, C[6], fade);
          D(p, x - Math.cos(an) * 1.5, y - Math.sin(an) * 1.5, INK[1], fade);
          D(p, x - Math.cos(an) * 2.5, y - Math.sin(an) * 2.5, C[2], fade * 0.8);
        }
        // 字环：细字绕身一圈，后半圈暗、前半圈亮，每拍沿环挪一点
        const ringT = (gl, r0, cy, life, rot) => {
          for (const g of gl) {
            const a0 = t - 0.08 - g.d;
            if (a0 <= 0 || a0 > life) continue;
            const an = g.a + Math.floor(t * 15) * rot, f = Math.sin(an), x = Math.cos(an) * r0, y = cy + f * RY;
            const al = 1 - smooth(life * 0.6, life, a0);
            const c = f < -0.2 ? C[2] : E === 2 && g.gi % 3 === 0 ? AC : a0 < SEG ? C[6] : C[5];
            glyph(p, x, y, g.gi, c, al * (f < -0.2 ? 0.75 : 1));
          }
        };
        ringT(S.g, RX, CY, big ? 0.6 : 0.36, 0.09);
        if (S.g2) ringT(S.g2, RX * 0.7, CY - 12, 0.5, -0.12);
        // 笔尖星芒（原作 0.50 s 出手星芒）：笔尖 = 身前 20、高 18
        const tx = 20, ty = -18;
        if (!big) {
          const st = t - 0.04;
          if (st > 0 && st < 0.22) {
            const rays = [[1, 0, 8, 1.3], [-1, 0, 6, 1.1], [0, -1, 7, 1.2], [0, 1, 6, 1.1]];
            if (E >= 1) rays.push([1, -1, 4, 0.9], [-1, -1, 4, 0.9], [1, 1, 4, 0.9], [-1, 1, 4, 0.9]);
            star(p, tx, ty, rays, (E === 2 ? 1.2 : 1) * (1 - 0.4 * smooth(0.05, 0.22, st)), clamp((st - SEG) / 0.15), C, INK);
          }
        } else {
          // 延异视阈起手：笔尖蓄势（小星慢慢长）→ 0.3 秒开域爆亮（大八芒）→ 0.6 秒收
          if (t < 0.3) star(p, tx, ty, [[1, 0, 6, 1.2], [-1, 0, 6, 1.2], [0, -1, 6, 1.2], [0, 1, 6, 1.2]], 0.5 + 1.2 * ease.inQuad(clamp(t / 0.3)), 0.25, C, INK);
          else if (t < 0.7) {
            const u = clamp((t - 0.3) / 0.4);
            star(p, tx, ty, [[1, 0, 34, 3], [-1, 0, 34, 3], [0, -1, 26, 2.8], [0, 1, 18, 2.4], [1, -1, 14, 2], [-1, -1, 14, 2], [1, 1, 11, 1.8], [-1, 1, 11, 1.8]], 1 - 0.5 * u, t < 0.3 + SEG ? 0 : clamp(u * 1.3), C, INK);
            if (t < 0.3 + 2 * SEG) for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(tx + x, ty + y, Math.abs(x) + Math.abs(y) <= 1 ? AC : C[6]);
          }
        }
      }
      // ================================================================ exec（殁亡处决）
      if (part === "exec") {
        const H = S.H;
        if (up) {
          // 竖墨柱：从地面冲起、往上散；墨芯 + 暗靛边，0.6 秒溶掉
          const rise = ease.outCubic(clamp(t / 0.15)), dis = smooth(0.3, 0.62, t);
          if (dis < 1)
            for (let y = 0; y <= H * rise; y++) {
              const v = y / H, w = (5 + 2 * nz(y * 0.3, +o.seed)) * (1 - 0.5 * v);
              for (let x = -w; x <= w; x++) {
                const c = Math.abs(x) > w - 1.2 ? (y < H * 0.5 && nz(y * 0.4, +o.seed + 1) > 0.45 ? C[3] : C[2]) : INK[nz(x * 0.7 + y * 0.2, +o.seed + 3) > 0.5 ? 0 : 1];
                D(p, x, -y, c, (1 - dis) * (1 - 0.6 * v));
              }
            }
          // 交叉咒文链：细字一个接一个从上往下写到脚下（0.12 秒写完），白 → 本色 → 暗
          S.chains.forEach(([x0, y0, x1, y1], ci) => {
            const L = Math.hypot(x1 - x0, y1 - y0), n = Math.floor(L / 6.5), wr = clamp(t / 0.12);
            for (let i = 0; i <= n * wr; i++) {
              const v = i / n, x = x0 + (x1 - x0) * v, y = y0 + (y1 - y0) * v;
              const a = 1 - smooth(0.4, 0.7, t + (1 - v) * 0.05);
              const c = t < SEG * 2 ? C[6] : E === 2 && i % 3 === ci % 3 ? AC : t < 0.3 ? C[5] : C[3];
              glyph(p, x, y, S.gl[ci][i % 14], c, a);
              if (i < n * wr - 1 && a > 0.3) D(p, x + (x1 - x0) / n * 0.5, y + (y1 - y0) / n * 0.5, C[3], a);   // 字间一点连笔
            }
          });
          // 胸口星芒（白 → 冷），E2 八芒更大
          if (t < 0.32) {
            const rays = [[1, 0, 14, 1.8], [-1, 0, 14, 1.8], [0, -1, 12, 1.6], [0, 1, 9, 1.4]];
            if (E >= 2) rays.push([1, -1, 8, 1.2], [-1, -1, 8, 1.2], [1, 1, 6, 1], [-1, 1, 6, 1]);
            star(p, 0, -12, rays, E >= 2 ? 1.3 : 1, clamp((t - SEG) / 0.2), C, INK);
          }
        }
        if (gd) {   // 地上：一摊不规则墨 + 一圈墨环（E2 外加一圈）
          const a = t < 0.05 ? 1 : 1 - smooth(0.35, 0.75, t);
          const r0 = 9 + 2 * E;
          for (let y = -r0 * SY; y <= r0 * SY; y++) for (let x = -r0; x <= r0; x++) {
            const q = Math.hypot(x / r0, y / (r0 * SY)) * (0.75 + 0.5 * nz(Math.atan2(y, x) * 2.4, +o.seed + 4));
            if (q <= 1) D(p, x, y, q > 0.8 ? C[1] : INK[0], a * 0.9);
          }
          inkRing(p, 17 + 3 * E, SY, a, C, INK, +o.seed + 2, true);
          if (E >= 2) inkRing(p, 24, SY, a * 0.8, C, INK, +o.seed + 6, false);
        }
      }
    },
  };
}
