// 塞雷娅终结技砸地（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：俯视地面透视，原点 = 拳落点。
// 爆亮 → 地面裂开不规整的分叉裂网（随机游走、长短不一、不等角度，先亮后冷却成暗缝）→ 隆起的碎石尘环往外推 → 碎石落下、尘土慢慢沉。
// 力量感口径（memory 特效力量感做法）：不规整分叉裂网 + 爆亮冷却 + 隆起尘墙；不画规整放射 / 同心圈。
// 分层（docs/242 §8）：core = 裂网 + 首帧爆点；deco = 尘环、碎石、光。
import { Particles, Lights, Bits, B, P, Rng, fit, clamp, smooth, ease, hex, TAU } from "../../core/index.js";

export const meta = {
  name: "Saria slam unleashed",
  desc: "An amber ground slam seen from above: a white flash, an irregular forked crack web glows then cools, a heaved ring of dust and rock rolls out and settles.",
  tags: ["impact", "slam", "crack", "amber", "topdown", "one-shot"],
  size: [240, 160],
  origin: [120, 80],
  duration: 1.2,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#241004", "#52260a", "#8e4510", "#cc7418", "#f2aa3c", "#ffd77e", "#fff2cf", "#ffffff"], radius: 96, layer: "all", seed: 9 },
};

const SY = 0.55;

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 8), R = o.palette, Rg = new Rng(o.seed), RAD = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] }), lights = new Lights();
  const bits = new Bits({ ground: () => 1e9 });
  lights.add(0, 0, 70, C[6], 1.0, 0.35);
  // 裂网：主裂 6–9 条，角度不等（随机间隔），每条随机游走，途中随机分叉
  const segs = [];
  function crack(x, y, a, len, w, depth, t0) {
    let px = x, py = y, d = 0;
    while (d < len) {
      const step = Rg.range(4, 8);
      a += Rg.range(-0.45, 0.45);
      const nx = px + Math.cos(a) * step, ny = py + Math.sin(a) * step * SY;
      segs.push({ x0: px, y0: py, x1: nx, y1: ny, w, t: t0 + d / 260 });
      px = nx; py = ny; d += step;
      if (depth < 2 && Rg.chance(0.16)) crack(px, py, a + Rg.range(0.5, 1.1) * (Rg.chance(0.5) ? 1 : -1), (len - d) * Rg.range(0.35, 0.7), Math.max(1, w - 1), depth + 1, t0 + d / 260);
    }
  }
  for (let a = Rg.range(0, 0.6), k = 0; a < TAU - 0.3 && k < 9; a += Rg.range(0.55, 1.1), k++) crack(0, 0, a, RAD * Rg.range(0.55, 1.0), Rg.int(2, 3), 0, 0.02);
  // 尘环 + 碎石（往外推，不等距）
  for (let a = Rg.range(0, 0.3); a < TAU; a += Rg.range(0.12, 0.35)) {
    const sp = Rg.range(90, 170);
    ps.spawn(P.DUST, Math.cos(a) * 10, Math.sin(a) * 10 * SY, Math.cos(a) * sp, Math.sin(a) * sp * SY, Rg.range(0.6, 1.0), C[2], Rg.range(6, 11), Rg.range(0, 0.06));
    if (Rg.chance(0.5)) bits.add({ kind: B.CHUNK, x: Math.cos(a) * 12, y: Math.sin(a) * 12 * SY, vx: Math.cos(a) * sp * 1.2, vy: Math.sin(a) * sp * 1.2 * SY - 80, a: Rg.range(0, TAU), va: Rg.range(-10, 10),
      s: Rg.range(2.5, 5), c: hex(R[Rg.int(1, 3)]), ramp: R.slice(0, 5), g: 1, drag: 1.2, bounce: 0.2, life: Rg.range(0.6, 0.9) });
  }
  for (let i = 0; i < 26; i++) {
    const a = Rg.range(0, TAU), sp = Rg.range(120, 320);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp * SY - 60, Rg.range(0.2, 0.45));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); bits.update(dt); lights.update(dt); },
    drawBack(p) {
      if (core) for (const s of segs) {
        const u = t - s.t;
        if (u <= 0) continue;
        const grow = clamp(u / 0.04), cool = smooth(0.08, 0.7, u), gone = smooth(0.7, 1.15, t);
        if (gone >= 1) continue;
        const ci = clamp(Math.round(7 - cool * 5.5), 1, 7), x1 = s.x0 + (s.x1 - s.x0) * grow, y1 = s.y0 + (s.y1 - s.y0) * grow;
        for (let k = 0; k < s.w; k++) p.line(s.x0, s.y0 + k * 0.5, x1, y1 + k * 0.5, k === 0 ? C[ci] : C[Math.max(1, ci - 2)], 1 - gone);
      }
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (core && t < 0.1) p.disc(0, 0, 22 * (1 - t / 0.1) + 8, C[7], 0.9);
      if (deco) {
        p.glow(0, 0, 60, C[4], 0.5 * (1 - smooth(0.1, 0.6, t)));
        bits.draw(p);
        ps.draw(p, "front");
        lights.draw(p);
      }
    },
  };
}
