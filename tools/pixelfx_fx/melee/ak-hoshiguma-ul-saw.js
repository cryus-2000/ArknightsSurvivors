// 星熊 S3「力之锯」放开版（docs/242；开关 fx/px_unleashed）：俯视直线撕裂斩，原点 = 星熊，正右为出手方向，游戏里按朝向旋转。
// 判定从 hoshiguma.json 读（targets judge）：len = s3_len / 2、w = s3_w / 2（1x 像素；PX 2）。核心层只画判定内：斩线 + 单侧不等距锯齿 + 判定边缘。
// 颜色：原作 S3 buff（build/ark_ref/hoshiguma/hsguma_01 / 03）是青绿鬼火，与 PRTS 发色 #58C4AB 一致 → 本招用青绿色阶（targets palette_src）。
// 精英档（docs/242 §10，docs/91 §4）：
//   E0 核心 + 短火星，余韵约 0.25 s、光晕 k ≤ 0.25；
//   E1 + 隆起尘墙 + 暗红余烬（精一「反击架势」：格挡后刀光转暗红）；余韵约 0.4 s；
//   E2 + 青绿鬼火舌 + 飞出的锯齿碎片 + 不规整分叉地裂 + 白热大光晕，余韵 0.6 s（精二「般若回旋」：翠绿盾锯）。
// 不用等距：锯齿 / 鬼火 / 裂缝分叉的位置都走 jitterSteps / 噪声；外缘起伏用 noise()。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Hoshiguma Saw of Strength unleashed",
  desc: "Straight shield-saw rip: white-hot cut with uneven teeth cooling to teal; higher elite tiers add dust, red embers, teal oni flames, flying teeth, a forking crack.",
  tags: ["melee", "slash", "saw", "topdown", "one-shot"],
  size: [176, 104],
  origin: [18, 52],
  duration: 0.95,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#081814", "#0f2e28", "#18584c", "#258a77", "#58c4ab", "#b4f0e2", "#ffffff"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],   // 精一「反击架势」暗红（docs/91 §4 精一视觉）
    dust: ["#14110d", "#2c261d", "#4a4032", "#6e604b", "#958468"],
    len: 110,
    w: 25,
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), E = fit(o.ember, 5), D = fit(o.dust, 5), Rg = new Rng(o.seed);
  const L = o.len, HW = o.w / 2, el = +o.elite, LQ = +o.quick > 0 ? 0.5 : 1;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const TAIL = [0.25, 0.4, 0.6][el] * LQ;           // 余韵（docs/242 §10 E0 / E1 / E2）
  const GK = [0.22, 0.32, 0.5][el];                  // 光晕系数
  const RUN = 0.06;                                  // 斩线从脚下撕到头的时间
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]], haze: C[3] }), lights = new Lights();
  const ems = new Particles({ rng: Rg, ground: () => 1e9, sparks: [E[4], E[3], E[2], E[1]] });
  // 锯齿：单侧（上沿），间距 2–13、高 1.5–7（偶有 1.5 倍大齿），都随机
  const teeth = jitterSteps(Rg, L - 6, 2, 13).map((x) => ({ x: x + 4, h: Rg.range(1.5, 7) * (0.5 + 0.5 * (x / L)) * (Rg.chance(0.15) ? 1.5 : 1), lean: Rg.range(0.2, 1.1) }));
  // 鬼火舌（E2）：沿斩线不等距，两侧都有，长短 / 出现早晚随机
  const flames = el >= 2 ? jitterSteps(Rg, L - 10, 7, 20).map((x, i) => ({ x: x + 6, side: (i + Rg.int(0, 1)) % 2 ? -1 : 1, h: Rg.range(6, 16), d: Rg.range(0.02, 0.16), ph: Rg.range(0, 6), lean: Rg.range(-0.6, 0.9) })) : [];
  // 地裂（E2）：主缝沿斩线 + 不规整分叉
  const forks = [];
  if (el >= 2) for (const x of jitterSteps(Rg, L - 14, 10, 30)) {
    const side = Rg.chance(0.5) ? -1 : 1, segs = [];
    let px = x + 8, py = 0, a = side * Rg.range(0.5, 1.2);
    for (let k = 0, n = Rg.int(2, 4); k < n; k++) { const l = Rg.range(4, 10); const nx = px + Math.cos(a) * l, ny = py + Math.sin(a) * l * 0.8; segs.push([px, py, nx, ny]); px = nx; py = ny; a += Rg.range(-0.6, 0.6); }
    forks.push(segs);
  }
  let t = 0, burst = false;
  return {
    update(dt) {
      t += dt;
      if (!burst && t >= RUN * 0.5) {
        burst = true;
        lights.add(L * 0.7, 0, 14, C[5], 0.45 * GK / 0.5, 0.16);
        if (deco) {
          // 火星：两侧甩出，角度集中在法线 ±0.8、略往前（出手方向），速度 / 寿命随机
          const n = [10, 16, 26][el];
          for (let i = 0; i < n; i++) {
            const x = Rg.range(6, L), side = Rg.chance(0.5) ? -1 : 1, a = side * (Math.PI / 2) + Rg.range(-0.8, 0.8) * side - 0.35 * side, sp = Rg.range(70, 210);
            ps.spawn(P.SPARK, x, side * HW * 0.3, Math.cos(a) * sp + 40, Math.sin(a) * sp, Rg.range(0.12, 0.28) * (0.6 + TAIL), 0, 1);
          }
          if (el >= 1) {   // 尘墙：两侧被推开的尘团（隆起），大小 / 位置不等
            for (const x of jitterSteps(Rg, L, 9, 26)) {   // 稀疏、两侧随机、离斩线远近不一（不排成两行）
              const side = Rg.chance(0.5) ? -1 : 1;
              ps.spawn(P.DUST, x + Rg.range(-4, 4), side * Rg.range(HW * 0.4, HW + 4), Rg.range(-10, 25), side * Rg.range(15, 45), Rg.range(0.25, 0.45) * (0.5 + TAIL), D[2 + Rg.int(0, 1)], Rg.range(1.8, 3.6), Rg.range(0, 0.08));
            }
            for (let i = 0; i < 9; i++) {   // 暗红余烬（反击架势）
              const x = Rg.range(10, L), side = Rg.chance(0.5) ? -1 : 1;
              ems.spawn(P.SPARK, x, side * HW * 0.5, Rg.range(-30, 60), side * Rg.range(40, 120), Rg.range(0.2, 0.4) * (0.5 + TAIL), 0, 1, Rg.range(0, 0.05));
            }
          }
          if (el >= 2) {   // 锯齿碎片：往前上方崩飞的青绿小块
            for (let i = 0; i < 8; i++) {
              const x = Rg.range(L * 0.5, L), a = Rg.range(-1.3, 1.3), sp = Rg.range(90, 230);
              ps.spawn(P.MOTE, x, Rg.range(-HW, HW) * 0.4, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.25, 0.45), C[4 + Rg.int(0, 1)], Rg.range(0.8, 1.4));
            }
            for (let i = 0; i < 6; i++) ps.spawn(P.VAPOUR, Rg.range(10, L), Rg.range(-HW, HW), Rg.range(-10, 30), Rg.range(-20, 20), Rg.range(0.4, 0.6), C[3], Rg.range(2, 4), Rg.range(0, 0.1));
          }
        }
      }
      ps.update(dt); ems.update(dt); lights.update(dt);
    },
    draw(p) {
      const head = L * ease.outExpo(clamp((t + 0.03) / RUN));                 // 斩线头部（第 0 帧已撕开大半）
      const cool = clamp((t - 0.05) / 0.25), fade = 1 - smooth(0.18, 0.18 + 0.12 + TAIL * 0.35, t);
      // —— 装饰：地裂（E2）先画在最底：先亮后冷，0.6 s 慢慢暗下去
      if (deco && el >= 2) {
        const ck = 1 - smooth(0.1, 0.1 + TAIL, t);
        if (ck > 0) for (const segs of forks) for (const [x0, y0, x1, y1] of segs) {
          if (x0 > head) continue;
          p.line(x0, y0, x1, y1, t < 0.12 ? C[5] : t < 0.25 ? C[4] : C[2], 0.9 * ck);
        }
        if (ck > 0) for (let x = 2; x < head; x++) p.blend(x, Math.round(noise(x * 0.4, o.seed + 9) * 1.2), C[t < 0.15 ? 4 : 2], 0.8 * ck);   // 主缝
      }
      // —— 装饰：光晕（沿斩线，首帧最强）
      if (deco) {
        const gk = GK * (t < 0.05 ? 1.4 : 1) * (1 - smooth(0.05, 0.05 + 0.2 + TAIL * 0.4, t));
        if (gk > 0.01) for (let x = 4; x < head; x += 9) p.glow(x, 0, 10 + HW * 0.6, C[4], gk * (0.4 + 0.6 * x / L));
      }
      // —— 装饰：鬼火舌（E2）：从斩线两侧窜起、摇曳、变细熄灭
      if (deco) for (const f of flames) {
        const u = t - f.d;
        if (u < 0 || f.x > head) continue;
        const life = clamp(u / 0.06) * (1 - smooth(0.1, 0.1 + TAIL * 0.8, u)), H = f.h * life;
        if (H < 1) continue;
        for (let d = 0; d < H; d += 0.5) {
          const v = d / H, sway = 2.4 * noise(f.ph + d * 0.18 + u * 9, o.seed + 4) * v + f.lean * d;   // 鬼火往后上方飘（往出手反方向斜）
          const wdt = (1.3 - 1.1 * v) * (0.6 + 0.4 * life);
          for (let e = -wdt; e <= wdt; e += 0.7) {
            const ci = clamp(Math.round(5 - v * 3 - Math.abs(e) * 0.7 - (1 - life) * 1.5), 1, 5);
            p.blend(f.x + sway + e, f.side * (HW * 0.35 + d), C[ci], (0.85 - v * 0.5) * life);
          }
        }
      }
      if (deco) { ems.draw(p); ps.draw(p, "back"); }
      // —— 核心：斩线（判定内）：中脊 + 单侧锯齿 + 判定边缘细线；首帧白热，第 2 帧余热降一档，之后回到色阶中段并淡出
      if (core && fade > 0) {
        const hot = t < 0.05 ? 2 : t < 0.1 ? 1 : 0;
        for (let x = 0; x <= head; x++) {
          const v = x / L, tip = clamp((head - x) / 8);                       // 刀头渐尖
          const th = (1.2 + 2.6 * Math.sin(Math.PI * Math.min(1, v * 0.9 + 0.05))) * tip * (1 - 0.45 * cool);
          const yc = 0.8 * noise(x * 0.3, o.seed + 2);
          for (let y = -th; y <= th; y++) {
            const q = Math.abs(y) / Math.max(th, 0.6);
            const ci = clamp(Math.round(4 + hot - q * 2 - cool * 2.2 + v * 0.6), 1, 6);
            p.blend(x, yc + y, C[ci], fade * (q > 0.75 ? 0.75 : 1));
          }
          // 判定边缘：上下两条断续细线（判定宽 w），只在出手后前 0.2 s，靠 alpha 淡出
          const ek = (1 - smooth(0.04, 0.22, t)) * tip;
          if (ek > 0.05 && noise(x * 0.5, o.seed + 6) > -0.35) { p.blend(x, -HW, C[3 + Math.min(1, hot)], 0.55 * ek); p.blend(x, HW, C[3], 0.45 * ek); }
        }
        for (const s of teeth) {                                                // 锯齿：上沿，三角，向后倾
          if (s.x > head) continue;
          const h = s.h * (1 - 0.3 * cool);
          for (let d = 0; d < h; d += 0.5) {
            const v = d / h, x = s.x - d * s.lean;
            const ci = clamp(Math.round(4 + hot - v * 1.5 - cool * 2), 1, 6);
            p.blend(x, -(2.6 + d), C[ci], fade);
            if (v < 0.5) p.blend(x + 1, -(2.6 + d), C[clamp(ci - 1, 1, 6)], fade * 0.8);
          }
        }
        if (t < 0.1) p.disc(head - 2, 0, 3.5 - t * 20, C[6], 0.9);            // 刀头白热芯（首帧）
      }
      if (deco) { ps.draw(p, "front"); lights.draw(p); }
    },
  };
}
