// 乌尔比安「放开版」锚砸地面（claude/pixelfx-ul-ulpianus，开关 fx/px_unleashed）：俯视地面，原点 = 判定圆心（地面），地面透视 y × SY。
// 用户认可过的裂地做法（memory「特效力量感做法」10-30）：不规整分叉裂网、先压暗再爆亮再冷却、隆起的尘墙、预兆和余震；规整放射 / 同心圈被否。
// 原作参照（ulpia.ab，只作参照）：普攻 attack_hit_01 = 靛蓝命中闪 + 水泡；S3 落点 range_01 = 大爆亮 + 水花外甩 + 暗底收拢。
// move：
//   slam   普攻「锚击」（半径 = reach）：裂网 + 边缘断续尘墙；E1 加飞石，E2 裂缝里透出暗酒红血纹 + 余震一跳（docs/91 精二血脉）
//   s2     「必须维系的界限」生效后的锚击：同裂地，外加锚砸开的水坑往上喷一圈不规整水刺（原作 skill_02_hit_01 的水爆）
//   quake  特性「撼地」（以自身为心）：从脚下放出 3–5 条不规则长裂缝，裂缝末端隆起一小段尘墙、碎石沿裂缝飞出（组长 C 11-04：不要排成一圈的碎石）
//   land   S3「必须开辟的通路」落地：压暗预兆 → 一记爆亮 → 粗长裂网铺满判定半径、成片水刺从裂缝里顶起、几段浪身弧片立起后往外拍倒碎成水花 + 碎石，余震两跳；
//          量级靠地裂 / 水刺 / 浪身，不画外扩的冲击环（组长 C 11-04、用户否决外扩光环）
//   blast2 成长「定点爆破」：同一落点 0.2 秒后从裂缝尖端喷出几股深海水柱
//   after  成长「通路余震」：小落点，几条短裂 + 一团尘
//   reel   S1 拽回后重砸：裂地 + 水冠往上翻（原作 skill_01_range_02 的水花）
//   erupt  终结技沿裂圈的喷发点：两三条短裂 + 水刺 + 碎石 + 尘（代替旧版沿圈等距摆的水柱），位置由代码按哈希错开
//   dust   精二「掷锚」拖人时脚下扬的一小团尘（无裂、无闪）
//   throw  精二「掷锚」落地：锚咬地的深沟（沿掷出方向 +x）+ 裂网 + 血纹
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Ulpianus anchor impact unleashed",
  desc: "An anchor bites the ground: a dark blot, one white flash, an uneven forked crack web cooling from white through indigo, a broken ridge of dust thrown up at the rim, chips and spray, an aftershock.",
  tags: ["impact", "ground", "crack", "anchor", "topdown", "one-shot"],
  size: [300, 240],
  origin: [150, 150],
  duration: 1.3,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#070a1f", "#121a45", "#1e2d73", "#2f47a3", "#4a68cf", "#7f97ea", "#c3cef7", "#ffffff"],   // 深海靛蓝（原作 #415aff / #589eff 一路，压低饱和，和敌弹青 #33ceff 拉开约 30°）
    dust: ["#131528", "#212842", "#323c5e", "#4a5781", "#6b7ba6", "#9eabcf"],                               // 尘 / 碎石：偏靛的钢灰（锚链色，压进深海色调）
    blood: ["#1c0710", "#33101c", "#4d1626", "#6b1e33"],                                                  // E2 血纹：深暗绯红（明度 ≤ 0.55，组长 C 11-04；和危险色 #ff2667 拉开），只在裂缝里、1 格宽
    radius: 45,
    move: "slam",
    elite: 2,
    quick: 0,
    spray: 0,          // 1 = 画往外甩的水珠 / 火星 / 碎石（docs/242 §14.7 用户 11-04 取消，缺省 0；尘 / 水雾保留）
    layer: "all",
    seed: 3,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), D = fit(o.dust, 6), BL = fit(o.blood, 4), Rg = new Rng(o.seed), mv = o.move || "slam", quick = +o.quick > 0;
  const el = clamp(Math.round(+o.elite), 0, 2), R = +o.radius;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const erupt = mv === "erupt", big = mv === "land", quake = mv === "quake" || mv === "dust", small = mv === "after", dustOnly = mv === "dust";
  // 分档：DL 余韵、GK 光晕、PM 颗粒量
  const DL = (big ? 1 : [0.5, 0.75, 1][el]) * (quick ? 0.55 : 1), GK = big ? 1 : [0.45, 0.75, 1][el], PM = big ? 1.2 : [0.55, 0.8, 1][el];
  const blood = (el >= 2 || mv === "throw") && !quake ? 1 : quake && el >= 2 && !dustOnly ? 0.6 : 0;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[4] }), lights = new Lights();
  if (!(+o.spray > 0)) { const sp0 = ps.spawn.bind(ps); ps.spawn = (k, ...a) => (k === P.DUST || k === P.VAPOUR || k === P.SMOKE ? sp0(k, ...a) : null); }   // §14.7：甩出物不画
  const T_DARK = quake ? 0 : 0.04;          // 压暗一帧，再爆亮
  const T_FLASH = T_DARK + (big ? 0.05 : 0.04);
  const GROW = big ? 0.12 : quake ? 0.2 : 0.08;

  // ---- 裂网：几条主裂从中心不规整地往外走（随机游走 + 噪声转角），沿途随机分叉；角度不等距
  const cracks = [];
  const nMain = dustOnly ? 0 : quake ? 3 + el : small || erupt ? 3 : big ? 9 : mv === "blast2" ? 4 : [4, 6, 7][el];
  const reachK = big ? 1.0 : 0.92;
  const walk = (x, y, a, L, w, d0, depth) => {
    const pts = [[x, y, d0]];
    let d = d0;
    for (let s = 0; s < L;) {
      const st = Rg.range(1.4, 3.2);
      a += Rg.range(-0.45, 0.45) + 0.25 * noise(s * 0.3, Rg.int(0, 999));
      x += Math.cos(a) * st; y += Math.sin(a) * st; s += st; d += st;
      pts.push([x, y, d]);
      if (depth < 2 && s > 4 && Rg.chance((depth ? 0.05 : 0.09) * (el >= 1 || big ? 1.3 : 0.7))) {
        cracks.push(walk(x, y, a + Rg.sign() * Rg.range(0.5, 1.1), (L - s) * Rg.range(0.3, 0.6), Math.max(1, w - 1), d, depth + 1));
      }
    }
    return { pts, w, depth };
  };
  if (mv === "throw") {   // 锚咬地的深沟：沿 +x 一道粗沟，两侧再出几条
    cracks.push(walk(-R * 0.25, 0, Rg.range(-0.08, 0.08), R * 0.9, 3, 0, 0));
    for (const a of jitterAngles(Rg, 4, -Math.PI, Math.PI, 0.45)) cracks.push(walk(Rg.range(-4, 6), Rg.range(-2, 2), a, R * Rg.range(0.45, 0.75), 2, 2, 0));
  } else {
    for (const a of jitterAngles(Rg, nMain, -Math.PI, Math.PI, 0.45)) {
      if (quake) {   // 撼地：裂缝从脚边起（人站在圆心），伸到判定边附近
        const r0 = R * Rg.range(0.14, 0.22);
        cracks.push(walk(Math.cos(a) * r0, Math.sin(a) * r0, a + Rg.range(-0.2, 0.2), R * Rg.range(0.62, 0.86), 2, r0, 0));
        continue;
      }
      const L = R * reachK * Rg.range(0.7, 1.05);
      cracks.push(walk(Rg.range(-2, 2), Rg.range(-1.5, 1.5), a, L, big ? 3 : 2, 0, 0));
    }
  }
  // 撼地：判定边上几处短裂口（往里往外各一点），不连成圈
  const rimCracks = [];
  if (false) for (const a of jitterAngles(Rg, Rg.int(5, 7) + el, -Math.PI, Math.PI, 0.48)) {
    if (Rg.chance(0.25)) continue;
    const x = Math.cos(a) * R * Rg.range(0.9, 1.0), y = Math.sin(a) * R * Rg.range(0.9, 1.0);
    rimCracks.push({ c: walk(x, y, a + Rg.range(-1.9, -1.2) * Rg.sign(), R * Rg.range(0.12, 0.22), 1, 0, 2), a });
  }

  // ---- 尘墙：沿判定边隆起，高低起伏、有断口（覆盖约一半），不是整圈
  const wallH = (big ? 15 : quake ? 5 + 2 * el : small ? 5 : [6, 7.5, 9][el]) * (mv === "s2" ? 1.15 : 1);
  const wallSeed = Rg.int(0, 9999);
  // 离散土脊：4–6 段，各段角度长度 / 离心距离 / 高度都不同，合起来只盖住一圈的三分之一左右（读起来是被砸开翻起的土，不是一道环）
  const ridges = [];
  {
    const onEnds = quake || mv === "slam" || mv === "s2";   // 尘墙挂在主裂缝末端（组长 C 11-04：普攻碎石别绕成一圈）
    const n = dustOnly || big || onEnds ? 0 : erupt ? 2 : small ? 2 : [3, 4, 5][el];
    let kEnd = quake ? 99 : [2, 2, 3][el];
    if (onEnds) for (const c of cracks) {   // 撼地：尘墙只隆在主裂缝末端，一小段
      if (c.depth || kEnd-- <= 0) continue;
      const e = c.pts[c.pts.length - 1], d = Math.hypot(e[0], e[1]);
      ridges.push({ a: Math.atan2(e[1], e[0]), len: Rg.range(10, 16) / Math.max(10, d), d: d / R, h: Rg.range(0.7, 1.1), skew: Rg.range(-0.5, 0.5) });
    }
    for (const a of jitterAngles(Rg, n, -Math.PI, Math.PI, 0.45)) ridges.push({ a, len: Rg.range(0.22, 0.5) * (big ? 1.2 : quake ? 0.4 : 1), d: Rg.range(0.82, 1.08), h: Rg.range(0.6, 1.15), skew: Rg.range(-0.5, 0.5) });
  }
  const wallAt = (a) => {   // 返回 [高度, 离心系数]
    for (const r of ridges) {
      let u = (a - r.a + Math.PI * 3) % TAU - Math.PI;
      u /= r.len;
      if (Math.abs(u) > 1) continue;
      const env = Math.pow(1 - u * u, 0.6) * (0.7 + 0.3 * noise(a * 9, wallSeed + 5) + 0.25 * noise(a * 31, wallSeed + 9));
      return [wallH * r.h * env, r.d + r.skew * 0.05 * u];
    }
    return [0, 1];
  };
  // ---- 水刺（s2 / blast2 / reel / land）：喷起的位置不等距，高矮粗细各不同
  const jets = [];
  const nJ = big ? 0 : mv === "s2" ? [0, 5, 6][el] : mv === "blast2" ? 3 + el : mv === "reel" ? 4 + el : big ? 6 : erupt ? 3 : 0;
  if (nJ) for (const a of jitterAngles(Rg, nJ, -Math.PI, Math.PI, 0.45)) {
    const d = mv === "blast2" ? R * Rg.range(0.35, 0.8) : R * Rg.range(0.15, 0.6);
    jets.push({ x: Math.cos(a) * d, y: Math.sin(a) * d * SY, H: (mv === "reel" ? 30 : big || erupt ? 30 : mv === "blast2" ? 26 : 20) * Rg.range(0.55, 1.1) * (0.8 + 0.1 * el), w: Rg.range(2.2, 3.6), d0: (mv === "blast2" ? 0.0 : 0.05) + Rg.range(0, 0.09), lean: Rg.range(-0.15, 0.15) + Math.cos(a) * Rg.range(0.5, 0.9) });
  }

  // ---- 水刃：命中一刻从落点刺出几道细长水刃（借原作 attack_hit_01 / skill_03_range_01 的尖刺星芒），角度不等距、长短不一、偏向上方，2–4 帧就收
  const shards = [];
  {
    const n = quake || dustOnly ? 0 : small ? 2 : big ? 5 : mv === "throw" ? 4 : [3, 4, 5][el] + (mv === "s2" || mv === "reel" ? 1 : 0);
    for (const a of jitterAngles(Rg, n, -Math.PI, Math.PI, 0.48)) {
      const up = a < 0 ? 1 : 0.55;   // 朝上的长、贴地的短（俯视里朝上 = 立起来）
      shards.push({ a, L: R * Rg.range(0.55, 1.05) * up * (big ? 0.55 : 1), w: Rg.range(1.6, 2.8), d0: Rg.range(0, 0.03) });
    }
  }
  if (big) {   // S3：水刺挂在裂缝上，成片顶起（位置取裂缝上的点，先后跟着裂缝往外长）
    const pool = [];
    for (const c of cracks) for (const q of c.pts) if (q[2] > R * 0.18) pool.push(q);
    for (let k = 0; k < 15 && pool.length; k++) {
      const q = pool.splice(Rg.int(0, pool.length - 1), 1)[0], a = Math.atan2(q[1], q[0]);
      jets.push({ x: q[0], y: q[1] * SY, H: Rg.range(16, 34) * (1 - 0.35 * q[2] / R), w: Rg.range(2.0, 3.4), d0: 0.03 + q[2] / R * 0.1 + Rg.range(0, 0.04), lean: Math.cos(a) * Rg.range(0.35, 0.7) });
    }
  }
  // S3 浪身弧片：几段弧形水墙从裂网外围立起，往外拍倒碎成水花（每段只占一小段角度，合起来不到半圈）
  const curtains = [];
  if (big) for (const a of jitterAngles(Rg, 4, -Math.PI, Math.PI, 0.45)) curtains.push({ a, len: Rg.range(0.45, 0.8), r: R * Rg.range(0.6, 0.85), H: Rg.range(18, 28), d0: Rg.range(0.06, 0.12), s: Rg.int(0, 999) });
  // 翘起的地块（E1+ / S3 / 掷锚的可见元素，代替往外飞的碎石，§14.7）：挂在裂缝中段，被顶起两三格再落回、不飞走
  const slabs = [];
  if ((el >= 1 || big || mv === "throw") && !quake && !small && !dustOnly) {
    const pool = [];
    for (const c of cracks) if (!c.depth) for (const q of c.pts) if (q[2] > R * 0.3 && q[2] < R * 0.85) pool.push(q);
    for (let k = 0, n = big ? 9 : mv === "throw" ? 4 : [0, 3, 4][el]; k < n && pool.length; k++) {
      const q = pool.splice(Rg.int(0, pool.length - 1), 1)[0];
      slabs.push({ x: q[0], y: q[1], w: Rg.range(3, 5.5) * (big ? 1.3 : 1), h: Rg.range(2, 3.5), up: Rg.range(2, 4.5) * (big ? 1.4 : 1), d0: 0.03 + q[2] / R * 0.06, tilt: Rg.range(-0.5, 0.5), s: Rg.int(0, 999) });
    }
  }
  let t = 0, flashed = false, shook = false, shook2 = false;
  const aft = el >= 2 && !quake && !small ? (big ? [0.3, 0.52] : [0.3]) : big ? [0.32] : [];
  const sp = (x, y) => [x, y * SY];   // 地面坐标 → 屏幕

  const crackCol = (heat, d, depth) => {   // heat 1 = 白热 → 0 = 冷却成暗裂
    const i = Math.round(1 + heat * 6 - depth * 0.6 - d / R * 0.8) + (quake ? 1 : 0);   // 撼地裂缝芯亮一档（组长 C：游戏镜头下要读得出）
    return C[clamp(i, 1, 7)];
  };
  const lineB = (p, x0, y0, x1, y1, c, a) => {   // 真半透明细线（p.line 的 a < 1 会抖成点阵）
    const n = Math.max(1, Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) / 0.7));
    for (let i = 0; i <= n; i++) p.blend(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n, c, a);
  };
  function drawCrack(p, c, reached, heat, fade, bl) {
    const pts = c.pts;
    for (let i = 1; i < pts.length; i++) {
      if (pts[i][2] > reached) break;
      const [x0, y0] = sp(pts[i - 1][0], pts[i - 1][1]), [x1, y1] = sp(pts[i][0], pts[i][1]);
      const fresh = clamp(1 - (reached - pts[i][2]) / (R * 0.5));   // 前沿最热
      const h = clamp(heat + fresh * 0.35 * (t < T_FLASH + GROW ? 1 : 0));
      const col = bl > 0 && h < 0.45 && pts[i][2] < R * 0.8 ? BL[clamp(Math.round(1.6 + bl * 1.2 - pts[i][2] / R * 1.6), 1, 3)] : crackCol(h, pts[i][2], c.depth);
      if (fade > 0.98) p.line(x0, y0, x1, y1, col); else lineB(p, x0, y0, x1, y1, col, fade);
      if (c.w >= 2 && pts[i][2] < R * (c.w >= 3 ? 0.55 : 0.3)) lineB(p, x0, y0 + 1, x1, y1 + 1, C[clamp(Math.round(heat * 4), 0, 3)], fade * 0.9);   // 近中心裂口张开一格（暗面在下）
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!flashed && t >= T_DARK) {
        flashed = true;
        if (!quake && !big) lights.add(0, -2, R * 0.4, C[6], 0.35 * GK, 0.1);   // S3 不挂圆光（第一帧读成一团圆盘）
        // 尘：判定边隆起处扬起几团（装饰），慢慢散
        if (deco) for (let a = Rg.range(-Math.PI, -Math.PI + 0.3); a < Math.PI; a += Rg.range(0.45, 0.9) / PM) {
          const [h, dd] = wallAt(a);
          if (h <= 0) continue;
          const [x, y] = sp(Math.cos(a) * R * dd, Math.sin(a) * R * dd);
          ps.spawn(P.DUST, x, y - h * 0.5, Math.cos(a) * Rg.range(10, 35), -Rg.range(6, 22), Rg.range(0.35, 0.6) * DL, D[3 + Rg.int(0, 1)], Rg.range(1.5, 3) * (big ? 1.4 : 1), Rg.range(0, 0.06));
        }
        // 飞石（E1+、落地大爆）：从裂网中段往外抛，带重力
        if (quake && !dustOnly) for (const c of cracks) {   // 撼地：碎石沿裂缝往外飞
          if (c.depth) continue;
          for (let k = 0, m = 1 + el; k < m; k++) {
            const q = c.pts[Rg.int(Math.floor(c.pts.length * 0.4), c.pts.length - 1)], a = Math.atan2(q[1], q[0]), [x, y] = sp(q[0], q[1]);
            ps.spawn(core ? P.GRIT : P.MOTE, x, y, Math.cos(a) * Rg.range(40, 90), -Rg.range(50, 110), Rg.range(0.3, 0.5) * (0.6 + 0.4 * DL), D[3 + Rg.int(0, 2)], Rg.range(1.3, 2.2), Rg.range(0.06, 0.16));
          }
        }
        const nGrit = quake ? 0 : big ? 22 : mv === "after" ? 3 : el >= 1 || mv === "throw" ? Math.round(8 * PM) : 0;
        for (let k = 0; k < nGrit; k++) {
          const a = Rg.range(-Math.PI, Math.PI), d = R * Rg.range(0.2, quake ? 1.0 : 0.7), v = Rg.range(50, 140) * (big ? 1.3 : 1);
          const [x, y] = sp(Math.cos(a) * d, Math.sin(a) * d);
          ps.spawn(core ? P.GRIT : P.MOTE, x, y, Math.cos(a) * v * 0.6, -Rg.range(60, 150) * (big ? 1.2 : 0.8), Rg.range(0.35, 0.6) * (0.6 + 0.4 * DL), D[3 + Rg.int(0, 2)], Rg.range(1.4, 2.4));
        }
        // 水泡 / 水珠（原作命中的水泡；深海色，少量）
        if (deco && !quake) for (let k = 0, n = Math.round((big ? 14 : mv === "after" ? 2 : 5) * PM); k < n; k++) {
          const a = Rg.range(-Math.PI, Math.PI), v = Rg.range(30, 110);
          ps.spawn(P.MOTE, Rg.range(-4, 4), -2, Math.cos(a) * v, -Rg.range(40, 140), Rg.range(0.35, 0.7) * DL, C[5 + Rg.int(0, 2)], Rg.range(0.8, 1.3), Rg.range(0, 0.05));
        }
        if (deco && big) for (let k = 0; k < 10; k++) {   // 大爆：落点一团水雾
          const a = Rg.range(-Math.PI, Math.PI);
          ps.spawn(P.VAPOUR, Math.cos(a) * R * 0.3, Math.sin(a) * R * 0.3 * SY, Math.cos(a) * 40, Math.sin(a) * 20 - 10, Rg.range(0.4, 0.7), C[4], Rg.range(2, 4));
        }
      }
      for (const j of jets) {   // 水刺顶端甩水珠
        const u = t - T_DARK - j.d0;
        if (u > 0.08 && u < 0.08 + dt && deco) for (let k = 0; k < 3; k++) ps.spawn(P.MOTE, j.x + j.lean * j.H, j.y - j.H, Rg.range(-50, 50), -Rg.range(20, 70), Rg.range(0.3, 0.55) * DL, C[6 + Rg.int(0, 1)], Rg.range(0.8, 1.2));
      }
      if (deco) for (const cu of curtains) {   // 浪身拍倒时沿弧碎成水花
        const u = t - T_DARK - cu.d0;
        if (u > 0.26 && u < 0.26 + dt) for (let s2 = -cu.len / 2; s2 < cu.len / 2; s2 += Rg.range(0.06, 0.14)) {
          const a = cu.a + s2, [x, y] = sp(Math.cos(a) * cu.r, Math.sin(a) * cu.r);
          ps.spawn(Rg.chance(0.6) ? P.MOTE : P.SPARK, x, y - Rg.range(4, 14), Math.cos(a) * Rg.range(40, 120), -Rg.range(20, 90), Rg.range(0.3, 0.6), C[5 + Rg.int(0, 2)], Rg.range(0.8, 1.3));
        }
      }
      for (let i = 0; i < aft.length; i++) {   // 余震：一小团尘 + 几颗碎石
        const fl = i ? shook2 : shook;
        if (!fl && t >= aft[i]) {
          if (i) shook2 = true; else shook = true;
          if (deco) for (let k = 0; k < 5; k++) {
            const a = Rg.range(-Math.PI, Math.PI), d = R * Rg.range(0.3, 0.9), [x, y] = sp(Math.cos(a) * d, Math.sin(a) * d);
            ps.spawn(P.DUST, x, y, Math.cos(a) * 12, -Rg.range(5, 14), Rg.range(0.3, 0.5) * DL, D[2 + Rg.int(0, 1)], Rg.range(2, 3.5));
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      // 压暗：落点先一团不规整的暗影（预兆），爆亮后退去
      if (core && !quake) {
        const k = t < T_DARK + 0.001 ? 0.75 : (1 - smooth(T_FLASH, T_FLASH + 0.12, t)) * 0.4;
        const rr = R * (big ? 0.8 : 0.55) * (t < T_DARK + 0.001 ? 0.8 : 1);
        if (k > 0.02) p.each(-rr * 1.3, -rr * SY * 1.3, rr * 1.3, rr * SY * 1.3, (x, y, sx, sy) => {   // 真半透明（blendPx），不抖点
          const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY);
          const e = rr * (0.75 + 0.3 * noise(a * 3, o.seed + 11) + 0.15 * noise(a * 8, o.seed + 13));
          if (r > e) return;
          p.blendPx(sx, sy, C[0], k * (1 - Math.pow(r / e, 3) * 0.6));
        });
      }
      // 震波（撼地）：一道很淡的地面起伏从里往外推（装饰），到判定边收住
      if (dustOnly) {   // 拖尘：几团贴地的尘 + 碎石，往后拖
        if (t < 0.05 && !this._d) {
          this._d = 1;
          for (let k = 0; k < 6; k++) ps.spawn(k < 4 ? P.DUST : P.GRIT, Rg.range(-6, 6), Rg.range(-2, 2), -Rg.range(20, 60), -Rg.range(4, 16), Rg.range(0.25, 0.45), D[2 + Rg.int(0, 2)], k < 4 ? Rg.range(1.6, 3) : 1.2);
        }
      }
      if (false) {
        const u = clamp(t / 0.22), rr = R * (0.35 + 0.65 * ease.outCubic(u)), k = (1 - smooth(0.12, 0.34, t)) * 0.5 * GK;
        if (k > 0.02) for (let a = -Math.PI; a < Math.PI; a += 0.7 / rr) {
          const n = noise(a * 3.1 + t * 4, o.seed + 31) + 0.5 * noise(a * 9, o.seed + 37);
          if (n < 0.45) continue;   // 只留稀疏几段断弧（整圈细线是被否的同心圈）
          const [x, y] = sp(Math.cos(a) * rr, Math.sin(a) * rr);
          p.blend(x, y, D[4], k * clamp(n - 0.2));
          p.blend(x, y + 1, D[1], k * 0.8 * clamp(n - 0.2));
        }
      }
      if (deco) ps.draw(p, "back");
      // 裂网
      if (core) {
        const reached = R * 1.2 * ease.outCubic(clamp((t - T_DARK) / GROW));
        let heat = (t < T_DARK ? 0 : t < T_FLASH ? 1 : clamp(1 - (t - T_FLASH) / (0.18 + 0.12 * DL))) * (quake ? 0.7 : 1);
        for (const a of aft) if (t > a && t < a + 0.08) heat = Math.max(heat, 0.35 * (1 - (t - a) / 0.08));   // 余震：裂缝回亮一下
        const fade = 1 - smooth((big ? 0.55 : 0.28) + 0.2 * DL + 0.1 * blood, (big ? 1.1 : 0.5) + 0.3 * DL + 0.15 * blood, t);
        const bl = blood ? clamp((t - T_FLASH - 0.06) / 0.1) * blood : 0;
        if (t >= T_DARK && fade > 0.02) for (const c of cracks) drawCrack(p, c, reached, heat, fade, bl);
        if (quake && fade > 0.02) {
          const ru = smooth(0.08, 0.22, t);
          for (const rc of rimCracks) drawCrack(p, rc.c, R * 0.3 * ru, clamp(1 - t / 0.3) * 0.6, fade * 0.9, el >= 2 ? 0.6 : 0);
        }
      }
    },
    draw(p) {
      // 尘墙：判定边隆起的一道土脊，先拱起再塌
      if (core) {
        const u = t - T_DARK, rise = ease.outBack(clamp(u / (quake ? 0.18 : 0.1))), sink = smooth(0.14 + 0.1 * DL, (big ? 0.6 : 0.34) + 0.16 * DL, u);
        const k = rise * (1 - sink);
        const delay = quake ? 0.16 : 0;
        if (u > delay && k > 0.04) for (let a = -Math.PI; a < Math.PI; a += 1.1 / R) {
          const [h0, dd] = wallAt(a), h = h0 * k;
          if (h < 1) continue;
          const [x, y] = sp(Math.cos(a) * R * dd, Math.sin(a) * R * dd);
          const cw = 1 + Math.round(1.5 + 1.2 * noise(a * 9, wallSeed + 3));   // 土块宽 1–3 格，高低不齐
          for (let d = 0; d < h; d += 0.7) {
            const top = d > h - 1.3, lit = Math.cos(a + 2.3) > 0.3;   // 左上受光
            const col = top ? D[lit ? 5 : 4] : D[clamp(Math.round(1 + 2.5 * d / h + (lit ? 1 : 0)), 1, 4)];
            for (let s2 = 0; s2 < cw; s2 += 0.7) p.px(x + s2 - cw / 2, y - d, col);
          }
        }
      }
      if (core) for (const sb of slabs) {   // 地块：不规则的一小块地面，顶面亮、侧面暗，被顶起后落回原处
        const u = t - T_DARK - sb.d0;
        if (u < 0 || u > 0.55 * DL + 0.2) continue;
        const lift = sb.up * Math.sin(Math.PI * clamp(u / 0.22)) * (u < 0.22 ? 1 : 0), fade = 1 - smooth(0.35 * DL + 0.1, 0.55 * DL + 0.2, u);
        const [cx, cy] = sp(sb.x, sb.y);
        for (let i = -sb.w / 2; i <= sb.w / 2; i += 0.6) for (let j = 0; j <= sb.h; j += 0.6) {
          const e = (Math.abs(i) / (sb.w / 2)) ** 2 + 0.6 * noise(i * 0.8 + j, sb.s);
          if (e > 1) continue;
          const top = j > sb.h - 1.2, x = cx + i, y = cy - lift - j + i * sb.tilt * 0.3;
          p.blend(x, y, top ? D[5] : j < 1 ? D[1] : D[3], fade);
        }
      }
      // 水刺：从裂缝里冲起，尖端白、根部深，到顶后碎落
      if (core) for (const j of jets) {
        const u = t - T_DARK - j.d0;
        if (u < 0 || u > 0.42) continue;
        const H = j.H * ease.outCubic(clamp(u / 0.1)) * (1 - smooth(0.2, 0.42, u)), base = smooth(0.14, 0.36, u) * H;
        for (let d = base; d < H; d += 0.6) {
          const v = d / Math.max(1, j.H), nz = noise(d * 0.35 + j.d0 * 50, o.seed + 77);
          if (v > 0.45 && nz < -0.45) continue;   // 上段断开、碎成水团
          const w = (j.w * Math.pow(1 - v, 1.1) + 0.4) * (0.75 + 0.4 * nz);   // 收尖、边缘起伏
          for (let s = -w; s <= w; s += 0.6) {
            const e = Math.abs(s) > w - 0.7;
            p.px(j.x + s + j.lean * d, j.y - d, d > H - 2 ? (u < 0.2 || !big ? C[7] : C[6]) : e ? C[clamp(Math.round(4 + 2 * v), 4, 6)] : C[clamp(Math.round(2 + 3.5 * v + nz), 2, 6)]);
          }
        }
      }
      if (core) for (const sh of shards) {   // 水刃：细长楔形，尖白根深，伸出后从根部往尖端退
        const u = t - T_DARK - sh.d0;
        if (u < 0 || u > 0.16) continue;
        const L = sh.L * ease.outExpo(clamp(u / 0.05)), b0 = sh.L * smooth(0.05, 0.16, u), ux = Math.cos(sh.a), uy = Math.sin(sh.a) * (sh.a < 0 ? 0.9 : SY);
        for (let d = b0; d < L; d += 0.6) {
          const v = d / sh.L, w = sh.w * (1 - v) * (1 - 0.5 * clamp((u - 0.05) / 0.11));
          for (let q = -w; q <= w; q += 0.6) p.px(ux * d - uy * q, uy * d + ux * q * 0.7, u < 0.05 || v > 0.8 ? C[7] : Math.abs(q) > w - 0.7 ? C[6] : C[clamp(Math.round(4 + 2 * v), 4, 6)]);
        }
      }
      if (core) for (const cu of curtains) {   // 浪身：弧形水墙立起（高度起伏、尖白），0.22 秒后往外拍倒、根部先退
        const u = t - T_DARK - cu.d0;
        if (u < 0 || u > 0.5) continue;
        const rise = ease.outCubic(clamp(u / 0.12)), fall = smooth(0.2, 0.42, u), lean = smooth(0.14, 0.34, u);
        for (let s2 = -cu.len / 2; s2 < cu.len / 2; s2 += 0.6 / cu.r) {
          const a = cu.a + s2, env = Math.pow(Math.cos(s2 / cu.len * Math.PI), 0.6) * (0.7 + 0.4 * noise(a * 9, cu.s));
          const H = cu.H * env * rise, base = H * fall, ox = Math.cos(a), oy = Math.sin(a);
          const [bx, by] = sp(ox * cu.r, oy * cu.r);
          for (let d = base; d < H; d += 0.6) {
            const v = d / Math.max(1, H), push = lean * v * v * 10;
            p.px(bx + ox * push, by + oy * push * SY - d, d > H - 1.6 ? (u < 0.28 ? C[7] : C[5]) : C[clamp(Math.round(2 + 4 * v + 0.8 * noise(d * 0.4 + a * 5, cu.s + 3)), 2, 6)]);
          }
        }
      }
      // 爆亮：一帧不规整的白热星芯（不是圆）
      if (core && !quake && t >= T_DARK && t < T_FLASH + 0.04) {
        const k = t < T_FLASH ? 1 : 0.45, rr = (big ? 12 : small ? 4 : 7) * (0.7 + 0.15 * el);
        p.shade(-rr * 1.6, -rr * 1.2, rr * 1.6, rr * 1.2, (x, y, out) => {
          const a = Math.atan2(y, x), r = Math.hypot(x, y * 1.3);
          const e = rr * (0.45 + 0.55 * Math.pow(Math.abs(noise(a * 2.7, o.seed + 21)), 0.6));
          if (r > e) return;
          out.c = r < e * 0.5 && k > 0.9 ? C[7] : C[k > 0.9 ? 6 : 5];
          out.a = 1;
        });
      }
      if (deco) {
        if (!quake && t >= T_DARK && t < T_FLASH + 0.22) {   // 光顺着裂缝走（不画圆形大光团）
          const kk = (t < T_FLASH ? 0.5 : 0.28 * (1 - (t - T_FLASH) / 0.22)) * GK, reached = R * 1.2 * ease.outCubic(clamp((t - T_DARK) / GROW));
          for (const c of cracks) {
            if (c.depth) continue;
            const pts = c.pts;
            for (let i = 2; i < pts.length; i += 2) {
              if (pts[i][2] > reached) break;
              const [x0, y0] = sp(pts[i - 2][0], pts[i - 2][1]), [x1, y1] = sp(pts[i][0], pts[i][1]);
              p.glowLine(x0, y0, x1, y1, big ? 7 : 5, C[5], kk * (1 - pts[i][2] / (R * 1.2)));
            }
          }
        }
        if (false) {   // 血纹不往外发光（组长 C 11-04：只出现在裂纹里）
          const kk = 0.22 * blood * smooth(T_FLASH + 0.05, T_FLASH + 0.15, t) * (1 - smooth(0.35, 0.6, t));
          for (const c of cracks) {
            if (c.depth) continue;
            const pts = c.pts;
            for (let i = 2; i < pts.length; i += 3) {
              if (pts[i][2] > R * 0.75) break;
              const [x0, y0] = sp(pts[i - 2][0], pts[i - 2][1]), [x1, y1] = sp(pts[i][0], pts[i][1]);
              p.glowLine(x0, y0, x1, y1, 3, BL[2], kk * 0.7);
            }
          }
        }
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
