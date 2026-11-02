// 铃兰狐火光域展开（docs/229 技能档）：@2x，1 贴图像素 = 1 世界像素，原点 = 脚底，地面透视 sy 0.55，外沿半径 radius。
// 一圈狐火从脚下推到外沿：圈上火舌高低按噪声起伏（不等距），首帧爆亮，之后外缘先冷；
// 到边后火舌塌下，散成几点狐火往上飘，圈按噪声溶解。只有一圈，不叠同心圈。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran foxfire ring",
  desc: "A ring of foxfire rushes out from the feet over the floor, its flames rising unevenly, then they sink, drift off as wisps and the ring dissolves.",
  tags: ["holy", "ring", "fire", "foxfire", "floor", "one-shot"],
  size: [150, 110],
  origin: [75, 70],
  duration: 0.5,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, radius: 60, seed: 9 },
};

const SY = 0.55, OUT = 0.16;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), R = o.radius, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  const rc = (tt) => R * (0.45 + 0.55 * ease.outQuart(clamp(tt / OUT)));
  const jag = (a) => 1 + 0.07 * noise(a * 3.3, S) + 0.04 * noise(a * 8.9, S + 4);
  const hAt = (a) => 13 * (0.25 + 0.75 * clamp(0.5 + 0.6 * noise(a * 4.1, S + 7))) * (0.8 + 0.4 * (0.5 + 0.5 * noise(a * 11, S + 1)));
  let t = 0, broke = false;
  function ring(p, far) {
    const k = 1 - smooth(0.25, 0.48, t), r = rc(t), Wd = 5 * (1 - 0.4 * clamp(t / 0.4));
    if (k <= 0) return;
    const B = r * 1.15 + 2;
    p.shade(-B, -B * SY - 2, B, B * SY + 2, (x, y) => {
      if ((y < 0) !== far) return;
      const a = Math.atan2(y / SY, x), q = (r - Math.hypot(x, y / SY) / jag(a)) / Wd;
      if (q < -0.2 || q > 1) return;
      if (noise2(x * 0.25, y * 0.4, S + 3) * 0.5 + 0.5 > k + 0.3) return;
      const ci = t < 0.04 ? clamp(Math.round(6.6 - q * 1.5), 4, 6) : clamp(Math.round(5.6 - Math.max(0, q) * 2.8 - t / 0.05 * 0.45 - (far ? 0.6 : 0)), 2, 6);
      p.blend(x, y, C[ci], q > 0.6 ? 0.55 : 0.95);
    });
  }
  function flames(p, far) {
    const rise = ease.outCubic(clamp(t / 0.08)) * (1 - smooth(0.18, 0.34, t));
    if (rise <= 0.02) return;
    const r = rc(t), step = 0.7 / r;
    for (let a = 0; a < TAU; a += step) {
      const sn = Math.sin(a);
      if ((sn < 0) !== far) continue;
      const k = jag(a), x = Math.cos(a) * r * k, y = sn * r * k * SY, h = hAt(a) * rise;
      const lean = noise(a * 2 + t * 6, S + 9) * 0.35;
      for (let d = 0; d <= h; d += 0.5) {
        const v = d / h;
        const ci = t < 0.04 ? 6 : clamp(Math.round(3 + (1 - v) * 3 - t / 0.05 * 0.5 - (far ? 1 : 0)), 2, 6);
        p.blend(x + lean * d, y - d, C[ci], v > 0.75 ? 0.5 : 0.9);
      }
    }
  }
  return {
    update(dt) {
      t += dt;
      if (!broke && t >= 0.2) {
        broke = true;
        for (let a = Rg.range(0, 0.4); a < TAU; a += Rg.range(0.35, 0.8)) {
          const r = rc(t) * jag(a);
          ps.spawn(P.EMBER, Math.cos(a) * r, Math.sin(a) * r * SY - hAt(a) * 0.5, Rg.range(-10, 10), -Rg.range(25, 60), Rg.range(0.12, 0.25), Rg.pick([C[5], C[4], C[6]]));
        }
      }
      ps.update(dt);
    },
    drawBack(p) { ring(p, true); flames(p, true); },
    draw(p) {
      ring(p, false);
      flames(p, false);
      ps.draw(p);
    },
  };
}
