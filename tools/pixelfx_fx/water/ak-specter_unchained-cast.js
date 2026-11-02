// 归溟幽灵鲨技能发动（S1–S3 起手，替换通用 fx_circle_ghost × 1.8）：@2x 帧条，原点 = 脚底（skills fx at self off [0,4]，游戏 scale 1.0）。
// 脚下一闪，几股苍白的水柱高矮不一、各自偏斜地窜起，顶上散成水沫和幽光；地上留一摊不规整的暗水渍慢慢退去。不画圈。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Specter wake",
  desc: "A flash at her feet, then pale water jets of uneven height and lean leap up and burst into spray and ghost-light over a ragged dark stain.",
  tags: ["water", "cast", "buff", "topdown", "one-shot"],
  size: [140, 150],
  origin: [70, 100],
  duration: 0.7,   // 主体 + 余韵（技能 ≤ 0.6 s）
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.specter_unchained],
    seed: 11,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]], haze: C[4] });
  const jets = [];
  const n = Rg.int(5, 7);
  for (let i = 0; i < n; i++) {
    const a = Rg.range(0, TAU), d = Rg.range(4, 26);
    jets.push({ x: Math.cos(a) * d, y: Math.sin(a) * d * SY, h: Rg.range(22, 62) * (Rg.chance(0.25) ? 1.3 : 1), w: Rg.range(2, 4),
      lean: Rg.range(-0.35, 0.35), t0: Rg.range(0, 0.08), up: Rg.range(0.1, 0.16), sd: Rg.range(0, 30), popped: false });
  }
  let t = 0;

  function stain(p) {
    const fade = 1 - smooth(0.18, 0.45, t), Rr = 34 * ease.outQuart(clamp(t / 0.12));
    if (fade <= 0 || Rr < 1) return;
    p.shade(-40, -22, 40, 22, (x, y, out) => {
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY), e = Rr * (1 + 0.18 * noise(a * 2.7, o.seed) + 0.08 * noise(a * 8, o.seed + 4));
      if (r > e) return;
      const q = r / e;
      p.blend(x, y, C[q > 0.8 ? 2 : 1], (q > 0.8 ? 0.5 : 0.4) * fade);
    });
  }

  function jet(p, j) {
    const u = t - j.t0;
    if (u < 0) return;
    const rise = ease.outQuart(clamp(u / j.up)), fall = smooth(j.up, j.up + 0.18, u);
    const top = j.h * rise, bot = j.h * fall * 1.02;   // 水柱从根部往上收干
    if (top - bot < 1) return;
    for (let d = bot; d <= top; d += 1) {
      const v = d / j.h, x = j.x + j.lean * d + 0.8 * noise(d * 0.2, j.sd), y = j.y - d;
      const w = j.w * (1 - v * 0.55);
      const hot = t < 0.05 ? 2 : 0;
      const c = C[clamp(Math.round(3 + v * 3.5 + hot - fall * 2), 1, 7)];
      for (let k = -w; k <= w; k += 1) p.blend(Math.round(x + k), Math.round(y), c, Math.abs(k) > w - 1 ? 0.55 : 0.9);
    }
  }

  // 余韵（docs/229 §2.5）：主体之后留几粒稀疏残光慢慢上浮淡掉，alpha ≤ TAIL_ALPHA；光晕（light 层 → _glow 条）在焦点
  const Rt = new Rng(o.seed + 99), res = [];
  for (let i = 0; i < 10; i++) { const q = ((Rt) => { const a = Rt.range(0, TAU), r = Rt.range(10, 32); return [Math.cos(a) * r, Math.sin(a) * r * SY]; })(Rt); res.push({ x: q[0], y: q[1], d: Rt.range(0, 0.35 * 0.4), l: Rt.range(0.35 * 0.5, 0.35 * 0.6) }); }
  function tailFx(p) {
    for (const r of res) {
      const u = (t - 0.3 - r.d) / r.l;
      if (u < 0 || u >= 1) continue;
      p.blend(Math.round(r.x), Math.round(r.y - u * 4), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  function halo(p) {
    const k = 1 - clamp(Math.abs(t - 0.02) / 0.14);
    if (k > 0) p.glow(0, 0, 24, C[5], 0.9 * k);
  }

  return {
    update(dt) {
      t += dt;
      for (const j of jets) {
        if (!j.popped && t - j.t0 >= j.up) {
          j.popped = true;
          const x = j.x + j.lean * j.h, y = j.y - j.h;
          const m = Rg.int(2, 3);
          for (let i = 0; i < m; i++) {
            const a = -Math.PI / 2 + Rg.range(-1.3, 1.3), sp = Rg.range(25, 70);
            ps.spawn(Rg.chance(0.5) ? P.VAPOUR : P.FLAKE, x, y, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.1, 0.2), C[Rg.int(5, 7)], Rg.range(1.5, 3));
          }
        }
      }
      ps.update(dt);
    },
    drawBack(p) {
      stain(p);
    },
    draw(p) {
      halo(p);
      tailFx(p);
      if (t < 0.1) {   // 脚下一闪：压扁的不规整水花，首帧白、第二帧冷却
        const k = t < 0.05 ? 1 : 0.5;
        p.shade(-18, -10, 18, 10, (x, y, out) => {
          const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / (16 * k + 4) / (1 + 0.25 * noise(a * 3, o.seed + 2));
          if (r > 1) return;
          const c = C[clamp(Math.round(7 - r * 3 - (1 - k) * 2.5), 2, 7)];
          if (r > 0.7) p.blend(x, y, c, 0.7); else out.c = c;
        });
      }
      for (const j of jets) jet(p, j);
      ps.draw(p);
    },
  };
}
