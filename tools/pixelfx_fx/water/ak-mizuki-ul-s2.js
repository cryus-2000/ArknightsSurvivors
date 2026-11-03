// 水月 S2「囚徒困境」（claude/pixelfx-ul-mizuki-claude，开关 fx/px_unleashed）：俯视，原点 = 水月脚底。
// 原作参照（build/ark_ref/mizuki）：skill_02_start = 地面暗影 + 几根细触须（mizuki_09）从地里钻出 + 一闪 + 黑粒子上飘；
//   skill_02_buff = 身后两条随动作摆动的触手（mizuki_10）+ 暗烟；skill_02_buff_02 = 被控制的敌人身上小触须缠绕。
// 颜色按用户 11-04：立绘宝蓝 → 淡紫。不画往外扩散的光环（用户 11-04 通用规则）。
// move：cast（开技一次性）/ aura（持续期间循环，身后两条触手）/ bind（被束缚敌人脚下循环的小触须）。
// S2 精一解锁：只做 E1 / E2。E2 = 精二「深蓝之籽」：触手身上淡紫荧光斑、开技多一根触手、尖端淡紫。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise, hex } from "../../core/index.js";
import { MZ, tentacle } from "./mizuki-lib.js";

export const meta = {
  name: "Mizuki prisoner's dilemma unleashed",
  desc: "Cast: thin tendrils burst from a speckled dark patch; aura: two tentacles sway behind her; bind: a small tendril coils round a held enemy.",
  tags: ["tentacle", "buff", "status", "topdown"],
  size: [240, 200],
  origin: [120, 130],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: MZ.blue, elite: 2, quick: 0, move: "cast", big: 0, layer: "all", seed: 9 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 1, 2), mv = o.move || "cast";
  const core = o.layer !== "deco", deco = o.layer !== "core", quick = +o.quick > 0, DL = [0.45, 0.75, 1][el] * (quick ? 0.5 : 1), GK = [0.45, 0.8, 1][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]], haze: C[4] }), lights = new Lights();
  const LAV = hex(MZ.lav), INKV = "#241a52";
  let t = 0.02, flashed = false;
  const LOOP = mv === "aura" || mv === "s3aura" ? 1.2 : mv === "bind" ? 0.8 : mv === "charge" ? 1.0 : 0;

  // cast：触须（E1 4 根 / E2 5 根），角度抖动、远近不一
  const ten = [];
  if (mv === "cast") {
    const big = +o.big > 0, n = big ? 7 : el >= 2 ? 5 : 4, a0 = Rg.range(0, TAU);   // big = S3 镜花水月起手（原作 skill_03_start 九根触手放射）：根数多、离身远、更高更粗
    for (let i = 0; i < n; i++) {
      const a = a0 + (i + Rg.range(-0.3, 0.3)) * TAU / n, d = big ? Rg.range(40, 74) : Rg.range(26, 46);
      ten.push({ b: [Math.cos(a) * d, Math.sin(a) * d * 0.55], lean: Math.cos(a) * Rg.range(6, 12) * (big ? 1.8 : 1), up: Rg.range(30, 44) * (big ? 1.35 : 1), w0: Rg.range(2.6, 3.2) * (big ? 1.3 : 1), t0: Rg.range(0, 0.08), ph: Rg.range(0, TAU), seed: o.seed + 13 * i });
    }
  }
  // aura：身后左右两条
  const aur = mv === "aura" ? [{ b: [-11, -3], s: -1, up: 44, w0: 3.6, seed: o.seed + 3, ph: 0 }, { b: [12, -5], s: 1, up: 38, w0: 3.2, seed: o.seed + 7, ph: 2.1 }] : [];

  return {
    update(dt) {
      t += dt;
      if (mv === "cast" && !flashed && t >= 0.06) {
        flashed = true;
        if (deco) lights.add(0, -16, 46, el >= 2 ? MZ.lav : C[5], 0.8 * GK, 0.3);
        for (let k = 0; k < 26; k++) {   // 黑粒子上飘（原作 lizi_hei）：不等距、往上
          const x = Rg.range(-50, 50), y = Rg.range(-14, 14);
          ps.spawn(P.MOTE, x, y, Rg.range(-8, 8), -Rg.range(20, 60), Rg.range(0.5, 0.9) * DL, k % 5 === 0 ? (el >= 2 ? MZ.lav : C[5]) : INKV, Rg.range(0.7, 1.2), Rg.range(0, 0.25));
        }
      }
      if (mv === "aura" && deco && Rg.chance(0.25)) ps.spawn(P.MOTE, Rg.range(-16, 16), Rg.range(-30, -6), Rg.range(-4, 4), -Rg.range(10, 24), Rg.range(0.4, 0.7), Rg.chance(0.3) ? (el >= 2 ? MZ.lav : C[5]) : INKV, 0.8);
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (deco && mv === "cast" && t < 0.9) {   // 开技：一片细碎暗地（散点，不铺实块）
        const k = smooth(0, 0.1, t) * (1 - smooth(0.5, 0.9, t)), G = +o.big > 0 ? 100 : 70, dk = hex("#1c1648"), dv = hex("#2e2470");
        if (k > 0) p.shade(-G, -G * 0.6, G, G * 0.6, (x, y, out) => {
          const r = Math.hypot(x, y / 0.55), a = Math.atan2(y / 0.55, x), lim = G * (0.6 + 0.25 * noise(a * 2.4, o.seed + 71) + 0.12 * noise(a * 7, o.seed + 73)) * (0.5 + 0.5 * smooth(0, 0.25, t));
          if (r > lim) return;
          const n = noise(x * 0.2, y * 0.2 + o.seed) + 0.5 * noise(x * 0.5 + 7, y * 0.5 - 3), h = ((x * 73856093) ^ (y * 19349663)) & 7;
          if (n < 0.1 || h > 3) return;
          out.c = n > 0.6 ? dv : dk; out.a = 0.6 * k * (1 - r / lim * 0.5);
        });
      }
    },
    draw(p) {
      if (mv === "cast") for (const pass of ["ink", "body"]) for (const tn of ten) {
        const u = t - tn.t0;
        if (u < 0) continue;
        const rise = ease.outCubic(clamp(u / 0.12)), back = ease.inCubic(smooth(0.35 + 0.15 * DL, 0.6 + 0.2 * DL, u));
        if (back >= 0.6) continue;
        const wv = Math.sin(u * 9 + tn.ph) * 5;
        const b = tn.b, tip = [b[0] + tn.lean + wv, b[1] - tn.up * rise];
        tentacle(p, b, [b[0] - wv * 0.4, b[1] - tn.up * 0.35 * rise], tip, 0, 1 - back, { c2: [b[0] + tn.lean * 0.5 - wv, b[1] - tn.up * 0.7 * rise], w0: tn.w0, seed: tn.seed, el, hot: u < 0.06 ? 1 : 0, dis: 0, curl: 0, glowK: GK, pass }, core, deco && pass === "body");
      }
      if (mv === "aura") for (const pass of ["ink", "body"]) for (const a of aur) {   // 身后两条：慢摆、尖端慢慢卷（循环：只按 t / LOOP 的整周期相位摆）
        const ph = TAU * t / LOOP + a.ph, sw = Math.sin(ph) * 6, cu = 0.5 + 0.5 * Math.sin(ph + 1.3);
        const b = a.b, tip = [b[0] + a.s * (14 + sw), b[1] - a.up + Math.cos(ph) * 3];
        tentacle(p, b, [b[0] + a.s * 2, b[1] - a.up * 0.45], tip, 0, 1, { c2: [b[0] + a.s * (4 - sw * 0.6), b[1] - a.up * 0.85], w0: a.w0, seed: a.seed, el, hot: 0, dis: 0, curl: 0.6 + 0.4 * cu, cs: a.s, glowK: GK * (0.6 + 0.4 * Math.sin(ph * 2) ** 2), pass }, core, deco && pass === "body");
      }
      if (mv === "charge") for (const pass of ["ink", "body"]) for (const c of [{ b: [-9, 3], s: -1, ph: 0 }, { b: [10, 2], s: 1, ph: 2.4 }]) {   // S1 唤醒已充能：脚边两截小触手尖探出地面、轻轻摆（取代脚下金环：金色和经验结晶撞色）
        const ph = TAU * t / LOOP + c.ph, h = 13 + 2 * Math.sin(ph);
        tentacle(p, c.b, [c.b[0], c.b[1] - h * 0.5], [c.b[0] + c.s * (4 + 2 * Math.sin(ph + 1)), c.b[1] - h], 0, 1, { c2: [c.b[0] + c.s * 3, c.b[1] - h * 0.85], w0: 2.4, seed: o.seed + c.s, el, hot: 0, dis: 0, curl: 0.55, cs: c.s, glowK: GK, pass }, core, deco && pass === "body");
      }
      if (mv === "s3aura" && core) {   // S3 持续：脚下几道横向水波纹慢慢流（原作 skill_03_buff 的 flow 水纹）；每道断成几段、长短不一，外缘不描圈
        const ph = TAU * t / LOOP, G = 40, md = hex("#3a4fb4"), hi = hex("#9aa8ff");
        for (let k = 0; k < 6; k++) {
          const y0 = -15 + k * 6 + 1.5 * noise(k * 3.1, o.seed + 4), half = G * Math.sqrt(Math.max(0, 1 - (y0 / 18) ** 2)) * (0.75 + 0.2 * noise(k * 1.7, o.seed + 5));
          for (let x = -half; x <= half; x += 0.6) {
            const seg = noise(x * 0.09 + Math.sin(ph) * 1.6 * (k % 2 ? 1 : -1) + k * 5, o.seed + 6);   // 断成几段，段随相位来回流（按 sin 相位，循环首尾相接）
            if (seg < -0.05) continue;
            const y = y0 + 1.6 * noise(x * 0.07 + Math.cos(ph) * 0.8 + k, o.seed + 7);
            p.px(x, y, seg > 0.45 && Math.abs(x) < half * 0.7 ? hi : md);
          }
        }
      }
      if (mv === "bind") for (const pass of ["ink", "body"]) {   // 敌人脚下：一根小触须从地里钻出、绕过脚踝收紧（开口弧，不是闭合圈）
        const ph = TAU * t / LOOP, sq = 1 + 0.08 * Math.sin(ph);
        const b = [-9 * sq, 2], tip = [8 * sq, 1 + Math.sin(ph + 1) * 1.5];
        tentacle(p, b, [-13 * sq, -7], tip, 0, 1, { c2: [13 * sq, -8 + Math.sin(ph) * 1.5], w0: 2.2, seed: o.seed, el, hot: 0, dis: 0, curl: 0.7, cs: 1, glowK: GK, pass }, core, deco && pass === "body");
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
