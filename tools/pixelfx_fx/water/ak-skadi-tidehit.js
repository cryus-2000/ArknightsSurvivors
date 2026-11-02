// 斯卡蒂精二潮刃命中浪花（docs/229 §7 第 2 批，替 fx_skadi_surge_hit 的棋盘格淡出）：@2x，原点 = 命中点，不旋转。
// 首帧白点爆亮，一簇方向不均的水珠往上和两侧甩出、落下；半透明水雾膨开变薄，0.25 s 内收尽。
import { Particles, Lights, P, Rng, fit, TAU } from "../../core/index.js";

export const meta = {
  name: "Skadi tide hit",
  desc: "Small water hit: a white pinpoint flash, an uneven spray of droplets thrown up and aside that falls back, and a thin vapour puff.",
  tags: ["water", "impact", "hit", "one-shot"],
  size: [64, 64],
  origin: [32, 36],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"],
    seed: 2,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 14, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  lights.add(0, 0, 16, C[6], 0.7, 0.15);
  for (let i = 0; i < 16; i++) {   // 水珠：上方和两侧，角度和速度都不均
    const a = -Math.PI / 2 + Rg.range(-1.4, 1.4) * (Rg.chance(0.3) ? 1.3 : 1), sp = Rg.range(70, 200);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.12, 0.25), C[5 + Rg.int(0, 2)], 1);
  }
  for (let i = 0; i < 4; i++) ps.spawn(P.VAPOUR, Rg.range(-4, 4), Rg.range(-3, 3), Rg.range(-25, 25), Rg.range(-30, 0), Rg.range(0.15, 0.25), C[4], Rg.range(3, 6));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      if (t < 0.1) {
        const k = 1 - t / 0.1;
        p.disc(0, 0, 2 + 4 * (1 - k), C[7], 0.9 * k);
        // 偏心的白色裂口：两臂长短不一
        p.line(-5 * k, 1, 9 * k, -2, C[7], k);
        p.line(1, -7 * k, -1, 4 * k, C[6], k);
      }
      ps.draw(p);
      lights.draw(p);
    },
  };
}
