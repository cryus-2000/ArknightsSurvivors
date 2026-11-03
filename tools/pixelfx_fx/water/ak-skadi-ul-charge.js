// 斯卡蒂放技能的起手信号（11-03 用户「放了技能等于没放」）：脚下 / 剑身周围的水汽和水珠往剑上聚拢（不等距、不等速），聚满一闪，0.18 秒内结束。
// 原点 = 斯卡蒂脚底，聚拢点在身前上方（剑身）。俯视；装饰层 = 水汽和光，核心层 = 聚拢的水珠与那一闪。
import { Particles, Lights, P, Rng, fit, clamp, smooth, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skadi skill charge",
  desc: "Mist and brine droplets are drawn in toward the greatsword from all around, then a short bright pulse.",
  tags: ["water", "charge", "windup", "one-shot"],
  size: [140, 140],
  origin: [70, 80],
  duration: 0.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#0b1529", ...OP.skadi],   // 11-03 §12.6：改用 house.js OP.skadi 7 阶（原水青 #34a8dc / #7fe0f4 和敌方青弹 #33ceff 色差仅 15–18），最暗一阶为压暗底色
    accent: 0,       // 0 / 1 / 2 / 3 = 普攻（不用）/ S1 / S2 / S3：S3 聚得更多更远
    layer: "all",
    seed: 4,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), core = o.layer !== "deco", deco = o.layer !== "core";
  const big = +o.accent >= 3, FX = 10, FY = -26;   // 聚拢点：身前上方
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[5]], haze: C[4] }), lights = new Lights();
  const drops = [];
  for (let i = 0, m = big ? Rg.int(26, 32) : Rg.int(16, 22); i < m; i++) {
    const a = Rg.range(0, TAU), d = Rg.range(26, big ? 64 : 48);
    drops.push({ x: FX + Math.cos(a) * d, y: FY + Math.sin(a) * d * 0.7, t0: Rg.range(0, 0.06), T: Rg.range(0.09, 0.15), s: Rg.range(0.8, 1.6), c: Rg.int(5, 7) });
  }
  let t = 0, flashed = false;
  return {
    update(dt) {
      t += dt;
      if (deco && t < 0.12 && Rg.chance(0.8)) {
        const a = Rg.range(0, TAU), d = Rg.range(30, big ? 60 : 44), x = FX + Math.cos(a) * d, y = FY + Math.sin(a) * d * 0.7;
        ps.spawn(P.VAPOUR, x, y, (FX - x) * 5, (FY - y) * 5, Rg.range(0.12, 0.2), C[4], Rg.range(2, 4));
      }
      if (!flashed && t >= 0.15) {
        flashed = true;
        lights.add(FX, FY, big ? 40 : 28, C[6], 0.8, 0.18);
        for (let i = 0, m = Rg.int(6, 10); i < m; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(40, 110);
          ps.spawn(P.SPARK, FX, FY, Math.cos(a) * sp, Math.sin(a) * sp * 0.7, Rg.range(0.12, 0.22));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (core) for (const d of drops) {   // 聚拢的水珠：沿直线加速吸向剑身，越近越亮
        const u = clamp((t - d.t0) / d.T);
        if (t < d.t0 || u >= 1) continue;
        const e = u * u, x = d.x + (FX - d.x) * e, y = d.y + (FY - d.y) * e;
        p.disc(x, y, d.s * (1 - 0.4 * e), C[Math.min(7, d.c + (e > 0.6 ? 1 : 0))], 1);
      }
      if (core && t >= 0.14 && t < 0.24) {
        const k = 1 - smooth(0.14, 0.24, t);
        p.disc(FX, FY, (big ? 7 : 5) * k + 2, C[7], 0.95 * k);
      }
      if (deco) {
        if (t < 0.16) p.glow(FX, FY, big ? 34 : 24, C[5], 0.5 * smooth(0, 0.15, t));
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
