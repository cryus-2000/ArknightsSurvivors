// 水月伞击 / 唤醒（claude/pixelfx-ul-mizuki-claude，开关 fx/px_unleashed）：俯视，原点 = 水月，正右为出手方向。
// 原作参照（build/ark_ref/mizuki，还原见 Claude outputs/pixelfx_ul_mizuki/ref/）：
//   普攻 attack_01_start：伞挥出一串水泡沿挥线溅开；hit：水冠爆开 + 暗底。
//   S1 唤醒 skill_01_start：地面紫暗，身边钻出两三根青绿身紫红尖的触手（mizuki_04 / 06）往前甩，落点水花；start_03 一道刀光。
// 本作：
//   basic：伞沿膜冠（新月，外缘一圈不等距小褶，像水母伞缘）+ 沿缘甩水珠；克制。
//   s1：膜冠放大一档 + 触手从身后地里钻出、抬高、越过她甩砸到弧上，落点水冠（主形 = 触手，和普攻一眼分开，docs/242 §12.1）。
//   elite（docs/91 §9，§10）：E0 只有主形；E1 = 精一「拖拽」：伞缘垂下丝须（basic）/ 触手尖卷钩（s1）；
//         E2 = 精二「深蓝之籽」：缘上浮起淡紫荧光籽（basic）/ 三根触手带荧光斑、落点淡紫重点（s1），白热首帧。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise, hex } from "../../core/index.js";
import { MZ, tentacle, membrane, threads } from "../water/mizuki-lib.js";

export const meta = {
  name: "Mizuki umbrella unleashed",
  desc: "Top-down umbrella sweep with a jellyfish-bell rim; the empowered swing has tentacles burst from the ground and whip down onto the arc.",
  tags: ["melee", "umbrella", "tentacle", "water", "topdown", "one-shot"],
  size: [260, 260],
  origin: [130, 130],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: MZ.blue,
    radius: 80,
    span: 2.62,       // 判定 2*half_base（150°），导出时由 judge 传
    move: "basic",    // basic / s1
    elite: 2,
    quick: 0,         // 1 = 队友版（余韵减半）
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), quick = +o.quick > 0, mv = o.move || "basic";
  const el = clamp(Math.round(+o.elite), 0, 2), core = o.layer !== "deco", deco = o.layer !== "core";
  const DL = [0.45, 0.75, 1][el] * (quick ? 0.5 : 1), GK = [0.45, 0.8, 1][el], PM = [0.6, 0.85, 1][el], HOT = [0.6, 1.4, 2.6][el];
  const s1 = mv === "s1", s3 = mv === "s3";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[5]], haze: C[4] }), lights = new Lights();
  const R0 = o.radius, span = s3 ? TAU * 0.98 : o.span, a0 = -span / 2, a1 = span / 2, SW = s1 ? 0.08 : 0.07;
  const M = { seed: o.seed, R: R0, W: (s3 ? 9 : s1 ? 6 : 13) * [0.8, 1, 1.15][el], ramp: C, GK, scal: [2.4, 3.6, 4.2][el], lav: el >= 2 ? hex(MZ.lav) : 0 };   // 伞缘小褶随档加深；精二外缘断续淡紫
  const LAV = hex(MZ.lav);
  let t = 0.02, passed = 0, landed = false;

  // basic E1+：伞缘垂下的丝须（不等距，3–5 根），E2 加荧光籽
  const ths = [];
  if (!s1 && !s3 && el >= 1) for (let u = Rg.range(0.06, 0.16); u < 0.94; u += Rg.range(0.11, 0.2)) {
    const a = a0 + span * u, x = Math.cos(a) * (R0 - 2), y = Math.sin(a) * (R0 - 2), d = Rg.range(-0.6, 0.6);
    ths.push({ x, y, dx: Math.cos(a + Math.PI + d) * 0.5 + 0.2, dy: Math.sin(a + Math.PI + d) * 0.5 + 0.8, len: Rg.range(16, 26) * [1, 1, 1.3][el], ph: Rg.range(0, TAU),
      t0: SW * u, t1: (0.32 + 0.28 * DL) + Rg.range(-0.05, 0.05) });
  }
  // s1：触手（E0 1 / E1 2 / E2 3），根在身后两侧地里，砸在弧上不等距的几处
  const tens = [];
  if (s1) {
    const n = [1, 2, 3][el], hits = n === 1 ? [Rg.range(-0.15, 0.15)] : n === 2 ? [Rg.range(-0.62, -0.38), Rg.range(0.3, 0.6)] : [Rg.range(-0.7, -0.5), Rg.range(-0.1, 0.12), Rg.range(0.45, 0.68)];
    for (let i = 0; i < n; i++) {
      const ha = hits[i] * span / 2 * 1.6, side = ha < 0 ? -1 : 1;
      const ba = Math.PI - side * Rg.range(0.75, 1.25) + (n === 3 && i === 1 ? -side * 0.9 : 0), bd = R0 * Rg.range(0.34, 0.48);   // 根分到身后两侧
      const tr = R0 * Rg.range(0.78, 0.95);
      tens.push({ base: [Math.cos(ba) * bd, Math.sin(ba) * bd], hit: [Math.cos(ha) * tr, Math.sin(ha) * tr], ha, side, w0: Rg.range(4.6, 5.4) * [0.9, 1, 1.1][el], wig: Rg.range(0.5, 1) * (Rg.chance(0.5) ? 1 : -1),
        t0: i * 0.025 + Rg.range(0, 0.012), up: R0 * Rg.range(0.7, 0.9), seed: o.seed + 17 * i, curl: el >= 1 && i === n - 1 ? 1 : 0, slammed: false });
    }
  }
  if (s3) {   // 镜花水月（精二才有，只做 E2）：身边五六根触手往四周甩砸，角度抖动、远近不一（不等距放射，§1）
    const n = Rg.int(5, 6), ang0 = Rg.range(0, TAU);
    for (let i = 0; i < n; i++) {
      const ha = ang0 + (i + Rg.range(-0.3, 0.3)) * TAU / n, side = Rg.chance(0.5) ? 1 : -1, bd = R0 * Rg.range(0.3, 0.42), tr = R0 * Rg.range(0.78, 0.96);
      const ba = ha + side * Rg.range(0.5, 0.9);   // 根在同一方向偏一侧、离身一段（不挤在脚下）
      tens.push({ base: [Math.cos(ba) * bd, Math.sin(ba) * bd], hit: [Math.cos(ha) * tr, Math.sin(ha) * tr], ha, side, w0: Rg.range(4.4, 5.4), wig: Rg.range(0.5, 1) * (Rg.chance(0.5) ? 1 : -1),
        t0: Rg.range(0, 0.07), up: R0 * Rg.range(0.5, 0.7), seed: o.seed + 17 * i, curl: Rg.chance(0.35) ? 1 : 0, slammed: false });
    }
  }
  const TE = 0.05, TS = 0.05;   // 触手钻出 / 甩砸时长
  function tentPose(tn, u) {   // u = t - tn.t0 → [base, ctrl, tip, from, to]
    const b = tn.base, h = tn.hit;
    if (u < TE) {   // 钻出：尖从根往上抬
      const k = ease.outCubic(clamp(u / TE));
      const tip = [b[0] + (h[0] - b[0]) * 0.2, b[1] - tn.up * k];
      return [b, [b[0], b[1] - tn.up * 0.5 * k], tip, 0, 1];
    }
    const k = ease.inCubic(clamp((u - TE) / TS));   // 越过头顶甩砸到弧上
    const lift = [b[0] + (h[0] - b[0]) * 0.2, b[1] - tn.up];
    const tip = [lift[0] + (h[0] - lift[0]) * k, lift[1] + (h[1] - lift[1]) * k];
    const ctrl = [b[0] + (tip[0] - b[0]) * 0.25 - tn.side * 6, Math.min(b[1], tip[1]) - tn.up * (1.0 - 0.35 * k)];
    const c2 = [b[0] + (tip[0] - b[0]) * 0.7 + tn.wig * 10, Math.min(b[1], tip[1]) - tn.up * (0.55 - 0.3 * k) + tn.wig * 8];   // 三次贝塞尔第二控制点：身子扭成 S 形
    return [b, ctrl, tip, 0, 1, c2];
  }
  function splash(x, y, nx, ny, n, sp, life, acc) {   // 落点水冠：顺冲击方向张开的不规整一簇
    for (let k = 0; k < n; k++) {
      const v = sp * Rg.range(0.45, 1.2), a = Math.atan2(ny, nx) + Rg.range(-0.9, 0.9);
      ps.spawn(k % 3 ? P.MOTE : P.SPARK, x, y, Math.cos(a) * v, Math.sin(a) * v - Rg.range(30, 90), life * Rg.range(0.6, 1.1), acc && k % 4 === 0 ? MZ.lav : C[5 + Rg.int(0, 2)], Rg.range(0.6, 1.1));
    }
  }

  return {
    update(dt) {
      t += dt;
      const head = ease.outExpo(clamp(t / SW));
      while (passed < head && passed < 1) {   // 沿缘甩水珠：步长随机（不等距放射）
        const a = a0 + span * passed, x = Math.cos(a) * (R0 - Rg.range(0, 4)), y = Math.sin(a) * (R0 - Rg.range(0, 4));
        const tx = -Math.sin(a), ty = Math.cos(a), nx = Math.cos(a), ny = Math.sin(a);
        for (let k = 0, m = Math.round((s1 ? 1.5 : 1) * PM + Rg.range(-0.45, 0.45)); k < m; k++) {   // 数量砍半（组长 C v1 #4）
          const sp = Rg.range(70, 220), j = Rg.range(-0.45, 0.45) * (s3 ? 2.4 : 1),   // 整圈时方向抖得更开（不成放射纹，§9.3）
             cj = Math.cos(j), sj = Math.sin(j), vx = tx * 0.95 + nx * 0.35, vy = ty * 0.95 + ny * 0.35;   // 顺挥击方向甩（组长 C v1 #4）   // 方向再抖一点（不排成放射纹，§9.3）
          ps.spawn(P.MOTE, x, y, (vx * cj - vy * sj) * sp, (vx * sj + vy * cj) * sp, Rg.range(0.22, 0.5) * (0.6 + 0.4 * DL), C[5 + Rg.int(0, 1)], Rg.range(0.6, 1.0));
        }
        if (deco && Rg.chance(0.15)) ps.spawn(P.VAPOUR, x + nx * 4, y + ny * 4, nx * 35 + tx * 20, ny * 35 + ty * 20, Rg.range(0.2, 0.35) * DL, C[3], Rg.range(1.2, 2));   // 水雾小而少（大了成孤立圆斑，§12.3）
        passed += 0.04 * Rg.range(0.4, 1.8);
      }
      if (!landed && t >= SW) {
        landed = true;
        if (deco) lights.add(Math.cos(a1) * R0 * 0.8, Math.sin(a1) * R0 * 0.8, 40, C[5], 0.7 * GK, 0.3);
        for (let a = a0 + 0.08; a < a1; a += Rg.range(0.1, 0.24) / PM) {   // 余韵：缘上碎成水雾 / 荧光籽
          const x = Math.cos(a) * (R0 + Rg.range(-2, 4)), y = Math.sin(a) * (R0 + Rg.range(-2, 4)), nx = Math.cos(a), ny = Math.sin(a);
          if (deco && Rg.chance(0.6)) ps.spawn(P.MOTE, x, y, nx * Rg.range(10, 40), ny * Rg.range(10, 40) - 10, Rg.range(0.3, 0.6) * DL, C[4 + Rg.int(0, 1)], Rg.range(0.5, 0.8), Rg.range(0, 0.08));
          if (el >= 2 && Rg.chance(0.35)) ps.spawn(P.STAR, x, y, nx * 6, ny * 6 - Rg.range(12, 26), Rg.range(0.4, 0.75) * DL, Rg.chance(0.5) ? MZ.lav : C[6], Rg.range(0.8, 1.4), Rg.range(0.03, 0.2));
        }
      }
      for (const tn of tens) if (!tn.slammed && t - tn.t0 >= TE + TS) {
        tn.slammed = true;
        const [hx, hy] = tn.hit, L = Math.hypot(hx, hy) || 1;
        splash(hx, hy, hx / L, hy / L, Math.round(14 * PM), 180, 0.55 * (0.6 + 0.4 * DL), el >= 2);
        if (deco) { lights.add(hx, hy, 34, el >= 2 ? MZ.lav : C[5], 0.8 * GK, 0.25); ps.spawn(P.VAPOUR, hx, hy, hx / L * 30, hy / L * 30, 0.35 * DL, C[3], 2.5); }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (deco && s1 && t < 0.75) {   // 唤醒起手：脚下到身前铺开一片细碎的紫暗地面（原作 skill_01_start 的 ground_ab / kirara 暗底；稀疏散点，不铺实块）
        const k = smooth(0, 0.08, t) * (1 - smooth(0.4, 0.75, t)), G = R0 * 0.95, dk = hex("#1c1648"), dv = hex("#2e2470");
        if (k > 0) p.shade(-G * 0.45, -G, G, G, (x, y, out) => {
          const r = Math.hypot(x * 0.8 + G * 0.1, y), a = Math.atan2(y, x);
          const lim = G * (0.55 + 0.25 * noise(a * 2.2, o.seed + 71) + 0.12 * noise(a * 7, o.seed + 73)) * (0.6 + 0.4 * smooth(0, 0.2, t));
          if (r > lim) return;
          const n = noise(x * 0.18, y * 0.18 + o.seed) + 0.5 * noise(x * 0.5 + 7, y * 0.5 - 3);
          const h = ((x * 73856093) ^ (y * 19349663)) & 7;   // 位置哈希：细碎散点
          if (n < 0.15 || h > 2 + Math.round(2 * k)) return;
          out.c = n > 0.6 ? dv : dk; out.a = 0.55 * k * (1 - r / lim * 0.5);
        });
      }
      if (core && tens.length && t < 0.5) {   // 触手根部：地面一小片暗洞（压扁、外缘噪声，不是圆）
        for (const tn of tens) {
          const k = smooth(0, 0.04, t - tn.t0) * (1 - smooth(0.3, 0.5, t)), [bx, by] = tn.base, L = 6 + tn.w0;
          if (k <= 0) continue;
          p.shade(bx - L * 1.6, by - L, bx + L * 1.6, by + L, (x, y, out) => {
            const dx = (x - bx) / 1.6, dy = y - by, a = Math.atan2(dy, dx), r = Math.hypot(dx, dy);
            if (r > L * (0.55 + 0.35 * noise(a * 3, tn.seed + 41) + 0.15 * noise(a * 9, tn.seed + 43)) * k) return;
            out.c = hex(MZ.ink); out.a = 0.6;
          });
        }
      }
    },
    draw(p) {
      // 膜冠
      {
        const u = t, head = ease.outExpo(clamp(u / SW)), hold = s1 ? 0.08 : 0.05, trail = (s1 ? 0.42 : 0.32) * (0.6 + 0.4 * DL);
        const tail = smooth(SW + hold, SW + hold + trail, u), age = clamp(u / (SW + hold + trail));
        const hot = u < 0.09 ? HOT : u < 0.14 ? 0.3 : 0;
        if (tail < 1) membrane(p, M, a0 + span * tail, span * (head - tail), age, hot, core, deco);
      }
      if (core) threads(p, ths, t, C[6]);
      if (core && el >= 2) for (const th of ths) if (t > th.t0 + 0.06 && t < th.t1) {   // E2：丝须末端一颗淡紫荧光籽
        const k = 1 - smooth(th.t1 - 0.15, th.t1, t), x = th.x + th.dx * th.len, y = th.y + th.dy * th.len - (t - th.t0) * 8;
        if (k > 0.1) { p.px(x, y, LAV); p.px(x + 1, y, LAV); p.px(x, y - 1, C[7]); p.px(x + 1, y + 1, C[6]); if (deco) p.glow(x, y, 7, LAV, 0.35 * k); }
      }
      // 触手：先全部描边、再全部画身（几根交叠处不出条纹）
      for (const pass of ["ink", "body"]) for (const tn of tens) {
        const u = t - tn.t0;
        if (u < 0) continue;
        const [b, c, tip, , , c2] = tentPose(tn, u);
        const end = TE + TS, hold = 0.12 * (0.6 + 0.4 * DL), out = 0.28 * (0.5 + 0.5 * DL);
        const back = ease.inCubic(smooth(end + hold, end + hold + out, u));   // 收尾：从尖往根缩回地里（不碎成块）
        if (back >= 0.8) continue;   // 缩到只剩根部一截就收掉（不留方块残桩）
        const hot = u > end && u < end + 0.05 ? HOT * 0.5 : 0;
        tentacle(p, b, c, tip, 0, 1 - back, { c2, w0: tn.w0, seed: tn.seed, el, hot, dis: 0, curl: tn.curl * smooth(end, end + 0.08, u) * (1 - back), cs: tn.side, glowK: GK, pass }, core, deco && pass === "body");
        if (pass === "body" && core && el >= 2 && u > end && u < end + 0.2) {   // E2 落点淡紫重点：沿冲击方向拉长的不规整水冠
          const [hx, hy] = tn.hit, L = Math.hypot(hx, hy) || 1, k = 1 - smooth(end + 0.06, end + 0.2, u), nx = hx / L, ny = hy / L;
          for (let a = -1.1; a <= 1.1; a += 0.09) {
            const len = (5 + 7 * Math.max(0, noise(a * 3, tn.seed + 61))) * k * (1 - Math.abs(a) / 1.3);
            const da = Math.atan2(ny, nx) + a;
            for (let d = 1; d < len; d += 0.7) p.px(hx + Math.cos(da) * d, hy + Math.sin(da) * d - d * 0.3, d > len - 1.5 ? LAV : C[5]);
          }
        }
      }
      if (deco && t < 0.3) {
        const a = a0 + span * ease.outExpo(clamp(t / SW));
        p.glow(Math.cos(a) * (R0 - 5), Math.sin(a) * (R0 - 5), (s1 ? 60 : 44) * [0.6, 0.85, 1][el], C[5], 0.55 * GK * (1 - t / 0.3));
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
