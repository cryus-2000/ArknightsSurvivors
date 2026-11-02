// 歌蕾蒂娅落点水爆（S1 拖回落地 / S3 收势 / 精二，替换 fx_gladiia_ram）：@2x 帧条，地面透视 sy 0.55，原点 = 落点地面，游戏 scale 1.0（1:1）。
// 首帧白闪；中心一股水柱冲起又塌下，地面上几片大小、方向都不等的水舌向外拍开，边缘碎成水珠落回，最后剩一摊退去的水渍。不画同心圈、不等距放射。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Gladiia tide burst",
  desc: "A white flash, a central water column shoots up and collapses while a ragged crown of water slaps outward across the floor and break into falling droplets.",
  tags: ["water", "splash", "impact", "floor", "topdown", "one-shot"],
  size: [140, 140],
  origin: [70, 84],
  duration: 0.8,   // 主体 + 余韵（技能 ≤ 0.6 s）
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.gladiia],
    radius: 50,
    seed: 2,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const ps = new Particles({ rng: Rg, ground: (x) => 0, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] });
  const colH = Rg.range(40, 52);
  let t = 0, burst = false;

  // 拍开的水面：一整片不规整的水冠，每个方向的外沿按噪声起伏（几处鼓出、几处缩回），外缘白沫、里面半透明并逐渐掏空
  const lobe = (a) => 0.62 + 0.3 * (0.5 + 0.5 * noise(a * 1.9, o.seed + 1)) + 0.04 * noise(a * 5.3, o.seed + 4);
  function sheet(p, far) {
    const out = ease.outQuart(clamp((t + 0.02) / 0.16)), fade = 1 - smooth(0.2, 0.42, t), hollow = smooth(0.06, 0.3, t);
    if (fade <= 0) return;
    const rc = R * (0.25 + 0.8 * out), B = rc * 1.2 + 3;
    p.shade(-B, -B * SY - 2, B, B * SY + 2, (x, y) => {
      if ((y < 0) !== far) return;
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY), e = rc * lobe(a);
      if (r > e) return;
      const q = r / e, rim = q > 0.88 - 0.06 * hollow;
      if (!rim && q < hollow * 0.9) return;
      if (rim && t > 0.14 && noise(a * 6.1, o.seed + 9) > 0.55 - (t - 0.14) * 2) return;   // 外沿白沫后段碎开、出缺口
      const c = C[clamp(Math.round((rim ? 6.5 - smooth(0.06, 0.3, t) * 1.5 : 3 + q * 2.5) - (1 - fade) * 3 - (far ? 1 : 0) + (t < 0.03 ? 3 : 0)), 1, 7)];
      p.blend(x, y, c, (rim || t < 0.03 ? 0.9 : 0.5) * Math.min(1, fade * 1.5));
    });
  }

  function column(p) {
    const up = ease.outQuart(clamp((t + 0.03) / 0.1)), down = smooth(0.12, 0.32, t);
    const top = colH * up * (1 - down * 0.4), bot = colH * down;
    if (top - bot < 1) return;
    for (let d = bot; d <= top; d += 1) {
      const v = d / colH, w = 5 * (1 - v * 0.6) + 1.2 * noise(d * 0.3, o.seed);
      const c = C[clamp(Math.round(4 + v * 3 - down * 2 + (t < 0.03 ? 3 : 0)), 2, 7)];
      for (let k = -w; k <= w; k += 1) p.blend(Math.round(k), Math.round(-d), c, Math.abs(k) > w - 1.2 ? 0.6 : 0.9);
    }
  }

  // 余韵（docs/229 §2.5）：主体之后留几粒稀疏残光慢慢上浮淡掉，alpha ≤ TAIL_ALPHA；光晕（light 层 → _glow 条）在焦点
  const Rt = new Rng(o.seed + 99), res = [];
  for (let i = 0; i < 12; i++) { const q = ((Rt) => { const a = Rt.range(0, TAU), r = R * lobe(a) * Rt.range(0.8, 1.0); return [Math.cos(a) * r, Math.sin(a) * r * SY]; })(Rt); res.push({ x: q[0], y: q[1], d: Rt.range(0, 0.4 * 0.4), l: Rt.range(0.4 * 0.5, 0.4 * 0.6) }); }
  function tailFx(p) {
    for (const r of res) {
      const u = (t - 0.36 - r.d) / r.l;
      if (u < 0 || u >= 1) continue;
      p.blend(Math.round(r.x), Math.round(r.y - u * 3), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  function halo(p) {
    const k = 1 - clamp(Math.abs(t - 0.02) / 0.15);
    if (k > 0) p.glow(0, -10, 26, C[5], 0.9 * k);
  }

  return {
    update(dt) {
      t += dt;
      if (!burst && t >= 0.08) {
        burst = true;
        for (let a = Rg.range(0, 0.4); a < TAU; a += Rg.range(0.35, 0.9)) {
          {
            const r = R * lobe(a) * Rg.range(0.75, 0.95), sp = Rg.range(30, 80);
            ps.spawn(P.SPARK, Math.cos(a) * r, Math.sin(a) * r * SY, Math.cos(a) * sp, Math.sin(a) * sp * SY - Rg.range(80, 160), Rg.range(0.2, 0.35));
          }
        }
        for (let i = 0; i < 4; i++) {
          const a = -Math.PI / 2 + Rg.range(-0.7, 0.7), sp = Rg.range(60, 130);
          ps.spawn(P.FLAKE, Rg.range(-3, 3), -colH * 0.8, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.2, 0.3), C[Rg.int(5, 7)], 2);
        }
      }
      ps.update(dt);
    },
    drawBack(p) {
      sheet(p, true);
    },
    draw(p) {
      halo(p);
      tailFx(p);
      sheet(p, false);
      column(p);
      ps.draw(p);
    },
  };
}
