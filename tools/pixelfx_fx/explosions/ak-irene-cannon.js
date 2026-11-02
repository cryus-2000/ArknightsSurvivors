// 艾丽妮追斩手炮（D 组）：原点 = 落点（地面）。mode 0 = 落点小爆（1x，替换被放大 2.4 倍的 fx_cannon_burst）；
// mode 1 = 枪口一闪（@2x，原点 = 枪口、正右开火，替换 fx_irene_gun_burst / fx_muzzle_flash）。灯火橙（我方灯火色），爆点白芯，黑烟不规整地翻上去。
import { Particles, Bits, B, Lights, P, Rng, fit, clamp, ease, TAU } from "../../core/index.js";
import { LAMP } from "../house.js";

export const meta = {
  name: "Irene cannon",
  desc: "A hand-cannon round: mode 0 lands as a small white-cored lamp-orange burst with ragged dark smoke and grit; mode 1 is the matching muzzle flash.",
  tags: ["explosion", "gun", "lamp", "one-shot"],
  size: [56, 56],
  origin: [28, 40],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "ground",
  options: { palette: ["#06142a", "#2a1a14", "#6a3418", "#c25a1e", LAMP, "#ffc68a", "#fff2dc", "#ffffff"], mode: 0, seed: 9 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), muzzle = +o.mode === 1;
  const ps = new Particles({ rng: Rg, ground: () => (muzzle ? 1e9 : 3), sparks: [C[7], C[6], C[5], C[3]] });
  const bits = new Bits({ ground: () => 3 }), lights = new Lights();
  if (muzzle) {
    for (let i = 0; i < 3; i++) ps.spawn(P.SPARK, 3, 0, Rg.range(150, 260), Rg.range(-40, 40), Rg.range(0.05, 0.09));
    ps.spawn(P.VAPOUR, 7, 0, 50, Rg.range(-8, 8), 0.12, C[2], 3);
  } else {
    lights.add(0, -8, 22, C[5], 0.5, 0.2);
    for (let i = 0; i < 6; i++) {
      const a = Rg.range(-Math.PI, 0), sp = Rg.range(70, 170);
      ps.spawn(P.SPARK, 0, -6, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.1, 0.22));
    }
    for (let i = 0; i < 4; i++) bits.add({ kind: B.CHUNK, x: Rg.sign() * Rg.range(3, 6), y: -2, vx: Rg.sign() * Rg.range(60, 110), vy: -Rg.range(80, 150), a: 0, va: Rg.range(-10, 10), s: Rg.range(1, 1.8), c: C[Rg.int(1, 2)], g: 600, life: Rg.range(0.25, 0.4) });
    for (let i = 0; i < 5; i++) {
      const a = Rg.range(0, TAU);
      ps.spawn(P.SMOKE, Math.cos(a) * Rg.range(1, 6), -6 + Math.sin(a) * 3, Math.cos(a) * 14, -Rg.range(18, 40), Rg.range(0.25, 0.38), 0, Rg.range(3, 5.5), Rg.range(0.02, 0.08));
    }
  }
  const blobs = [[0, 0, 0.75], [Rg.range(-0.5, -0.2), Rg.range(-0.4, 0), Rg.range(0.4, 0.6)], [Rg.range(0.2, 0.5), Rg.range(-0.5, -0.1), Rg.range(0.35, 0.55)], [Rg.range(-0.2, 0.3), Rg.range(-0.8, -0.5), Rg.range(0.3, 0.45)]];
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); bits.update(dt); lights.update(dt); },
    draw(p) {
      if (muzzle) {
        const k = 1 - clamp(t / 0.08);
        if (k > 0) {
          for (const [a, L] of [[0, 12], [-0.45, 6], [0.5, 5.5]])
            for (let d = 0; d < L * (0.7 + 0.3 * k); d += 0.5) {
              const u = d / L, w = (1 - u) * (a === 0 ? 2.4 : 1.2) * k;
              for (let s = -w; s <= w; s += 0.5) p.px(d * Math.cos(a) - s * Math.sin(a), d * Math.sin(a) + s * Math.cos(a), C[clamp(Math.round(7 - u * 3 - Math.abs(s) - (1 - k) * 3), 2, 7)]);
            }
          if (t < 0.04) p.circle(1, 0, 1.6, C[7]);
        }
        ps.draw(p);
        return;
      }
      ps.draw(p, "back");
      const u = t / 0.2;
      if (u < 1) {
        const rr = 4 + 8 * ease.outQuart(clamp(u * 2));
        // 几团大小不一、偏心的火球叠成不规整的爆点；首帧白芯
        for (const [dx, dy, s] of blobs) p.disc(dx * rr, -6 + dy * rr, rr * s, (d) => C[clamp(Math.round(7 - d * 2.5 - u * 4.5), 2, 7)], (d) => (1 - u) * (0.95 - d * 0.55));
        if (t < 0.05) p.circle(0, -6, 3, C[7]);
        p.glow(0, -6, 16, C[5], 0.3 * (1 - u));
      }
      bits.draw(p); ps.draw(p, "front"); lights.draw(p);
    },
  };
}
