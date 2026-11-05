// 逻各斯 S1「提喻」放开版（docs/242；开关 fx/px_unleashed）：原点 = 被锁定敌人的身体中心，正右 = 从逻各斯指向敌人的方向（游戏里按方向转）。
// 锁链本体不换（docs/242 §4）；这里只画链端每一跳落在目标身上的那一下（move "tick"）和锁定那一刻（move "lock"）。
// tick：一笔带飞白的墨色长锋顺着锁链方向扎进目标（笔锋收尖、按笔处鼓、边缘 1 格亮线），笔锋处炸开一摊不规整的墨，往前甩出几道粗细不一的墨勾和墨点；
//       笔画随后从笔尾干涸回缩、飞白变多。
// lock：三四道勾笔从目标四周扫进来收紧（弧心、半径、长短都不同，不闭合、不同心），收紧那一下笔锋白热。
// 分档（docs/91 逻各斯）：E0 只有主笔；E1「剜魂」加一道斜穿目标的淡紫剜刻笔（撇 + 回勾，留得最久）；
// E2「连缀」质变：主笔变成两股绞合（一股紫），扎入处抽出 2–3 道往两侧卷开的长墨丝、丝梢紫色，白热大光晕。
import { Particles, Lights, P, Rng, fit, hex, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos synecdoche unleashed",
  desc: "A dry-brush ink stroke stabs into the locked target and dries back, with an ink splash flicking forward; on lock, hooked brush strokes sweep in and tighten. Elite tiers add a carved cross-stroke and curling ink filaments.",
  tags: ["arcane", "ink", "brush", "stab", "lock", "one-shot"],
  size: [200, 150],
  origin: [125, 75],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#0b0d22", ...OP.logos],
    accent: "#b98cff",   // E2 专属重点（紫，避开危险色 #ff2667、敌弹青 #33ceff、结晶暖金）
    move: "tick",        // tick / lock
    elite: 2,
    quick: 0,            // 1 = 队友版（余韵减半）
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0, mv = o.move || "tick";
  const core = o.layer !== "deco", deco = o.layer !== "core", ACC = hex(o.accent), ACCD = hex("#6a4cb0");
  // 分档（docs/242 §10）：DL 余韵、GK 光晕、PM 颗粒量
  const DL = [0.45, 0.7, 1][el] * (quick ? 0.5 : 1), GK = [0.22, 0.4, 0.6][el], PM = [0.6, 0.85, 1.2][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[3] }), lights = new Lights();
  let t = 0;

  // 毛笔：沿 path(u) 从 u0 画到 u1，半宽 W，按笔压起伏；dry 0..1 飞白（沿笔向的断丝），col(v, edge) 返回颜色
  function brush(p, path, u0, u1, W, dry, sn, col) {
    if (u1 - u0 < 0.01) return;
    const [ax, ay] = path(u0), [bx, by] = path(u1), len = Math.hypot(bx - ax, by - ay) + 1, du = (u1 - u0) / (len * 2.2);
    for (let u = u0; u <= u1; u += du) {
      const v = (u - u0) / (u1 - u0), [x, y] = path(u), [x2, y2] = path(u + du);
      const w = W * Math.pow(Math.sin(Math.PI * clamp(v * 0.9 + 0.06)), 0.55) * (1.25 - 0.5 * v) * (0.85 + 0.25 * noise(u * 9, sn));   // 起笔按重、收笔出尖
      if (w < 0.35) continue;
      let nx = -(y2 - y), ny = x2 - x;
      const nl = Math.hypot(nx, ny) || 1;
      nx /= nl; ny /= nl;
      for (let q = -w; q <= w; q += 0.5) {
        const edge = Math.abs(q) > w - 0.6, hair = Math.round((q + w) * 1.4);
        if (!edge && dry > 0 && noise2(u * len * 0.35, hair * 1.7, sn) > 1 - dry * 1.6 * (1 - v * 0.6)) continue;   // 飞白：笔尾一侧断丝多
        const c = col(v, edge);
        if (c) p.px(x + nx * q, y + ny * q, c);
      }
    }
  }
  const pick = (i) => C[clamp(Math.round(i), 0, 7)];

  // ---------------- tick：长锋扎入
  const L = [46, 52, 60][el], W = [2.6, 2.9, 3.2][el], IN = 0.06;   // 笔长、按笔处半宽（1x）、扎入时长
  const bend = Rg.range(-0.1, 0.1) * L;
  const strands = el >= 2 ? [{ ph: 0, a: 1.0, w: 0.72 }, { ph: Math.PI, a: 0, w: 0.55 }] : [{ ph: 0, a: 0, w: 1 }];   // E2 两股绞合，第二股紫
  const mainPath = (s) => (u) => [-L + u * (L + 8), Math.sin(u * Math.PI) * bend + (strands.length > 1 ? Math.sin(u * 7 + s.ph) * 2.2 * u : 0)];
  // 笔锋处一摊墨（不规整，往前鼓）
  const blotR = [5, 6, 7.5][el];
  // 往前甩的墨勾：角度、长短、粗细、先后都随机（不等距）
  const flicks = [];
  for (let i = 0, n = Rg.int(3, 4) + (el > 0 ? 1 : 0); i < n; i++)
    flicks.push({ a: Rg.range(-1.0, 1.0), L: Rg.range(9, 17) * (1 + el * 0.12), curl: Rg.range(-0.7, 0.7), w: Rg.range(1.1, 1.8), d: Rg.range(0, 0.03), sn: Rg.int(1, 999) });
  // E1 剜刻：斜穿目标的一笔（撇 + 回勾）
  const cs = Rg.chance(0.5) ? 1 : -1;
  const carve = { a: cs * Rg.range(1.05, 1.3), L: Rg.range(24, 28), hook: -cs * Rg.range(0.9, 1.3), d: 0.08 };
  const carvePath = (u) => {
    const ca = Math.cos(carve.a), sa = Math.sin(carve.a), s = (u - 0.5) * carve.L;
    let x = ca * s, y = sa * s;
    if (u > 0.82) { const k = (u - 0.82) / 0.18, ha = carve.a + carve.hook * k; x += Math.cos(ha) * k * 3; y += Math.sin(ha) * k * 3; }   // 回勾
    return [x, y];
  };
  // E2 连缀墨丝：从扎入点抽出、往两侧卷开
  const fils = [];
  if (el >= 2) for (let i = 0, n = Rg.int(2, 3); i < n; i++) {
    const side = i % 2 ? 1 : -1;
    fils.push({ a: side * Rg.range(0.8, 1.6), L: Rg.range(36, 48), curl: side * Rg.range(1.6, 2.4), d: Rg.range(0.0, 0.05), sn: Rg.int(1, 999) });
  }
  const curlPath = (a, Lc, curl, k) => (u) => {   // 积分一条卷曲线（解析近似：角度随 u 线性 + 噪声）
    let x = 0, y = 0, ang = a;
    const n = Math.max(1, Math.round(u * 24));
    for (let i = 0; i < n; i++) { ang += (curl * k) / 24 * (1.3 - 1.25 * i / 24) + 0.05 * noise(i * 0.4, Lc); x += Math.cos(ang) * (Lc * k / 24); y += Math.sin(ang) * (Lc * k / 24); }   // 先卷后回（S 形笔势，不成圆弧）
    return [x, y];
  };

  // ---------------- lock：勾笔收紧
  const hooks = [];
  if (mv === "lock") {
    const n = [3, 3, 4][el];
    let a = Rg.range(0, TAU);
    for (let i = 0; i < n; i++) {
      a += Rg.range(1.2, 2.2);
      const oa = Rg.range(0, TAU), od = Rg.range(2, 6);
      hooks.push({ a0: a, sp: Rg.range(1.5, 2.3) * (i % 2 ? 1 : -1), R: Rg.range(24, 38), ox: Math.cos(oa) * od, oy: Math.sin(oa) * od, d: i * Rg.range(0.015, 0.035), w: Rg.range(2.0, 2.8), sn: Rg.int(1, 999) });
    }
  }
  const LT = 0.16;
  const HIT = mv === "lock" ? LT : IN;

  let burst = false;
  return {
    update(dt) {
      t += dt;
      if (!burst && t >= HIT) {
        burst = true;
        if (deco) {
          lights.add(2, 0, [14, 20, 28][el], C[6], GK * 1.5, 0.15 + 0.1 * el);
          for (let i = 0, n = Math.round(18 * PM); i < n; i++) {   // 墨点：往前成团甩出（锁定时往四周）
            const a = mv === "lock" ? Rg.range(0, TAU) : Rg.range(-1.1, 1.1), sp = Rg.range(40, 160);
            ps.spawn(i % 4 ? P.MOTE : P.SPARK, 3, 0, Math.cos(a) * sp, Math.sin(a) * sp - Rg.range(0, 25), Rg.range(0.25, 0.6) * DL + 0.1,
              i % 3 ? C[4 + Rg.int(0, 2)] : C[2], Rg.range(0.6, 1.2));
          }
          for (let i = 0, n = Math.round(3 * PM); i < n; i++)   // 墨雾
            ps.spawn(P.VAPOUR, Rg.range(-6, 8), Rg.range(-4, 4), Rg.range(5, 25), Rg.range(-12, -2), Rg.range(0.35, 0.7) * DL + 0.1, C[2], Rg.range(3, 6));
          if (el >= 2) for (let i = 0; i < 10; i++) {   // E2：紫色细光点顺墨丝飘
            const f = fils[i % fils.length];
            ps.spawn(P.STAR, 0, 0, Math.cos(f.a) * Rg.range(30, 80), Math.sin(f.a) * Rg.range(30, 80) - 8, Rg.range(0.4, 0.8) * DL, ACC, Rg.range(0.8, 1.2), Rg.range(0, 0.12));
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (!deco) return;
      // 光晕（装饰层）：顺笔画拉长 + 扎入点，E0 克制、E2 白热大光晕
      const k = smooth(HIT - 0.05, HIT, t) * (1 - smooth(HIT, HIT + 0.4 * DL, t));
      if (k > 0) {
        if (mv === "tick") p.glowLine(-L * 0.6, 0, 6, 0, [7, 10, 14][el], C[4], GK * k * 0.6);
        p.glow(2, 0, [10, 15, 24][el], el >= 2 ? C[5] : C[4], GK * k);
      }
      // 墨摊内部的半透明填充（装饰层）
      if (mv === "tick" && t >= IN) {
        const u = t - IN, gr = ease.outQuart(clamp(u / 0.05)), fade = smooth(0.04, 0.05 + 0.3 * DL, u);
        if (fade < 1) p.shade(-8, -14, 16, 14, (x, y, out) => {
          const r = Math.hypot(x - 2, y), a = Math.atan2(y, x - 2);
          const R = blotR * gr * (1 + 0.45 * Math.max(0, Math.cos(a)) + 0.3 * noise(a * 3 + 5, o.seed));
          if (r > R - 1) return;
          out.c = C[2]; out.a = 0.55 * (1 - fade);
        });
      }
      ps.draw(p, "back");
    },
    draw(p) {
      if (core && mv === "tick") {
        const head = ease.outExpo(clamp(t / IN)), dry = smooth(IN + 0.03, IN + 0.06 + 0.3 * DL, t);   // 干涸：笔尾往笔锋回缩
        const hot = t < IN + 0.03 ? 2 : t < IN + 0.09 ? 1 : 0;   // 白热只在扎入那 1–2 帧（docs/242 §9.3）
        for (const s of strands) {
          const path = mainPath(s);
          brush(p, path, Math.min(dry, head), head, W * s.w * (1 - dry * 0.35), 0.15 + dry * 0.5, 11 + s.ph, (v, edge) => {
            if (s.a && !edge) return v > 0.4 ? ACC : ACCD;
            if (edge) return hot >= 2 ? C[7] : hot ? C[6] : C[5];
            return pick(1.5 + v * 2.2 + hot * 1.5 - dry * 1.5);
          });
        }
        // 笔锋处的墨摊边缘 + 墨勾（核心 = 命中主形，和笔锋连成一片）
        if (t >= IN) {
          const u = t - IN, gr = ease.outQuart(clamp(u / 0.05)), fade = smooth(0.04, 0.05 + 0.3 * DL, u);
          if (fade < 1) p.shade(-8, -14, 16, 14, (x, y, out) => {
            const r = Math.hypot(x - 2, y), a = Math.atan2(y, x - 2);
            const R = blotR * gr * (1 + 0.45 * Math.max(0, Math.cos(a)) + 0.3 * noise(a * 3 + 5, o.seed));
            if (r > R || r < R - 1.2 || noise2(a * 6, u * 20, o.seed) < fade * 2 - 1) return;   // 只画边缘，随时间碎开
            out.c = u < 0.04 ? C[7] : pick(5 - fade * 3);
            out.a = 1;
          });
          for (const f of flicks) {
            const uu = u - f.d;
            if (uu <= 0) continue;
            const k = ease.outQuart(clamp(uu / 0.06)), ff = smooth(0.05, 0.06 + 0.25 * DL, uu);
            if (ff >= 1) continue;
            const path = curlPath(f.a, f.L, f.curl, k), off = (u) => { const [x, y] = path(u); return [x + 3, y]; };
            brush(p, off, ff * 0.8, 1, f.w, 0.2 + ff * 0.6, f.sn, (v, edge) => edge ? (uu < 0.04 ? C[7] : C[5]) : pick(2 + v * 2.5 - ff * 2));
          }
        }
        // E1 剜刻：淡紫亮笔斜穿目标，留得比主笔久
        if (el >= 1 && t > carve.d) {
          const u = t - carve.d, k = ease.outExpo(clamp(u / 0.05)), fade = smooth(0.18, 0.18 + 0.45 * DL, u);
          if (fade < 1) brush(p, carvePath, fade * 0.9, k, 2.3 * (1 - fade * 0.3), 0.1 + fade * 0.6, 77, (v, edge) =>
            edge ? (u < 0.08 ? C[7] : pick(6 - fade * 2)) : pick(4.5 + v * 1.2 - fade * 2.5));
        }
        // E2 连缀墨丝：往两侧卷开，丝梢紫
        for (const f of fils) {
          const u = t - IN - f.d;
          if (u <= 0) continue;
          const k = ease.outCubic(clamp(u / 0.12)), fade = smooth(0.14, 0.14 + 0.45 * DL, u);
          if (fade >= 1) continue;
          brush(p, curlPath(f.a, f.L, f.curl, k), fade * 0.85, 1, 1.9, fade * 0.5, f.sn, (v, edge) =>
            v > 0.65 ? ACC : pick(4 - fade * 2));   // 墨丝一色到底（亮暗交替会看成虚线），丝梢紫
        }
      }
      if (core && mv === "lock") {
        for (const h of hooks) {
          const u = t - h.d;
          if (u <= 0) continue;
          const k = ease.inOutCubic(clamp(u / LT)), R = h.R * (1 - 0.35 * k) + 4, fade = smooth(LT + 0.04, LT + 0.06 + 0.3 * DL, u);
          if (fade >= 1) continue;
          const len = Math.abs(h.sp) * Math.min(1, u / 0.06), dir = Math.sign(h.sp), hot = Math.abs(u - LT) < 0.04 ? 2 : 0;
          const path = (s) => {   // 勾笔：沿弧扫、尾端往外翻（不是正圆）
            const a = h.a0 + dir * (s * len + k * 1.6), rr = R * (1 - 0.92 * s * k) + noise(a * 2 + h.R, h.sn) * 2 * (1 - s * k);   // 螺旋往里收：笔锋扎到目标身上，不收成圈
            return [h.ox * (1 - k) + Math.cos(a) * rr, h.oy * (1 - k) + Math.sin(a) * rr * 0.8];
          };
          brush(p, path, fade * 0.9, 1, h.w * (1 - fade * 0.3), 0.15 + fade * 0.6, h.sn, (v, edge) => edge ? (hot ? C[7] : C[5]) : pick(1.5 + v * 2.5 + hot - fade * 1.5));
        }
        if (el >= 1 && t > LT) {   // E1+ 锁定收紧后同样剜一笔
          const u = t - LT, k = ease.outExpo(clamp(u / 0.05)), fade = smooth(0.18, 0.18 + 0.45 * DL, u);
          if (fade < 1) brush(p, carvePath, fade * 0.9, k, 2.3 * (1 - fade * 0.3), 0.1 + fade * 0.6, 77, (v, edge) =>
            edge ? (u < 0.08 ? C[7] : pick(6 - fade * 2)) : pick(4.5 + v * 1.2 - fade * 2.5));
        }
        if (el >= 2) for (const f of fils) {   // E2 锁定时同样抽出连缀墨丝
          const u = t - LT - f.d;
          if (u <= 0) continue;
          const k = ease.outCubic(clamp(u / 0.12)), fade = smooth(0.14, 0.14 + 0.45 * DL, u);
          if (fade < 1) brush(p, curlPath(f.a, f.L, f.curl, k), fade * 0.85, 1, 1.9, fade * 0.5, f.sn, (v, edge) =>
            v > 0.65 ? ACC : pick(4 - fade * 2));   // 墨丝一色到底（亮暗交替会看成虚线），丝梢紫
        }
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
