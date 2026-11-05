// 浊心斯卡蒂 S2「同葬无光之愿」起手（docs/242 放开版；技能起手钩子 cast "1"）：1x，俯视，原点 = 脚底，地面透视 sy 0.55。
// 一次性立誓、永久生效：一道暗酒红的光自上而下落到她身上（细、收尖，不是光柱方块），落地处溅起不规则的一圈水沫（贴着脚、外缘噪声），
// 然后一道前沿把歌域推到 ×(1 + s2_aura) 的 R2（judge 传入）。和 S1（缠身光带）/ S3（潮冠 + 浪柱）区分：S2 是自上而下的「落」。
// 精英档（docs/91 §13）：E0 落光 + 溅沫 + 前沿；E1「余音」= 落光两侧多两道更细的余光、前沿到边后外圈回声弧；E2「远古血亲」= 落地后两三片海嗣鳍从溅沫里环身升起、海蓝光点。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skalter vow without light",
  desc: "A thin wine-dark light falls onto her from above, splashing a ragged collar at her feet, then a broken front widens her song field; higher ranks add side lights, echo arcs and seaborn fins.",
  tags: ["water", "song", "buff", "topdown", "one-shot"],
  size: [300, 300],
  origin: [150, 220],
  duration: 1.05,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: [...OP.skalter],
    sea: ["#0b1a2e", "#14324f", "#1f5468", "#3b8e89", "#7fc4bf", "#d6f0ec"],
    R0: 95,          // 原歌域边缘（1x）= judge: aura ÷ PX
    R2: 123.5,       // S2 后歌域边缘 = judge: aura × (1 + s2_aura) ÷ PX
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 9,
  },
};

const SY = 0.55, FALL = 0.12, FRONT0 = 0.12, FRONT = 0.42;

export function create(o) {
  const C = fit(o.palette, 8), S = fit(o.sea, 6), Rg = new Rng(o.seed), el = +o.elite;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const tail = [0.25, 0.4, 0.6][el] * (+o.quick ? 0.5 : 1), glowK = [0.25, 0.4, 0.55][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [S[5], S[4], C[5]] }), lights = new Lights();
  const H = 150 * [1, 1.1, 1.2][el];
  const beams = [{ x: 0, w: [3.2, 3.6, 4.6][el], d: 0 }];
  if (el >= 1) { beams.push({ x: -Rg.range(9, 14), w: 1.2, d: Rg.range(0.03, 0.06) }); beams.push({ x: Rg.range(8, 15), w: 1.2, d: Rg.range(0.04, 0.08) }); }
  const gaps = [];
  for (let a = Rg.range(0, 0.9); a < TAU - 0.2; a += Rg.range(0.8, 1.9)) gaps.push({ a, w: Rg.range(0.12, 0.3) });
  const inGap = (a) => gaps.some((g) => { let d = a - g.a; d -= Math.round(d / TAU) * TAU; return Math.abs(d) < g.w; });
  const echo = [];
  if (el >= 1) for (let i = 0, a0 = Rg.range(0, TAU), n = Rg.int(2, 3); i < n; i++) { echo.push({ a: a0, w: Rg.range(0.3, 0.8) }); a0 += Rg.range(1.5, 2.6); }
  const onEcho = (a) => echo.some((g) => { let d = a - g.a; d -= Math.floor(d / TAU) * TAU; return d < g.w; });
  const fins = [];
  if (el >= 2) for (let a = Rg.range(0, 1.2); a < TAU - 0.6; a += Rg.range(1.7, 2.9)) fins.push({ a, h: Rg.range(46, 64), lean: Rg.range(-0.5, 0.5), d: FALL + Rg.range(0.03, 0.1), spikes: Array.from({ length: Rg.int(3, 5) }, () => ({ v: Rg.range(0.2, 0.9), l: Rg.range(3, 6) })) });
  const front = (t) => o.R0 * 0.3 + (o.R2 - o.R0 * 0.3) * ease.outCubic(clamp((t - FRONT0) / (FRONT - FRONT0)));
  const jag = (a) => 1 + 0.035 * noise(a * 3.3, o.seed) + 0.02 * noise(a * 9.1, o.seed + 7);
  const collar = (a) => [14, 16, 20][el] * (1 + 0.35 * noise(a * 2.6, o.seed + 3) + 0.15 * noise(a * 7.3, o.seed + 9));
  let t = 0, landed = false;

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

  function beam(p, b) {   // 自上而下的落光：下端是光头，上面拖一截收尖的尾；落地后从上往下散
    const u = t - b.d;
    if (u < 0) return;
    const head = ease.inQuad(clamp(u / FALL)), gone = smooth(FALL, FALL + 0.2, u);
    if (gone >= 1) return;
    const yHead = -H + H * head, yTail = -H + H * Math.max(0, head - 0.55) + H * gone;
    for (let y = Math.round(yTail); y <= Math.round(yHead); y++) {
      const v = (y - yTail) / Math.max(1, yHead - yTail), w = b.w * (0.35 + 0.65 * v) * (1 - gone);
      for (let q = -w; q <= w; q += 0.5) {
        const edge = Math.abs(q) > w - 0.8, hot = u < FALL + 0.05;
        p.blend(Math.round(b.x + q + 0.8 * noise(y * 0.2, o.seed)), y, edge ? (hot ? C[6] : S[4]) : C[clamp(Math.round(3 + v * 2), 2, 5)], 0.9 * (0.4 + 0.6 * v));
      }
    }
  }

  function splash(p, far) {   // 落地处的水沫领：贴着脚的一圈不规则水沫，外缘白沫、往外翻
    const u = t - FALL;
    if (u < 0) return;
    const k = 1 - smooth(0.15, 0.45, u), g = ease.outQuart(clamp(u / 0.12));
    if (k <= 0) return;
    for (let a = 0; a < TAU; a += 0.04) {
      if ((Math.sin(a) < 0) !== far) continue;
      const r = collar(a) * (0.5 + 0.6 * g), up = 6 * g * (0.5 + 0.5 * noise(a * 4, o.seed + 5)) * (1 - smooth(0.1, 0.35, u));
      const x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
      for (let d = 0; d <= up; d += 1) p.blend(Math.round(x), Math.round(y - d), d > up - 1.2 ? (u < 0.05 ? C[6] : S[4]) : C[3], 0.85 * k);
    }
  }

  function fin(p, f, far) {
    if ((Math.sin(f.a) < 0) !== far) return;
    const u = t - f.d;
    if (u < 0) return;
    const grow = ease.outQuart(clamp(u / 0.18)), fade = 1 - smooth(0.45, 0.75, u);
    if (fade <= 0) return;
    const bx = Math.cos(f.a) * 18, by = Math.sin(f.a) * 18 * SY;
    for (let d = 0; d <= f.h * grow; d += 1) {
      const v = d / f.h, w = 5.2 * (1 - v) + 0.5;
      let sp = 0;
      for (const s of f.spikes) if (Math.abs(v - s.v) < 0.05) sp = s.l * (1 - Math.abs(v - s.v) / 0.05);
      for (let q = -w; q <= w + sp; q += 1) p.blend(Math.round(bx + q + f.lean * d), Math.round(by - d), q < -w + 1 ? S[5] : q > w - 1 ? S[4] : S[2], 0.95 * fade);
    }
  }

  function draws(p, far) {
    if (!core) return;
    const k = 1 - smooth(FRONT * 0.8, FRONT + 0.12, t);
    if (t >= FRONT0) arc(p, front(t), k, far, (a) => !inGap(a), S[4]);
    if (el >= 1) { const u = t - FRONT - 0.04; if (u > 0) arc(p, o.R2 * (0.84 + 0.16 * ease.outQuad(clamp(u / 0.28))), 0.75 * (1 - smooth(0.18, 0.36, u)), far, onEcho, S[4]); }
    splash(p, far);
    for (const f of fins) fin(p, f, far);
  }

  return {
    update(dt) {
      t += dt;
      if (!landed && t >= FALL) {
        landed = true;
        if (deco) {
          lights.add(0, -6, 14 + 4 * el, C[5], glowK, 0.12);
          for (let i = 0, n = 8 + 4 * el; i < n; i++) {   // 落地溅起的水珠：方向偏上、速度和寿命各不相同
            const a = Rg.range(0, TAU), sp = Rg.range(30, 90);
            ps.spawn(Rg.chance(0.5) ? P.SPARK : P.FLAKE, Math.cos(a) * 10, Math.sin(a) * 10 * SY, Math.cos(a) * sp, Math.sin(a) * sp * SY - Rg.range(30, 80), Rg.range(0.2, 0.2 + tail), Rg.chance(0.6) ? S[Rg.int(3, 5)] : C[5], Rg.range(1, 1.8));
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) { draws(p, true); if (deco) ps.draw(p, "back"); },
    draw(p) {
      if (deco) lights.draw(p);
      draws(p, false);
      if (core) for (const b of beams) beam(p, b);
      if (deco) ps.draw(p);
    },
  };
}
