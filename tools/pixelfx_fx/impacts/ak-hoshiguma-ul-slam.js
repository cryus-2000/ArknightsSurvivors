// 星熊 S1「战意」放开版：举盾重砸（圆形判定 s1_r，圆心 = 星熊），俯视地面透视 sy 0.55，原点 = 星熊脚下。
// 半径 = fit（1x，= s1_r / 2），运行时按判定半径缩放；核心层画落点白热 + 判定边缘一圈断续的震裂线（只一道，非同心圈），装饰层放其余。
// 和普攻拉开：普攻是一道薄刀弧，S1 是整片地面被砸开——爆亮更大、裂网、碎石、隆起尘墙、轻震（游戏侧 3 px 0.12 s）。
// 蓄势：第 0 帧盾面先收一下光（往里聚的短亮线），第 1 帧砸下爆亮（帧条内，判定时刻在第 1 帧）。
// 精英档（docs/242 §10，docs/91 §4）：
//   E0 落点爆亮 + 不规整分叉裂网 + 碎石，余韵 0.3 s；
//   E1 + 判定边缘隆起的尘墙（不等距尘团）+ 暗红余烬（精一「反击架势」）；余韵 0.45 s；
//   E2 + 裂缝里窜出的青绿鬼火 + 般若盾形白热印（倒三角）+ 青绿碎晶，余韵 0.65 s（精二「般若」）。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { jitterSteps, jitterAngles } from "../house.js";

export const meta = {
  name: "Hoshiguma battle-will shield slam unleashed",
  desc: "Shield slam into the ground: gather glint, white-hot impact, forking cracks and rocks; tiers add a dust wall and red embers, then teal ghost flames and a shield sigil.",
  tags: ["impact", "slam", "ground", "one-shot"],
  size: [232, 150],
  origin: [116, 78],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#081814", "#0f2e28", "#18584c", "#258a77", "#58c4ab", "#b4f0e2", "#ffffff"],   // §12.6：不用金（经验结晶暖金），青绿 = 般若 / 原作 S3
    dust: ["#14110d", "#2c261d", "#4a4032", "#6e604b", "#958468"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    radius: 75,
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 4,
  },
};

const SY = 0.55, HIT = 0.05;

export function create(o) {
  const C = fit(o.palette, 7), D = fit(o.dust, 5), E = fit(o.ember, 5), J = fit(o.jade, 5), Rg = new Rng(o.seed);
  const R = o.radius, el = +o.elite, LQ = +o.quick > 0 ? 0.5 : 1;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const TAIL = [0.3, 0.45, 0.65][el] * LQ;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  const ems = new Particles({ rng: Rg, ground: () => 1e9, sparks: [E[4], E[3], E[2], E[1]] });
  // 裂网：主缝 5–8 条，角度抖动、长短不一，每条 2–4 段、带 0–2 个分叉
  const cracks = jitterAngles(Rg, Rg.int(5, 8), 0, Math.PI * 2, 0.45).map((a0) => {
    const segs = [];
    const walk = (x, y, a, len, depth) => {
      let px = x, py = y;
      for (let k = 0, n = Rg.int(2, 4); k < n && len > 4; k++) {
        const l = Rg.range(0.25, 0.45) * len, nx = px + Math.cos(a) * l, ny = py + Math.sin(a) * l * SY;
        segs.push([px, py, nx, ny, depth]);
        if (depth < 2 && Rg.chance(0.4)) walk(nx, ny, a + Rg.range(0.5, 1.1) * (Rg.chance(0.5) ? -1 : 1), len * 0.45, depth + 1);
        px = nx; py = ny; a += Rg.range(-0.45, 0.45); len -= l;
      }
    };
    walk(Math.cos(a0) * 6, Math.sin(a0) * 6 * SY, a0, R * Rg.range(0.7, 1.15), 0);
    return segs;
  });
  const flames = el >= 2 ? cracks.flatMap((s) => s.filter((q) => q[4] === 0 && Rg.chance(0.5)).map((q) => ({ x: q[2], y: q[3], h: Rg.range(8, 18), d: Rg.range(0.04, 0.16), ph: Rg.range(0, 6), lean: Rg.range(-0.5, 0.5) }))) : [];
  let t = 0, hit = false;
  return {
    update(dt) {
      t += dt;
      if (!hit && t >= HIT) {
        hit = true;
        lights.add(0, -2, 14, C[5], 0.5, 0.14);   // 小光：大圆光在游戏里读成一个半透明圆盘（§12.3），光改沿裂缝走
        if (deco) {
          for (let i = 0; i < [14, 20, 28][el]; i++) {   // 碎石 / 火星：往外上方抛，落回（俯视里往外飞、往下坠）
            const a = Rg.range(0, Math.PI * 2), sp = Rg.range(60, 200);
            ps.spawn(i % 3 ? P.SPARK : P.GRIT, Math.cos(a) * 8, Math.sin(a) * 8 * SY, Math.cos(a) * sp, Math.sin(a) * sp * SY - Rg.range(40, 140), Rg.range(0.25, 0.5) * (0.6 + TAIL), i % 3 ? 0 : D[3 + Rg.int(0, 1)], 1);
          }
          if (el >= 1) {
            for (const a of jitterAngles(Rg, Rg.int(16, 22), 0, Math.PI * 2, 0.45)) {   // 隆起尘墙：判定边缘不等距的小尘团往外推（小而多，连成一圈被掀起的地皮，不是孤立圆团 §12.3）
              const r = R * Rg.range(0.8, 1.05);
              ps.spawn(P.DUST, Math.cos(a) * r, Math.sin(a) * r * SY, Math.cos(a) * Rg.range(15, 40), Math.sin(a) * Rg.range(15, 40) * SY - Rg.range(10, 30), Rg.range(0.3, 0.5) * (0.5 + TAIL), D[1 + Rg.int(0, 2)], Rg.range(1.4, 3.2), Rg.range(0, 0.06));
              if (Rg.chance(0.6)) ps.spawn(P.GRIT, Math.cos(a) * r, Math.sin(a) * r * SY, Math.cos(a) * Rg.range(30, 80), -Rg.range(60, 140), Rg.range(0.3, 0.5), D[3], 1, Rg.range(0, 0.04));
            }
            for (let i = 0; i < 10; i++) { const a = Rg.range(0, Math.PI * 2), sp = Rg.range(50, 130); ems.spawn(P.SPARK, Math.cos(a) * R * 0.4, Math.sin(a) * R * 0.4 * SY, Math.cos(a) * sp, Math.sin(a) * sp * SY - 60, Rg.range(0.25, 0.45) * (0.5 + TAIL), 0, 1, Rg.range(0, 0.05)); }
          }
          if (el >= 2) for (let i = 0; i < 10; i++) {   // 青绿碎晶
            const a = Rg.range(0, Math.PI * 2), sp = Rg.range(80, 220);
            ps.spawn(P.MOTE, 0, -4, Math.cos(a) * sp, Math.sin(a) * sp * SY - Rg.range(40, 120), Rg.range(0.3, 0.5), J[3 + Rg.int(0, 1)], Rg.range(0.9, 1.5));
          }
        }
      }
      ps.update(dt); ems.update(dt); lights.update(dt);
    },
    draw(p) {
      const u = t - HIT;
      // —— 蓄势（第 0 帧）：几道往落点聚拢的短亮线（盾面收光），长短 / 角度不等
      if (core && u < 0) for (const a of [0.3, 1.4, 2.2, 3.5, 4.4, 5.6]) {
        const r0 = R * (0.35 + 0.15 * Math.sin(a * 3.1)), r1 = r0 * 0.45;
        p.line(Math.cos(a) * r0, Math.sin(a) * r0 * SY - 6, Math.cos(a) * r1, Math.sin(a) * r1 * SY - 6, C[5], 0.8);
      }
      if (u < 0) return;
      const fade = 1 - smooth(0.12, 0.2 + TAIL * 0.5, u), ck = 1 - smooth(0.15, 0.15 + TAIL, u);
      // —— 核心：裂网主缝（判定内）先白热后冷成暗金，分叉只在装饰层
      if (ck > 0) for (const segs of cracks) for (const [x0, y0, x1, y1, dep] of segs) {
        if (dep > 0 ? !deco : !core) continue;
        const grow = clamp(u / 0.08 - Math.hypot(x0, y0 / SY) / R * 0.6);
        if (grow <= 0) continue;
        const ex = x0 + (x1 - x0) * grow, ey = y0 + (y1 - y0) * grow;
        const ci = u < 0.05 ? 6 : u < 0.1 ? 5 : clamp(Math.round(4 - u * 6), 1, 4);
        p.line(x0, y0, ex, ey, C[ci - (dep > 0 ? 1 : 0)], ck * (dep > 0 ? 0.75 : 1));
        if (dep === 0 && u < 0.35) p.line(x0, y0 + 1, ex, ey + 1, C[clamp(ci - 2, 1, 6)], ck * 0.6);   // 主缝两像素宽
      }
      // —— 核心：判定边缘一道断续的震裂线（只一道）
      if (core && fade > 0) for (let a = 0; a < Math.PI * 2; a += 0.6 / R) {
        if (noise(a * 4.3, o.seed + 8) < -0.2) continue;
        const r = R * (1 + 0.03 * noise(a * 9, o.seed + 2));
        p.blend(Math.cos(a) * r, Math.sin(a) * r * SY, C[u < 0.1 ? 5 : 3], 0.7 * fade * (1 - smooth(0.05, 0.3, u)));
      }
      // —— 核心：落点白热（第 1 帧）+ E2 般若盾形印（倒三角，白热后转翠绿）
      if (core && u < 0.12) { const k = 1 - u / 0.12; p.disc(0, -2, 9 + 14 * (1 - k), C[u < 0.05 ? 6 : 5], 0.9 * k); }
      if (core && el >= 2 && u < 0.35) {
        const k = 1 - u / 0.35, V = [[-14, -9], [14, -9], [1, 13]];
        for (let i = 0; i < 3; i++) p.line(V[i][0], V[i][1] * SY - 3, V[(i + 1) % 3][0], V[(i + 1) % 3][1] * SY - 3, u < 0.06 ? C[6] : J[clamp(Math.round(4 - u * 8), 2, 4)], k);
      }
      if (deco) {
        const gk = [0.18, 0.24, 0.32][el] * (1 - smooth(0.02, 0.15 + TAIL * 0.3, u));   // 光晕沿主缝走（不画圆心大光盘，§12.3）
        if (gk > 0.01) for (const segs of cracks) { const q = segs[0]; if (q) p.glow((q[0] + q[2]) / 2, (q[1] + q[3]) / 2, 7, C[4], gk); }
        // E2 鬼火：从主缝末端窜起
        for (const f of flames) {
          const v0 = u - f.d;
          if (v0 < 0) continue;
          const life = clamp(v0 / 0.06) * (1 - smooth(0.1, 0.1 + TAIL * 0.8, v0)), H = f.h * life;
          if (H < 1) continue;
          for (let d = 0; d < H; d += 0.5) {
            const v = d / H, sway = 2 * noise(f.ph + d * 0.2 + v0 * 9, o.seed + 5) * v + f.lean * d;
            for (let e = -(1.4 - 1.1 * v); e <= 1.4 - 1.1 * v; e += 0.7)
              p.blend(f.x + sway + e, f.y - d, J[clamp(Math.round(4 - v * 2.6 - Math.abs(e) * 0.6), 1, 4)], (0.85 - v * 0.5) * life);
          }
        }
        ems.draw(p); ps.draw(p); lights.draw(p);
      }
    },
  };
}
