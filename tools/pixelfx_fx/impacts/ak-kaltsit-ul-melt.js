// 凯尔希 · Mon3tr 熔毁爆（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：俯视，原点 = 爆心（Mon3tr 所在处），地面按透视压扁。
// 用户定：纯红色粒子爆炸，不加烟团；11-04 用户：往外发散的光环一律不要（不画扩散圈 / 冲击环）。
// 原作参照（build/ark_ref/mon3tr）：S3 命中的红芯 + 红碎片（skill_03_hit：ptc blkkgt_03 拉长红点、red_line 红裂纹）、S3 结束 end_01 的线状迸散；
//   原作结束是结晶化，本作是熔毁爆（自创），只借红芯 / 红碎片 / 拉长火星的画法。
// 构成：首帧白热晶芯（核心）→ 晶芯崩成不等大的红晶片往外迸（核心：主形）+ 地面不规则红裂纹落在判定半径内（核心：范围边缘用裂纹尖端表示，不画圆）
//   → 拉长红火星 + 余烬慢慢落（装饰）。
// move：ult（终结技爆心，最大）/ pop（终结技外两圈散落的小爆，无地面裂纹以外的东西）/ end（S3 结束，r = melt_r）/ rebuild（S1 重构与三连爆的后两拍，小一号、晶片少）/ down（Mon3tr 倒地爆）/ debride（清创：敌人身上爆开，最小）
import { Particles, Lights, Bits, B, P, Rng, fit, clamp, smooth, ease, noise, noise2, hex, TAU } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 #12）：OP.kaltsit 黄绿、OP.kaltsit_melt 熔毁红

// 实色：painter.put 在 a < 1 时按 Bayer 点阵抖动（棋盘格脏点，§12 画面不能脏）；本作一律 a ≥ 0.5 画实、< 0.5 不画，淡出靠色阶变暗
function solid(p) {
  if (p._solid) return;
  const f = p.put.bind(p);
  p.put = (sx, sy, c, a = 1) => { if (a < 0.999) { if (a < 0.5) return; a = 1; } f(sx, sy, c, a); };
  p._solid = 1;
}

export const meta = {
  name: "Kal'tsit Mon3tr meltdown burst unleashed",
  desc: "Mon3tr melts down from above: a white-hot crystal core cracks into uneven red shards that fly outward, red fractures snake across the ground to the edge of the blast and long red sparks and embers settle. No smoke, no expanding ring.",
  tags: ["impact", "explosion", "crystal", "red", "topdown", "one-shot"],
  size: [240, 200],
  origin: [120, 100],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    red: OP.kaltsit_melt,
    radius: 65,      // 判定半径（1x 像素）：judge 传 melt_r / 2
    sy: 0.55,        // 地面透视压扁
    move: "end",
    quick: 0,
    layer: "all",
    seed: 5,
  },
};

export function create(o) {
  const C = fit(o.red, 8), Rg = new Rng(o.seed), R0 = o.radius, SY = o.sy, mv = o.move;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ult = mv === "ult", big = mv === "end" || ult, small = mv === "debride" || mv === "pop";
  const K = ult ? 1.35 : big ? 1 : small ? 0.55 : 0.8;              // 体量
  const DL = (+o.quick > 0 ? 0.5 : 1) * (small ? 0.6 : 1);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[5], C[4]], haze: C[3] }), lights = new Lights();
  const bits = new Bits({ ground: () => 1e9 });
  const CY = -10 * K;   // 晶芯离地高度（Mon3tr 身体中段）

  // ---- 晶片：不等大、不等角（角度随机步长，不等距），往外迸、带旋转；核心层
  const shards = [];
  let a = Rg.range(0, TAU);
  const ns = ult ? 13 : big ? 9 : small ? 4 : 6;
  for (let i = 0; i < ns; i++) {
    a += TAU / ns * Rg.range(0.55, 1.45);
    const sp = R0 * Rg.range(1.8, 3.0) * K, L = Rg.range(7, 15) * K, W = Rg.range(2.5, 5) * K;
    shards.push({ a, sp, L, W, rot: a + Rg.range(-0.6, 0.6), spin: Rg.range(-9, 9), t0: 0.03 + Rg.range(0, 0.03), life: Rg.range(0.22, 0.36) });
  }
  // ---- 地面裂纹：从爆心往外的折线，尖端落在判定半径附近（0.8–1.0 R），条数少、角度不等；核心层
  const cracks = [];
  let b0 = Rg.range(0, TAU);
  const nc = ult ? 8 : big ? 6 : small ? 3 : 4;
  for (let i = 0; i < nc; i++) {
    b0 += TAU / nc * Rg.range(0.6, 1.4);
    const pts = [[0, 0]], reach = R0 * Rg.range(0.78, 1.0) * (small ? 0.8 : 1);
    let ang = b0, d = 0;
    while (d < reach) { d = Math.min(reach, d + Rg.range(5, 11)); ang += Rg.range(-0.35, 0.35); pts.push([Math.cos(ang) * d, Math.sin(ang) * d * SY]); }
    const fork = Rg.chance(0.6) ? { at: Rg.int(2, Math.max(2, pts.length - 2)), ang: ang + Rg.range(0.5, 0.9) * (Rg.chance(0.5) ? 1 : -1), len: reach * Rg.range(0.2, 0.35) } : null;
    cracks.push({ pts, fork, t0: Rg.range(0, 0.04) });
  }
  // ---- 装饰：拉长红火星（STREAK 跟速度方向拉长）、余烬、热碎屑
  if (deco) {
    for (let i = 0; i < (ult ? 70 : big ? 44 : small ? 12 : 24); i++) {
      const aa = Rg.range(0, TAU), sp = Rg.range(120, 340) * K;
      ps.spawn(P.SPARK, Math.cos(aa) * 4, CY + Math.sin(aa) * 3, Math.cos(aa) * sp, Math.sin(aa) * sp * 0.8, Rg.range(0.18, 0.42) * DL + 0.05, 0, 1, Rg.range(0.02, 0.06));
    }
    for (let i = 0; i < (big ? 14 : small ? 4 : 8); i++) {
      const aa = Rg.range(0, TAU), d = R0 * Rg.range(0.2, 0.8);
      ps.spawn(P.EMBER, Math.cos(aa) * d, Math.sin(aa) * d * SY, Rg.range(-8, 8), -Rg.range(10, 30), Rg.range(0.4, 0.75) * DL, C[Rg.int(4, 6)], 1, Rg.range(0.08, 0.2));
    }
    for (let i = 0; i < (big ? 8 : small ? 2 : 4); i++) {
      const aa = Rg.range(0, TAU), sp = Rg.range(70, 170) * K;
      bits.add({ kind: B.SHARD, x: 0, y: CY, vx: Math.cos(aa) * sp, vy: Math.sin(aa) * sp * 0.7, a: Rg.range(0, 6.28), va: Rg.range(-14, 14), s: Rg.range(1.5, 3) * K,
        c: C[4], ramp: o.red.slice(2, 7), g: 0, drag: 2.6, bounce: 0, life: Rg.range(0.3, 0.55) * DL + 0.08 });
    }
  }

  const shardPoly = (x, y, L, W, r) => {
    const c = Math.cos(r), s = Math.sin(r);
    return [[x + c * L, y + s * L], [x - s * W, y + c * W], [x - c * L * 0.6, y - s * L * 0.6], [x + s * W * 0.7, y - c * W * 0.7]];
  };

  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); bits.update(dt); lights.update(dt); },
    drawBack(p) { if (deco) ps.draw(p, "back"); },
    draw(p) {
      solid(p);
      // 地面裂纹（核心）：先亮后暗，沿长度逐段亮起
      if (core) for (const c of cracks) {
        const u = t - c.t0;
        if (u < 0) continue;
        const grow = ease.outCubic(clamp(u / 0.1)), fade = 1 - smooth(0.25, 0.6 * DL + 0.2, u);
        if (fade <= 0) continue;
        const n = Math.max(1, Math.floor((c.pts.length - 1) * grow));
        const col = u < 0.05 ? C[7] : C[clamp(Math.round(6 - u * 8), 3, 6)];
        for (let i = 0; i < n; i++) p.line(c.pts[i][0], c.pts[i][1], c.pts[i + 1][0], c.pts[i + 1][1], col, fade);
        if (c.fork && n > c.fork.at) {
          const [fx, fy] = c.pts[c.fork.at];
          p.line(fx, fy, fx + Math.cos(c.fork.ang) * c.fork.len, fy + Math.sin(c.fork.ang) * c.fork.len * SY, C[clamp(Math.round(5 - u * 8), 3, 5)], fade);
        }
      }
      // 装饰：沿裂纹的暗红光（不画圆形光团）
      if (deco) for (const c of cracks) {
        const u = t - c.t0, k = (1 - smooth(0.05, 0.4 * DL + 0.1, u)) * 0.22;
        if (u < 0 || k <= 0.01) continue;
        const e = c.pts[Math.floor((c.pts.length - 1) * 0.6)];
        p.glowLine(0, 0, e[0], e[1], 6 * K, C[4], k);
      }
      if (deco) { bits.draw(p); ps.draw(p, "front"); }
      // 爆团（核心）：0.02–0.2 s 红热团块，外缘按 noise 起伏（不是圆）、往外长；后段被噪声洞蚀穿、碎成颗粒
      if (core && t > 0.015 && t < 0.24) {
        const u = (t - 0.015) / 0.225, Rb = R0 * (0.25 + 0.5 * ease.outCubic(clamp(u * 1.6))) * K, hole = smooth(0.3, 1, u);
        p.shade(-Rb - 6, CY - Rb - 6, Rb + 6, CY + Rb * 0.8 + 6, (x, y, out) => {
          const dx = x, dy = (y - CY) / 0.8, d = Math.hypot(dx, dy), an = Math.atan2(dy, dx);
          const edge = Rb * (0.72 + 0.28 * noise(an * 3.1 + o.seed, o.seed) + 0.16 * noise(an * 9.3, o.seed + 3));
          if (d > edge) return;
          const q = d / edge, n2 = 0.5 + 0.5 * noise2(x * 0.19 + 31, y * 0.21 - 17, o.seed + 7);   // 二维噪声蚀洞（一维相加会出横竖条纹）
          if (n2 < hole * 1.05 - q * 0.25) return;
          out.c = u < 0.08 ? (q < 0.4 ? C[7] : C[5]) : C[clamp(Math.round(5.6 - q * 3 - u * 3.5), 2, 6)];   // 组长 C v2：爆团压一档，中心别是整块饱和红 / 白
        });
      }
      // 晶芯：首帧白热菱形晶核，0.03 s 起崩开；晶片往外迸
      if (core) {
        if (t < 0.06) {
          const s = (big ? 12 : small ? 6 : 9) * (0.8 + t * 6), hot = t < 0.05;
          p.poly([[0, CY - s * 1.3], [s * 0.7, CY], [0, CY + s * 0.8], [-s * 0.7, CY]], hot ? C[7] : C[6], 1);
          p.poly([[0, CY - s * 0.7], [s * 0.35, CY], [0, CY + s * 0.4], [-s * 0.35, CY]], C[7], 1);
        }
        for (const sh of shards) {
          const u = t - sh.t0;
          if (u < 0 || u > sh.life) continue;
          const d = sh.sp * (1 - Math.exp(-u * 6)) / 6, k = u / sh.life;
          const x = Math.cos(sh.a) * d, y = CY + Math.sin(sh.a) * d * 0.75;
          const col = u < 0.04 ? C[6] : C[clamp(Math.round(5 - k * 3.5), 2, 5)];
          p.poly(shardPoly(x, y, sh.L * (1 - k * 0.4), sh.W * (1 - k * 0.3), sh.rot + sh.spin * u), col, 1);
        }
      }
      if (deco) lights.draw(p);
    },
  };
}
