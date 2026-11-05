// 艾雅法拉「转平面」（docs/259，开关 fx/px_plane，照斯卡蒂 docs/246 / 星熊 docs/254 / 流明 docs/255 的做法）：pixelfx 画法按本作俯视斜角重画。
// 一个文件按 part 出各件；每件分层（layer）：
//   up 立起层 —— 离地的东西（爆团、火舌、火柱、花瓣碎片、火星线、咏唱火缕），原点 = 地面点，进单位层按 y 排序；
//   gd 贴地层 —— 地面上的东西（焦痕边、裂缝、熔岩池边），已按 SY（= combat.GROUND_Y 0.72）压扁，画在地面层；
//   raw 旧做法对照 —— 同一形状不压扁（正俯视正圆），光晕另画进 light 层（烘焙时烤进颜色），游戏里旋转 + 小数缩放贴在最上层。
// 尺寸按目标大小直接生成（1 像素 = 1 美术像素 = 2 世界像素），游戏里只按 2 倍整数放大，不缩放、不旋转。
// 色：本人熔岩 7 阶（house.js OP.eyjafjalla）+ 一阶橙黄热芯 C[7]。暖红一律偏橙：主体用 C4 / C5，C3 只做外缘，危险红（DANGER 粉红）不用。
// 爆发主体（爆团、火柱）照原作体量：大、亮、实，持续短；持续的地面区域（熔岩池、熔池、喷发热圈）只画边 + 内侧淡渐变（α ≤ 0.14），不平涂。
// 白（C6）只给第 0 拍的热芯；之后热芯降到橙黄。同一招元素 ≤ 3（主形 / 贴地件 / 游戏里的 Noita 颗粒）。
import { fit, clamp, smooth, ease, noise, noise2, TAU, Rng, hex, Particles, Bits, P, B, FIRE_RAMP, Painter } from "../../core/index.js";
import { draw as fireballDraw } from "./fireball.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla plane",
  desc: "Eyjafjalla's lava and fire moves redrawn for a 3/4 top-down plane: solid standing fire masses, flame crowns, ignition pillars, petal-shaped embers and spark lines, plus squashed scorch edges, cracks and lava-pool rims.",
  tags: ["fire", "explosion", "topdown", "eyjafjalla", "one-shot"],
  size: [300, 280],
  origin: [150, 196],
  duration: 1.2,
  loop: false,
  fps: 15,   // 统一动画时钟（docs/246 §5）
  bg: "dark",
  options: { palette: OP.eyjafjalla, part: "boom", layer: "up", el: 0, R: 30, SY: 0.72, seed: 3, dur: 1.2, k: 1 },
};

const HOTY_HEX = "#ffaa45";   // 橙黄热芯（白只给第 0 拍）；create 里转成 C[7]
const SEG = 1 / 15;
const nz = (x, sd) => noise(x, sd) * 0.5 + 0.5;   // 0..1
const nz2 = (x, y, sd) => noise2(x * 0.45, y * 0.45, sd) * 0.5 + 0.5;
// 半透明不用 Bayer 抖动（2 倍下成网点）：a < 1 时按固定噪声成团消散
const D = (p, x, y, c, a = 1) => { if (a >= 0.999 || (a > 0 && nz2(Math.floor(x), Math.floor(y) * 1.3, 77) < a)) p.px(x, y, c); };

// ---------------------------------------------------------------- 实心火团（爆团主体）
// lobes: [{x, y, r, d 延迟, life, rise}]，坐标 / 半径按 R 归一；热度 = 离心距离 + 年龄 + 左上受光；第 0 拍白芯
function mass(p, lobes, R, t, C, sd, sy = 1, hot0 = true) {
  for (let i = 0; i < lobes.length; i++) {
    const L = lobes[i], age = t - L.d;
    if (age < 0) continue;
    const u = clamp(age / L.life);
    if (u >= 1) continue;
    const grow = ease.outCubic(clamp(age / 0.07));
    const r = L.r * R * (0.5 + 0.5 * grow) * (1 - 0.3 * u * u);
    const cx = L.x * R, cy = L.y * R - (L.rise || 0) * R * age;
    const first = hot0 && age < SEG;
    for (let y = -r - 2; y <= r + 2; y++)
      for (let x = -r - 2; x <= r + 2; x++) {
        const an = Math.atan2(y, x), rr = r * (0.8 + 0.32 * nz(an * 2.2 + i * 3.1 + t * 2, sd + i));
        const q = Math.hypot(x, y / 0.92) / rr;
        if (q > 1) continue;
        const lit = (-x - y) / (r * 2.4);   // 左上受光
        let hv = (1 - q) * 1.25 - u * 1.45 + lit * 0.5;
        if (first) hv += 0.45;
        let c;
        if (hv > 1.3 && first) c = C[6];
        else if (hv > 1.05) c = C[7];
        else if (hv > 0.78) c = C[7];
        else if (hv > 0.5) c = C[5];
        else if (hv > 0.22) c = C[4];
        else if (hv > -0.05) c = C[3];
        else if (hv > -0.35) c = C[2];
        else c = C[1];
        // 冷下来的外层成团散掉（不留整圈）
        const fade = u < 0.62 ? 1 : 1 - (u - 0.62) / 0.38;
        D(p, cx + x, (cy + y) * sy, c, q < 0.55 ? Math.min(1, fade + 0.25) : fade);
      }
  }
}

// 花瓣状暗红碎片（原作 S3 hit 的五瓣碎片）：五瓣、暗红身 + 受光一侧亮一阶，往外飞、转、受重力
function petal(p, x, y, s, rot, C, a) {
  for (let yy = -s - 1; yy <= s + 1; yy++)
    for (let xx = -s - 1; xx <= s + 1; xx++) {
      const an = Math.atan2(yy, xx) - rot, rr = s * (0.5 + 0.5 * Math.abs(Math.cos(an * 2.5)));
      const q = Math.hypot(xx, yy) / rr;
      if (q > 1) continue;
      const c = q > 0.72 && xx + yy < 0 ? C[3] : q < 0.35 ? C[1] : C[2];
      D(p, x + xx, y + yy, c, a);
    }
}

// 火星线：1 像素亮线，头白 / 橙黄、尾橙
function spark(p, x0, y0, dx, dy, L, C, hot) {
  const n = Math.max(1, Math.round(L));
  for (let s = 0; s <= n; s++) {
    const v = s / n;
    p.px(x0 - dx * s, y0 - dy * s, v < 0.2 ? (hot ? C[6] : C[7]) : v < 0.6 ? C[5] : C[4]);
  }
}

// 火舌（立起）：下鼓上尖的一团火苗，顶上往一侧卷、按拍摇摆；h 高、w 最宽处半宽。芯（下半中间）橙黄，外层橙，尖端暗一阶
function tongue(p, x, y, h, w, t, sd, C, hotk) {
  for (let s = 0; s <= h; s += 0.5) {
    const v = s / h;
    const prof = v < 0.3 ? 0.65 + 0.35 * (v / 0.3) : Math.pow((1 - v) / 0.7, 0.85);
    const ww = w * prof * (0.85 + 0.2 * nz(s * 0.35 + t * 9, sd));
    const sw = (nz(v * 1.6 + t * 5, sd + 3) - 0.5) * w * 1.4 * v * v;
    for (let q = -ww; q <= ww; q += 0.5) {
      const e = Math.abs(q) / Math.max(ww, 0.5);
      let c = e < 0.45 && v < 0.55 ? C[7] : e < 0.8 ? C[5] : C[4];
      if (v > 0.78) c = e < 0.5 ? C[4] : C[3];
      if (hotk > 0.3 && e < 0.4 && v < 0.4) c = C[6];
      p.px(x + q + sw, y - s, c);
    }
  }
}

// 贴地边弧（焦痕 / 池边）：半径 R(+噪声) 上 segs 段，w 像素厚：外圈亮（hot 时橙）→ 内圈两格深色内边（颜色阶代替透明度）
function edge(p, R, SY, segs, w, a, C, sd, t, hot, wob = 0.1) {
  for (const sg of segs)
    for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.4 / R) {
      const e = 1 - Math.abs(an - sg.c) / sg.half, n = nz(an * 3.1 + t * 1.2, sd + 7);
      const k = a * smooth(0, 0.3, e);
      if (k <= 0.05) continue;
      const rr = R * (1 - wob + 2 * wob * nz(an * 1.7, sd + 2));
      for (let q = 0; q < w; q++) {
        const r = rr - q;
        const ci = q === 0 ? (hot ? (n > 0.5 ? 5 : 4) : n > 0.62 ? 4 : 3) : q === 1 ? (hot ? 3 : 2) : 1;
        D(p, Math.cos(an) * r, Math.sin(an) * r * SY, C[ci], k * (q === 0 ? 1 : 0.9));
      }
    }
}

// 内侧淡渐变（真半透明 blend，α ≤ amax）：只贴着边往里 band 像素，中心不铺
function innerFade(p, R, SY, band, amax, c, sd) {
  for (let y = -R * SY; y <= R * SY; y += 1)
    for (let x = -R; x <= R; x += 1) {
      const q = Math.hypot(x / R, y / (R * SY));
      if (q > 1 || q < 1 - band / R) continue;
      const u = (q - (1 - band / R)) / (band / R);
      p.blend(x, y, c, amax * u * u * (0.6 + 0.4 * nz(Math.atan2(y, x) * 2.3, sd + 5)));
    }
}

function segsOf(Rg, n, cover) {
  const out = [], a0 = Rg.range(0, TAU);
  for (let i = 0; i < n; i++) {
    const w = TAU / n, c = a0 + (i + 0.5 + Rg.range(-0.2, 0.2)) * w;
    out.push({ c, half: w * cover * Rg.range(0.75, 1.15) * 0.5 });
  }
  return out;
}

// 贴地裂缝：从中心往外不规整分叉（先橙黄后冷成暗红、断成一节节）；cr = [{a, L, fork}]
function cracks(p, cr, SY, t, C, sd, tHot, tCool) {
  for (const k of cr) {
    let x = Math.cos(k.a) * k.r0, y = Math.sin(k.a) * k.r0, a = k.a;
    for (let s = 0; s < k.L; s += 1) {
      a += (nz(s * 0.5, sd + k.i) - 0.5) * 0.5;
      x += Math.cos(a); y += Math.sin(a);
      const v = s / k.L, heat = 1 - smooth(tHot, tCool, t - v * 0.12);
      if (heat <= 0 && (s + k.i) % 4 === 3) continue;   // 冷了断成一节节
      const c = heat > 0.7 ? C[7] : heat > 0.35 ? C[5] : heat > 0.05 ? C[3] : C[1];
      p.px(x, y * SY, c);
      if (k.fork && Math.abs(s - k.L * 0.5) < 0.6) k.fx = [x, y, a + k.fork];
    }
    if (k.fx) {
      let [fx, fy, fa] = k.fx;
      for (let s = 0; s < k.L * 0.45; s++) {
        fa += (nz(s * 0.6, sd + 9 + k.i) - 0.5) * 0.5; fx += Math.cos(fa); fy += Math.sin(fa);
        const heat = 1 - smooth(tHot, tCool, t - 0.06);
        p.px(fx, fy * SY, heat > 0.5 ? C[5] : heat > 0.05 ? C[3] : C[1]);
      }
    }
  }
}

// ---------------------------------------------------------------- pixelfx 粒子做法（11-05 用户「火山和熔岩的感觉要做出来，火球也是，参考 pixelfx 的做法」）
// 爆团 / 火柱 / 喷发 = 库里 explosions、flame-pillar 那套粒子：火团（P.FIRE）沿火焰色阶冷却、火星（P.SPARK）、余烬（P.EMBER）、
// 带受光面的熔岩块（Bits CHUNK）；火球 = 库里 fire/fireball 原样（按 5 个平面角转着生成）。色阶换成她的熔岩色（暖红偏橙、白只在最热一阶）；
// 不加烟（库里的紫灰烟在本作地面上发脏），火团冷到最暗一阶就成团散掉。半透明一律按固定噪声成团消散（不用 Bayer 网点）。
const RAMP9 = ["#fff0e0", "#ffe3a8", "#ffc46b", "#ffaa45", "#ff8a3d", "#f6561a", "#d2330f", "#8f1d0d", "#4a110a"];
const LAVA_ROCK = ["#1a0705", "#4a110a", "#8f1d0d", "#f6561a", "#ffaa45"];   // 熔岩块：暗壳 → 受光面透橙
const BALL_PAL = ["#4a110a", "#8f1d0d", "#d2330f", "#f6561a", "#ff8a3d", "#ffaa45", "#ffc46b", "#ffe3a8", "#fff0e0"];

function patchPainter() {
  if (Painter.prototype._eyPatched) return;
  Painter.prototype._eyPatched = true;
  Painter.prototype.put = function (sx, sy, c, a = 1) {
    if (!c) return;
    a *= this.fade;
    if (a < 1 && (a <= 0 || nz2(sx, sy * 1.3, 91) >= a)) return;
    const x = sx - this.ox, y = sy - this.oy;
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    this.C[y * this.w + x] = c;
  };
}

// 熔岩块的岩壳（火球头上盖几块暗壳，壳缝透橙）：r 半径，ph 翻滚相位
function crust(p, x0, y0, r, ph, C, ang = 0) {
  // 熔岩块：不规则的暗岩外形 + 几道透橙黄的裂缝 + 迎着飞行方向那一面烧红；岩块随相位慢慢翻滚
  const dx = Math.cos(ang), dy = Math.sin(ang);
  for (let y = -r - 1; y <= r + 1; y++)
    for (let x = -r - 1; x <= r + 1; x++) {
      const d = Math.hypot(x, y), an = Math.atan2(y, x);
      const rr = r * (0.72 + 0.32 * nz(an * 1.3 + ph * 0.6, 43));
      if (d > rr) continue;
      const u = x * Math.cos(ph) - y * Math.sin(ph), v = x * Math.sin(ph) + y * Math.cos(ph);
      const n = nz2(u * 1.1 / Math.max(1, r * 0.3) + 7, v * 1.1 / Math.max(1, r * 0.3) + 3, 41) * 3;
      const fr = Math.abs(n - Math.round(n));
      const face = d > 0 ? (x * dx + y * dy) / d : 0;
      let c = d > rr - 1 ? C[0] : x + y < -rr * 0.5 ? C[2] : C[1];
      if (face > 0.55 && d > rr * 0.55) c = d > rr - 1 ? C[3] : C[4];   // 迎风面烧红
      if (fr < 0.07 && d < rr - 0.5) c = fr < 0.035 ? C[7] : C[5];      // 裂缝
      p.px(x0 + x, y0 + y, c);
    }
}

export function create(o) {
  patchPainter();
  FIRE_RAMP.splice(0, FIRE_RAMP.length, ...RAMP9.map(hex));
  const C = fit(o.palette, 7).concat(fit([HOTY_HEX], 1)), E = +o.el, R = +o.R, part = o.part, ly = o.layer;
  const raw = ly === "raw", up = ly === "up" || raw, gd = ly === "gd" || raw, SY = raw ? 1 : +o.SY;
  const Rg = new Rng(+o.seed + 17 * E + 3 * R);
  const sd = +o.seed;
  let t = 0;
  const S = {};
  // ---------------------------------------------------------------- 粒子
  const ps = new Particles({ rng: new Rng(+o.seed * 7 + E * 13 + R), ground: () => 0, sparks: [C[6], C[7], C[5], C[4]] });
  const bits = new Bits({ ground: () => 0 });
  const fireBurst = (n, cx, cy, rad, spd, life, size, rise = 40, delay = 0) => {
    for (let i = 0; i < n; i++) {
      const a = Rg.range(0, TAU), d = Rg.range(0, rad), sp = Rg.range(0.35, 1) * spd;
      ps.spawn(P.FIRE, cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.8, Math.cos(a) * sp, Math.sin(a) * sp * 0.7 - rise, Rg.range(0.7, 1.15) * life, 0, Rg.range(0.75, 1.15) * size, delay + Rg.range(0, 0.03));
    }
  };
  const sparkBurst = (n, cx, cy, spd, life, upk = 0.35, delay = 0) => {
    for (let i = 0; i < n; i++) {
      const a = Rg.range(0, TAU), sp = Rg.range(0.45, 1) * spd;
      ps.spawn(P.SPARK, cx, cy, Math.cos(a) * sp, Math.sin(a) * sp * 0.75 - spd * upk, Rg.range(0.5, 1) * life, 0, 1, delay);
    }
  };
  const emberBurst = (n, cx, cy, spd, life) => {
    for (let i = 0; i < n; i++) {
      const a = Rg.range(0, TAU), sp = Rg.range(0.3, 1) * spd;
      ps.spawn(P.EMBER, cx + Math.cos(a) * 2, cy, Math.cos(a) * sp, Math.sin(a) * sp * 0.6 - spd * 0.6, Rg.range(0.6, 1) * life, C[5], Rg.chance(0.4) ? 2 : 1);
    }
  };
  const chunkBurst = (n, cx, cy, spd, s0, s1, life, upk = 1.2) => {
    for (let i = 0; i < n; i++) {
      const a = Rg.range(0, TAU), sp = Rg.range(0.5, 1) * spd;
      bits.add({ kind: B.CHUNK, x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.5 - spd * upk * Rg.range(0.7, 1.1), g: 1, drag: 0.3, bounce: 0.25, life: Rg.range(0.75, 1) * life, a: Rg.range(0, TAU), va: Rg.range(-14, 14), s: Rg.range(s0, s1), ramp: LAVA_ROCK });
    }
  };
  // 火柱：一串往上冲的火团（库里 flame-pillar 的做法），x 中心、w 半宽、h 高
  const column = (x, w, h, life, delay, n) => {
    for (let i = 0; i < n; i++) {
      const v = i / n;
      ps.spawn(P.FIRE, x + Rg.range(-w, w) * 0.6, -Rg.range(0, h * 0.15), Rg.range(-8, 8), -h * Rg.range(3.2, 5.2) * (0.6 + 0.6 * v), life * Rg.range(0.75, 1.1), 0, w * Rg.range(0.8, 1.25) * (1 - 0.3 * v), delay + v * 0.12);
    }
  };
  // ---------------------------------------------------------------- 预计算
  const flyers = (n, spd0, spd1, up0, up1, life) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      const a = Rg.range(-Math.PI, Math.PI);
      const sp = Rg.range(spd0, spd1) * R;
      out.push({ a, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.72 - Rg.range(up0, up1) * R, s: Rg.range(0.75, 1.25), rot: Rg.range(0, TAU), w: Rg.range(-9, 9), d: Rg.range(0, 0.04), life: life * Rg.range(0.8, 1.15) });
    }
    return out;
  };
  const crk = (n, r0, L0, L1) => {
    const out = [], a0 = Rg.range(0, TAU);
    for (let i = 0; i < n; i++) out.push({ i, a: a0 + (i + Rg.range(-0.3, 0.3)) * TAU / n, r0: r0 * Rg.range(0.7, 1.2), L: Rg.range(L0, L1), fork: Rg.range(0, 1) < 0.5 ? Rg.range(-0.9, 0.9) : 0 });
    return out;
  };
  const Y = -R * 0.45;   // 爆心离地高度
  if (part === "boom" || part === "splash") {
    // 普攻熔岩弹爆炸（原作 attack_01_hit：一团火 + 暗红碎块 + 火星线）。
    // E0 一团火；E1 形状差：晚一拍两侧再炸开两团（二段爆）+ 甩出熔岩块；E2 质变（三重咏唱每落一发）：团顶冲起三股小火柱 + 熔岩块更多
    const sm = part === "splash", k = sm ? 0.75 : 1;
    S.flash = [0, Y * k, R * 0.38 * k];
    fireBurst(sm ? 7 : 12, 0, Y * k, R * 0.35 * k, R * 4.2 * k, 0.36, R * 0.3 * k, 30);
    fireBurst(4, 0, Y * k, R * 0.15, R * 1.5, 0.26, R * 0.36 * k, 10);
    if (E >= 1 && !sm) { fireBurst(5, -R * 0.55, Y * 0.8, R * 0.2, R * 2.5, 0.3, R * 0.24, 30, 1 / 15); fireBurst(5, R * 0.55, Y * 0.85, R * 0.2, R * 2.5, 0.3, R * 0.24, 30, 1 / 15); }
    if (E >= 2 && !sm) for (const x of [-0.45, 0, 0.45]) column(x * R, R * 0.13, R * 0.9, 0.3, 0.04, 6);
    sparkBurst(sm ? 6 : 10 + 4 * E, 0, Y * k, R * 9 * k, 0.28);
    if (E >= 1 || sm) chunkBurst(sm ? 2 : 3 + E, 0, Y * k * 0.6, R * 4.5 * k, 0.9, 1.6, 0.55, 1.3);
    S.segs = segsOf(Rg, sm ? 3 : 4, 0.7);
    S.cr = crk(E >= 1 && !sm ? 5 : 3, R * 0.25, R * 0.45, R * 0.7);
  }
  if (part === "s1boom") {
    // S1 二重咏唱强化弹：更大的火团 + 第二拍再炸一次（二重）+ 一圈立起的火苗；E1 第二次更大 + 熔岩块；E2 火苗圈变成一圈火柱
    S.flash = [0, Y, R * 0.36];
    fireBurst(16, 0, Y, R * 0.35, R * 4, 0.38, R * 0.28, 30);
    fireBurst(9 + 3 * E, 0, Y * 1.3, R * 0.3, R * (3 + 0.6 * E), 0.34, R * (0.24 + 0.03 * E), 50, 2 / 15);
    const nT = 7 + E;
    for (let i = 0; i < nT; i++) {
      const a = i * TAU / nT + Rg.range(-0.15, 0.15);
      column(Math.cos(a) * R * 0.8, R * (E >= 2 ? 0.12 : 0.09), R * (E >= 2 ? 0.75 : 0.5), 0.3, 0.03 + Rg.range(0, 0.05), E >= 2 ? 5 : 3);
    }
    S.ring = Array.from({ length: nT }, (_, i) => i * TAU / nT);
    sparkBurst(12 + 4 * E, 0, Y, R * 8, 0.3);
    if (E >= 1) chunkBurst(3 + E, 0, Y * 0.6, R * 4, 1, 1.8, 0.6);
    S.segs = segsOf(Rg, 5, 0.72);
    S.embers = Array.from({ length: 10 + 3 * E }, () => { const a = Rg.range(0, TAU), r = R * Rg.range(0.55, 1.0); return { x: Math.cos(a) * r, y: Math.sin(a) * r, d: Rg.range(0.1, 0.5) }; });
    S.cr = E >= 2 ? crk(6, R * 0.2, R * 0.55, R * 0.85) : [];
  }
  if (part === "ignite") {
    // S2 点燃（精一解锁）：命中处猛地立起一根火柱（库里 flame-pillar），柱脚一团火；E2 质变：三根（中柱 + 两侧晚一拍）+ 柱脚一圈火苗
    S.flash = [0, -R * 0.3, R * 0.3];
    fireBurst(10, 0, -R * 0.25, R * 0.4, R * 3.5, 0.34, R * 0.3, 20);
    column(0, R * 0.24, R * 1.9, 0.45, 0, 34);
    if (E >= 2) {
      column(-R * 0.6, R * 0.16, R * 1.25, 0.38, 1 / 15, 18);
      column(R * 0.62, R * 0.16, R * 1.35, 0.38, 1 / 15, 18);
      for (let i = 0; i < 8; i++) column(Math.cos(i * TAU / 8) * R * 0.8, R * 0.08, R * 0.45, 0.28, 0.08, 3);
    }
    sparkBurst(14 + 6 * E, 0, -R * 0.6, R * 7, 0.34, 0.9);
    emberBurst(6 + 2 * E, 0, -R * 0.8, R * 3, 0.7);
    S.segs = segsOf(Rg, 5, 0.7);
    S.embers = Array.from({ length: 12 + 4 * E }, () => { const a = Rg.range(0, TAU), r = R * Rg.range(0.4, 1.0); return { x: Math.cos(a) * r, y: Math.sin(a) * r, d: Rg.range(0.1, 0.55) }; });
  }
  if (part === "s3boom") {
    // S3 火山落点（用户 11-05：实心大爆团，暖红到亮橙，花瓣状暗红碎片 + 火星线，体量不小于现版熔岩）：库里 big-explosion 的火团量 + 一束往上冲的火 + 熔岩块
    S.flash = [0, Y, R * 0.5];
    fireBurst(34, 0, Y, R * 0.5, R * 4.4, 0.48, R * 0.36, 35);
    fireBurst(10, 0, Y, R * 0.25, R * 1.4, 0.4, R * 0.46, 15);
    fireBurst(8, 0, Y * 0.3, R * 0.6, R * 3.5, 0.4, R * 0.3, 10, 1 / 15);
    column(0, R * 0.24, R * 1.5, 0.4, 0.03, 16);
    sparkBurst(26, 0, Y, R * 9.5, 0.32);
    emberBurst(8, 0, Y, R * 3, 0.7);
    chunkBurst(6, 0, Y * 0.5, R * 4.2, 1.2, 2.2, 0.7, 1.4);
    S.petals = flyers(9, 1.8, 2.8, 1.4, 2.2, 0.55).map((f) => ({ ...f, s: f.s * Math.max(3, R * 0.11) }));
    S.segs = segsOf(Rg, 5, 0.74);
    S.cr = crk(7, R * 0.2, R * 0.6, R * 0.95);
  }
  if (part === "lava") {
    // 持续熔岩池 / 三重咏唱熔池（循环）：只画不规整的边 + 两格深色内边 + 内侧淡渐变 + 几点慢慢明灭的热泡；o.k < 1 = 细一号（熔池）
    S.segs = segsOf(Rg, +o.k < 1 ? 4 : 5, +o.k < 1 ? 0.8 : 0.86);
    S.bub = Array.from({ length: +o.k < 1 ? 4 : 6 }, () => { const a = Rg.range(0, TAU), r = R * Rg.range(0.25, 0.8); return { x: Math.cos(a) * r, y: Math.sin(a) * r, ph: Rg.range(0, 1) }; });
  }
  if (part === "lavaup") {
    // 熔岩池上方（循环，立起）：池里鼓起熔岩泡，鼓到顶「啵」地破开，冒一小簇火苗和一两颗火星——熔岩感靠这个，不靠铺满地面
    S.bub = Array.from({ length: +o.k < 1 ? 3 : 5 }, (_, i) => { const a = Rg.range(0, TAU), r = R * Rg.range(0.15, 0.75); return { x: Math.cos(a) * r, y: Math.sin(a) * r * SY, ph: (i + Rg.range(0, 0.6)) / (+o.k < 1 ? 3 : 5), s: Rg.range(1.5, 2.5) }; });
  }
  if (part === "s1cast") {
    // S1 二重咏唱起手：两缕火从脚下绕身旋上杖头（二重）；E1 加粗 + 杖头一圈火星；E2 三缕 + 地上一圈咏唱火环边
    S.strands = E >= 2 ? [0, 2.1, 4.2] : [0, Math.PI];
    S.TH = [2, 2.5, 2.5][E];
    S.segs = segsOf(Rg, 6, 0.6);
    S.sparks = E >= 1 ? flyers(6 + 2 * E, 2.5, 4, 0.5, 1.2, 0.2) : [];
    fireBurst(4 + 2 * E, 0, -62, 3, 18, 0.28, 3 + 0.5 * E, 25, 0.26);
  }
  if (part === "s3cast") {
    // S3 火山起手：身后地里冲起一股熔岩喷柱（火柱 + 上抛的熔岩块）+ 脚下裂开一圈裂缝
    S.flash = [-R * 0.15, -R * 0.3, R * 0.3];
    column(-R * 0.15, R * 0.24, R * 2.3, 0.52, 0, 38);
    fireBurst(10, -R * 0.15, -R * 0.2, R * 0.35, R * 3, 0.34, R * 0.28, 15);
    chunkBurst(7, -R * 0.15, -R * 0.4, R * 2.2, 1.2, 2.2, 0.8, 3.2);
    sparkBurst(14, -R * 0.15, -R * 0.6, R * 6, 0.35, 1.0);
    S.cr = crk(8, R * 0.25, R * 0.55, R * 0.8);
    S.segs = segsOf(Rg, 5, 0.66);
  }
  if (part === "aura") {
    S.segs = segsOf(Rg, 3, 0.5);
  }
  // 第 0–1 拍爆心闪光（实心、白芯小、外圈橙黄；第 1 拍缩一圈变橙）：粒子火团第 0 拍还小，靠它给出「砰」的一下
  const flash = (p) => {
    if (!S.flash || t >= 2 * SEG) return;
    const [fx, fy, fr] = S.flash, k = t < SEG ? 1 : 0.7;
    const r = fr * k;
    for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) {
      const d = Math.hypot(x, y) / r;
      if (d > 1) continue;
      p.px(fx + x, fy + y, t < SEG ? (d < 0.4 ? C[6] : d < 0.8 ? C[7] : C[5]) : (d < 0.5 ? C[7] : C[4]));
    }
  };
  const sim = (p) => { ps.draw(p, "back"); bits.draw(p); ps.draw(p, "front"); flash(p); };
  return {
    update(dt) {
      t += dt;
      for (let i = 0; i < 4; i++) { ps.update(dt / 4); bits.update(dt / 4); }
    },
    draw(p) {
      // ================================================================ ball（火球 / 熔岩块，循环；o.ang 飞行方向）：库里 fire/fireball，熔岩块再盖一层岩壳
      if (part === "ball") {
        const tx = p.tx, ty = p.ty, ang = (+o.ang || 0) * Math.PI / 180;
        p.place(tx, ty, false, ang);
        fireballDraw(p, t, { palette: BALL_PAL, radius: R, speed: 120 * (+o.k || 1), seed: sd });
        p.place(tx, ty, false, 0);
        if (+o.crust) crust(p, 0, 0, Math.max(2, Math.round(R * 0.9)), t * 3, C, ang);   // 岩壳在不旋转的格子上画（旋转写像素会漏格成网纹）
        return;
      }
      // ================================================================ boom / splash（普攻爆炸、抛射熔岩落地）
      if (part === "boom" || part === "splash") {
        const sm = part === "splash";
        if (up) sim(p);
        if (gd) {
          const a = t < 0.05 ? 1 : 1 - smooth(0.12, 0.47, t);
          if (a > 0) {
            const Rs = R * (sm ? 0.75 : 0.95);
            innerFade(p, Rs, SY, Math.min(10, Rs * 0.4), 0.14 * a, C[2], sd);
            edge(p, Rs, SY, S.segs, 2, a, C, sd, t, t < 2 * SEG);
            if (!sm) cracks(p, S.cr, SY, t, C, sd, 0.08, 0.4);
          }
        }
        if (raw && t < 0.3) p.glow(0, Y, R * 1.3, C[5], 0.55 * (1 - t / 0.3));
      }
      // ================================================================ s1boom（S1 强化弹爆炸）
      if (part === "s1boom") {
        if (up) sim(p);
        if (gd) {
          const a = t < 0.05 ? 1 : 1 - smooth(0.25, 0.75, t);
          if (a > 0) {
            innerFade(p, R, SY, 12, 0.14 * a, C[2], sd);
            edge(p, R, SY, S.segs, 3, a, C, sd, t, t < 3 * SEG);
            for (const m of S.embers) {   // 焦边上几点余烬，慢慢熄
              const b = t - m.d; if (b <= 0 || b > 0.4) continue;
              p.px(m.x, m.y * SY, b < 0.15 ? C[5] : b < 0.3 ? C[4] : C[2]);
            }
            if (S.cr.length) cracks(p, S.cr, SY, t, C, sd, 0.12, 0.6);
          }
        }
        if (raw && t < 0.35) p.glow(0, Y, R * 1.4, C[5], 0.6 * (1 - t / 0.35));
      }
      // ================================================================ ignite（S2 点燃火柱）
      if (part === "ignite") {
        if (up) sim(p);
        if (gd) {
          const a = t < 0.05 ? 1 : 1 - smooth(0.3, 0.9, t);
          if (a > 0) {
            innerFade(p, R, SY, 12, 0.14 * a, C[2], sd);
            edge(p, R, SY, S.segs, 3, a, C, sd, t, t < 3 * SEG);
            for (const m of S.embers) { const b = t - m.d; if (b <= 0 || b > 0.45) continue; p.px(m.x, m.y * SY, b < 0.15 ? C[5] : b < 0.3 ? C[4] : C[2]); }
          }
        }
        if (raw && t < 0.4) p.glow(0, -R * 0.8, R * 1.5, C[5], 0.6 * (1 - t / 0.4));
      }
      // ================================================================ s3boom（S3 火山落点：实心大爆团 + 花瓣碎片 + 火星线）
      if (part === "s3boom") {
        if (up) {
          sim(p);
          for (const f of S.petals) {
            const a = t - f.d; if (a <= 0 || a > f.life) continue;
            const x = f.vx * a, y = Math.min(R * 0.1, f.vy * a + 0.5 * 7 * R * a * a) - R * 0.5;
            petal(p, x, y, f.s * (a < 0.08 ? 0.7 + a * 3.5 : 1), f.rot + f.w * a, C, 1 - smooth(f.life * 0.6, f.life, a));
          }
        }
        if (gd) {
          const a = t < 0.05 ? 1 : 1 - smooth(0.3, 0.8, t);
          if (a > 0) {
            innerFade(p, R, SY, 14, 0.14 * a, C[2], sd);
            edge(p, R, SY, S.segs, 3, a, C, sd, t, t < 3 * SEG);
            cracks(p, S.cr, SY, t, C, sd, 0.1, 0.6);
          }
        }
        if (raw && t < 0.45) p.glow(0, Y, R * 1.6, C[5], 0.7 * (1 - t / 0.45));
      }
      // ================================================================ lava（持续熔岩池 / 熔池，循环）
      if (part === "lava" && gd) {
        const ph = (t / +o.dur) * TAU;
        innerFade(p, R, SY, Math.min(14, R * 0.45), 0.14, C[2], sd);
        edge(p, R, SY, S.segs, +o.k < 1 ? 2 : 3, 1, C, sd, Math.sin(ph) * 0.6, false, 0.12);
        for (const b of S.bub) {   // 热泡：慢慢亮起再熄（一圈 1.2 秒）
          const v = (Math.sin(ph + b.ph * TAU) + 1) * 0.5;
          if (v < 0.45) continue;
          p.px(b.x, b.y * SY, v > 0.85 ? C[5] : v > 0.65 ? C[4] : C[3]);
          if (v > 0.8) p.px(b.x + 1, b.y * SY, C[4]);
        }
        if (raw) p.glow(0, 0, R, C[4], 0.35);
      }
      // ================================================================ lavaup（熔岩泡鼓起、破开、冒火苗，循环）
      if (part === "lavaup") {
        const D0 = +o.dur;
        for (const b of S.bub) {
          const u = ((t / D0 + b.ph) % 1);
          if (u < 0.45) {   // 鼓起：一个越来越大的亮橙泡，顶上一点高光
            const r = b.s * (0.4 + u / 0.45);
            for (let y = -r; y <= 0; y++) for (let x = -r; x <= r; x++) if (Math.hypot(x, y * 1.2) <= r) p.px(b.x + x, b.y + y, y < -r * 0.5 && x < 0 ? C[7] : Math.hypot(x, y * 1.2) > r - 1 ? C[3] : C[4]);
          } else if (u < 0.75) {   // 破开：一小簇火苗往上窜 + 两颗火星
            const k = (u - 0.45) / 0.3;
            for (let i = 0; i < 3; i++) {
              const fx = b.x + (i - 1) * 1.5, fy = b.y - 1 - k * (6 + 3 * i);
              const r = Math.max(0.5, b.s * (1 - k) * (i === 1 ? 1 : 0.7));
              for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) if (x * x + y * y <= r * r) D(p, fx + x, fy + y, k < 0.35 ? C[7] : k < 0.7 ? C[5] : C[3], 1 - k * 0.6);
            }
            if (k < 0.6) { p.px(b.x - 2 - k * 4, b.y - 3 - k * 9, C[6]); p.px(b.x + 2 + k * 3, b.y - 4 - k * 11, C[5]); }
          }
        }
      }
      // ================================================================ s1cast（S1 起手：火缕绕身旋上）
      if (part === "s1cast") {
        if (up) {
          const H = 62, RX = 13 + 2 * E;
          for (const a0 of S.strands) {
            const head = clamp(t / 0.3), tail = clamp((t - 0.15) / 0.35);
            for (let u = tail; u <= head; u += 0.01) {
              const an = a0 + u * 1.4 * TAU, x = Math.cos(an) * RX * (1 - 0.4 * u), y = -u * H + Math.sin(an) * RX * 0.35;
              const back = Math.sin(an) < -0.2;   // 绕到身后的那段暗一阶
              const hv = (u - tail) / Math.max(0.01, head - tail);
              const c = back ? C[3] : hv > 0.85 ? (t < 0.15 ? C[7] : C[5]) : hv > 0.4 ? C[5] : C[4];
              for (let q = 0; q < S.TH; q += 0.5) p.px(x, y - q, c);
            }
          }
          sim(p);   // 杖头一小团火
          for (const f of S.sparks) { const a = t - 0.28 - f.d; if (a <= 0 || a > 0.2) continue; const d = Math.hypot(f.vx, f.vy) || 1; spark(p, f.vx * a, -H + f.vy * a, f.vx / d, f.vy / d, 3, C, false); }
        }
        if (gd && E >= 2) {
          const a = t < 0.1 ? t / 0.1 : 1 - smooth(0.3, 0.6, t);
          if (a > 0) edge(p, 24, SY, S.segs, 2, a, C, sd, t, t < 0.25);
        }
        if (raw && t < 0.5) p.glow(0, -40, 26, C[5], 0.5);
      }
      // ================================================================ s3cast（S3 起手：熔岩喷柱 + 脚下裂缝圈）
      if (part === "s3cast") {
        if (up) sim(p);
        if (gd) {
          const a = t < 0.05 ? 1 : 1 - smooth(0.4, 0.9, t);
          if (a > 0) { edge(p, R, SY, S.segs, 2, a, C, sd, t, t < 0.2); cracks(p, S.cr, SY, t, C, sd, 0.15, 0.7); }
        }
        if (raw && t < 0.5) p.glow(0, -R, R * 1.4, C[5], 0.55);
      }
      // ================================================================ aura（S3 持续：脚下一圈断续热边，循环）
      if (part === "aura" && gd) {
        const ph = (t / +o.dur) * TAU;
        const segs = S.segs.map((s) => ({ c: s.c + ph * 0.25, half: s.half }));
        edge(p, R, SY, segs, 2, 0.85, C, sd, Math.sin(ph), false, 0.06);
        for (let i = 0; i < 5; i++) {
          const an = ph * 0.25 + i * TAU / 5 + 0.4, v = (Math.sin(ph * 2 + i * 1.7) + 1) * 0.5;
          if (v > 0.6) p.px(Math.cos(an) * (R - 1), Math.sin(an) * (R - 1) * SY, v > 0.85 ? C[5] : C[4]);
        }
      }
    },
  };
}
