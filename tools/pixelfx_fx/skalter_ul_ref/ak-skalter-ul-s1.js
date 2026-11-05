// 浊心斯卡蒂 S1「同归殊途之吟」起手（docs/242 放开版；技能起手钩子 cast "0"，character.spend_sp 播）：1x，俯视，原点 = 脚底，地面透视 sy 0.55。
// 她开嗓：两三条细长的歌声光带绕身螺旋上升（酒红带身、海蓝 / 白的带边），地面一道前沿把歌域从原半径 R0 推到 ×s1_aura 的 R1（judge 传入）。
// 和 S3 区分：S3 是绕身卷起的潮冠弧焰 + 浪柱；S1 是细长缠绕的光带，读作「歌声扩张」。
// 精英档（docs/91 §13）：E0 两条光带 + 前沿；E1「余音」= 光带加到三条、更高，前沿到边后外圈起回声弧；E2「远古血亲」= 光带脚下探出两片海嗣鳍、带上海蓝光点盘旋，全量光晕与余韵。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skalter song of convergence",
  desc: "Two or three thin song ribbons spiral up around her while a broken front pushes her song field outward; higher ranks add echo arcs and seaborn fins.",
  tags: ["water", "song", "buff", "aura", "topdown", "one-shot"],
  size: [320, 260],
  origin: [160, 180],
  duration: 1.05,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: [...OP.skalter],
    sea: ["#0b1a2e", "#14324f", "#1f5468", "#3b8e89", "#7fc4bf", "#d6f0ec"],
    R0: 95,          // 原歌域边缘（1x）= judge: aura ÷ PX
    R1: 133,         // S1 期间歌域边缘 = judge: aura × s1_aura ÷ PX
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 6,
  },
};

const SY = 0.55, FRONT = 0.34;

export function create(o) {
  const C = fit(o.palette, 8), S = fit(o.sea, 6), Rg = new Rng(o.seed), el = +o.elite;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const tail = [0.25, 0.4, 0.6][el] * (+o.quick ? 0.5 : 1), glowK = [0.25, 0.4, 0.55][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [S[5], S[4], C[5]] }), lights = new Lights();
  const bands = [];
  for (let i = 0, n = [2, 3, 3][el], a0 = Rg.range(0, TAU); i < n; i++) {
    bands.push({ a: a0, h: Rg.range(64, 84) * [1, 1.2, 1.55][el], r: Rg.range(16, 24), turns: Rg.range(1.1, 1.6), w: Rg.range(1.6, 2.6) * [1, 1, 1.35][el], d: i * Rg.range(0.03, 0.07), sd: Rg.range(0, 50) });
    a0 += Rg.range(1.6, 2.9);
  }
  const gaps = [];
  for (let a = Rg.range(0, 0.9); a < TAU - 0.2; a += Rg.range(0.8, 1.9)) gaps.push({ a, w: Rg.range(0.12, 0.3) });
  const inGap = (a) => gaps.some((g) => { let d = a - g.a; d -= Math.round(d / TAU) * TAU; return Math.abs(d) < g.w; });
  const echo = [];
  if (el >= 1) for (let i = 0, a0 = Rg.range(0, TAU), n = Rg.int(2, 3); i < n; i++) { echo.push({ a: a0, w: Rg.range(0.3, 0.8) }); a0 += Rg.range(1.5, 2.6); }
  const onEcho = (a) => echo.some((g) => { let d = a - g.a; d -= Math.floor(d / TAU) * TAU; return d < g.w; });
  const fins = [];
  if (el >= 2) for (let i = 0, a0 = Rg.range(0, TAU); i < 2; i++) { fins.push({ a: a0, h: Rg.range(44, 60), lean: Rg.range(-0.5, 0.5), d: Rg.range(0.05, 0.12), spikes: Array.from({ length: Rg.int(3, 5) }, () => ({ v: Rg.range(0.2, 0.9), l: Rg.range(3, 6) })) }); a0 += Rg.range(2.2, 3.6); }
  const front = (t) => o.R0 + (o.R1 - o.R0) * ease.outCubic(clamp(t / FRONT));
  const jag = (a) => 1 + 0.035 * noise(a * 3.3, o.seed) + 0.02 * noise(a * 9.1, o.seed + 7);
  let t = 0, burst = false;

  function arc(p, rr, k, far, pick, crest) {
    if (k <= 0.02) return;
    for (let a = 0; a < TAU; a += 0.7 / rr) {
      if ((Math.sin(a) < 0) !== far || !pick(a)) continue;
      const r = rr * jag(a), x = Math.round(Math.cos(a) * r), y = Math.round(Math.sin(a) * r * SY);
      const hi = 0.5 + 0.5 * noise(a * 5 + t * 5, o.seed + 2);
      p.blend(x, y, hi > 0.7 ? crest : C[clamp(Math.round(2 + 3.5 * k), 2, 5)], (far ? 0.6 : 0.9) * k);
      p.blend(Math.round(Math.cos(a) * r * 0.98), Math.round(Math.sin(a) * r * 0.98 * SY), C[2], 0.5 * k);
    }
  }

  function band(p, b, far) {   // 一条螺旋上升的光带：带身酒红，外缘海蓝 / 白；从下往上长、从下往上散
    const u = t - b.d;
    if (u < 0) return;
    const grow = ease.outQuart(clamp(u / 0.22)), fade = smooth(0.35, 0.7, u);
    if (fade >= 1) return;
    const N = Math.ceil(b.h * 2.4), seen = new Set();
    for (let i = 0; i <= N * grow; i++) {
      const v = i / N;
      if (v < fade) continue;
      const ang = b.a + b.turns * TAU * v, rr = b.r * (1 - 0.45 * v) + 2 * noise(v * 6, b.sd);
      if ((Math.sin(ang) < 0) !== far) continue;
      const x = Math.cos(ang) * rr, y = Math.sin(ang) * rr * SY - v * b.h;
      const w = b.w * (0.7 + 0.6 * Math.sin(Math.PI * v));
      for (let d = -w; d <= w; d += 0.5) {
        const px = Math.round(x), py = Math.round(y + d), key = px * 1000 + py;
        if (seen.has(key)) continue;
        seen.add(key);
        const edge = d < -w + 1, hot = u < 0.05 ? 2 : u < 0.1 ? 1 : 0;
        p.blend(px, py, edge ? (hot ? C[6] : v > 0.6 ? S[4] : C[5]) : C[clamp(3 + hot, 1, 6)], (edge ? 0.95 : 0.75) * (far ? 0.75 : 1));
      }
    }
  }

  function fin(p, f, far) {
    if ((Math.sin(f.a) < 0) !== far) return;
    const u = t - f.d;
    if (u < 0) return;
    const grow = ease.outQuart(clamp(u / 0.18)), fade = 1 - smooth(0.4, 0.7, u);
    if (fade <= 0) return;
    const bx = Math.cos(f.a) * 22, by = Math.sin(f.a) * 22 * SY;
    for (let d = 0; d <= f.h * grow; d += 1) {
      const v = d / f.h, w = 5 * (1 - v) + 0.5;
      let sp = 0;
      for (const s of f.spikes) if (Math.abs(v - s.v) < 0.05) sp = s.l * (1 - Math.abs(v - s.v) / 0.05);
      for (let q = -w; q <= w + sp; q += 1) p.blend(Math.round(bx + q + f.lean * d), Math.round(by - d), q < -w + 1 ? S[5] : q > w - 1 ? S[4] : S[2], 0.95 * fade);
    }
  }

  function draws(p, far) {
    if (core) {
      const k = 1 - smooth(FRONT * 0.7, FRONT + 0.12, t);
      arc(p, front(t), k, far, (a) => !inGap(a), t < 0.05 ? C[6] : S[4]);
      if (el >= 1) { const u = t - FRONT - 0.04; if (u > 0) arc(p, o.R1 * (0.84 + 0.16 * ease.outQuad(clamp(u / 0.28))), 0.75 * (1 - smooth(0.18, 0.36, u)), far, onEcho, S[4]); }
      for (const f of fins) fin(p, f, far);
      for (const b of bands) band(p, b, far);
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!burst) { burst = true; if (deco) lights.add(0, -24, 14 + 4 * el, C[5], glowK, 0.12); }
      if (deco && t < 0.4 && Rg.chance(0.5 + 0.2 * el)) {   // 光带上甩下的歌声光点，沿螺旋往上飘
        const b = bands[Rg.int(0, bands.length - 1)], v = Rg.range(0.1, 0.8), ang = b.a + b.turns * TAU * v, rr = b.r * (1 - 0.45 * v);
        ps.spawn(Rg.chance(0.6) ? P.MOTE : P.FLAKE, Math.cos(ang) * rr, Math.sin(ang) * rr * SY - v * b.h, -Math.sin(ang) * Rg.range(15, 40), -Rg.range(20, 60), Rg.range(0.25, 0.25 + tail), Rg.chance(0.7) ? S[Rg.int(3, 5)] : C[5], Rg.range(1, 1.8));
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      draws(p, true);
    },
    draw(p) {
      if (deco) { lights.draw(p); const k = 1 - smooth(0, 0.2, t); if (k > 0) p.glow(0, -24, 10 + 3 * el, C[5], glowK * 0.8 * k); }
      draws(p, false);
      if (deco) ps.draw(p);
    },
  };
}
