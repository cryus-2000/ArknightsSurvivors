// 凯尔希「治疗」普攻落在队长身上（替换通用 fx_heal_aura_green + 黄色 fx_holy_impact）：@2x 帧条，原点 = 队长脚底，游戏 scale 1.0。
// 脚下一摊不规整的荧绿微光一闪即收，几粒大小、速度、起点都不同的光点往上浮到胸口高度，胸口处一个偏心的十字缝合闪（横短竖长、右上臂最长）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Kal'tsit mend",
  desc: "A ragged lime glow flashes at the feet and draws in, uneven motes float up to chest height, and an off-centre stitch-cross glints there.",
  tags: ["holy", "heal", "buff", "topdown", "one-shot"],
  size: [70, 120],
  origin: [35, 76],
  duration: 0.65,   // 主体 + 余韵（技能 ≤ 0.6 s）
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.kaltsit],
    seed: 7,
  },
};

const SY = 0.5, CHEST = 34;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]] });
  const motes = [];
  for (let i = 0, n = Rg.int(5, 7); i < n; i++)
    motes.push({ x: Rg.range(-14, 14), y: Rg.range(-4, 4), d: Rg.range(0.02, 0.12), v: Rg.range(110, 190), life: Rg.range(0.2, 0.32), s: Rg.chance(0.5) ? 2 : 1 });
  let t = 0;

  function pool(p) {
    const k = 1 - smooth(0.02, 0.3, t), Rr = 18 * (0.6 + 0.4 * ease.outQuart(clamp(t / 0.06))) * (1 - 0.35 * smooth(0.1, 0.3, t));
    if (k <= 0) return;
    p.shade(-22, -12, 22, 12, (x, y, out) => {
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / Rr / (1 + 0.22 * noise(a * 2.6, o.seed));
      if (r > 1) return;
      const hot = t < 0.04;   // 首帧整摊爆亮
      const c = C[clamp(Math.round((r > 0.78 ? 6 : 5) - (1 - k) * 2.5 + (hot ? 2 : 0)), 2, 7)];
      p.blend(x, y, c, (hot ? 0.95 : r > 0.78 ? 0.6 : 0.3) * k);
    });
  }

  function stitch(p) {
    const u = t - 0.12;
    if (u < 0 || u > 0.2) return;
    const k = u < 0.05 ? 1 : 1 - (u - 0.05) / 0.15, cy = -CHEST;
    const arm = (dx, dy, L) => { for (let i = 0; i <= L; i++) p.px(Math.round(dx * i), Math.round(cy + dy * i), C[clamp(Math.round(7 - i / L * 3 - (1 - k) * 3), 2, 7)]); };
    arm(1, -1, Math.round(9 * k)); arm(-1, 1, Math.round(4 * k)); arm(-1, -1, Math.round(5 * k)); arm(1, 1, Math.round(3 * k));   // 偏心：右上臂最长
    p.px(0, cy, C[7]);
  }

  // 余韵（docs/229 §2.5）：主体之后留几粒稀疏残光慢慢上浮淡掉，alpha ≤ TAIL_ALPHA；光晕（light 层 → _glow 条）在焦点
  const Rt = new Rng(o.seed + 99), res = [];
  for (let i = 0; i < 6; i++) { const q = ((Rt) => [Rt.range(-10, 10), -CHEST + Rt.range(-8, 8)])(Rt); res.push({ x: q[0], y: q[1], d: Rt.range(0, 0.3 * 0.4), l: Rt.range(0.3 * 0.5, 0.3 * 0.6) }); }
  function tailFx(p) {
    for (const r of res) {
      const u = (t - 0.32 - r.d) / r.l;
      if (u < 0 || u >= 1) continue;
      p.blend(Math.round(r.x), Math.round(r.y - u * 3), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  function halo(p) {
    const k = 1 - clamp(Math.abs(t - 0.14) / 0.1);
    if (k > 0) p.glow(0, -CHEST, 14, C[5], 0.9 * k);
  }

  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      halo(p);
      tailFx(p);
      pool(p);
      for (const m of motes) {
        const u = t - m.d;
        if (u < 0 || u > m.life) continue;
        const q = u / m.life, y = m.y - Math.min(CHEST + 6, m.v * u) , x = m.x * (1 - q * 0.6);
        const c = C[clamp(Math.round(7 - q * 3), 3, 7)];
        p.px(Math.round(x), Math.round(y), c);
        if (m.s > 1) p.px(Math.round(x) + 1, Math.round(y), c);
        p.blend(Math.round(x), Math.round(y + 1), C[clamp(Math.round(5 - q * 2), 2, 6)], 0.8 - q * 0.5);   // 大光点拖一格尾
      }
      stitch(p);
    },
  };
}
