// 星熊精二「般若回旋」飞盾擦过敌人的火星（docs/229，替 fx_hoshiguma_saw_spark 的绿色小点）：@2x 32×32，4 帧 @20，原点 = 帧中心。
// 盾缘刮出一小撮火星：首帧白点 + 短偏心闪，四五道长短不一的火星往一侧甩出、拉长、冷却成星熊色阶的暗金。
import { Particles, P, Rng, fit } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Hoshiguma saw spark",
  desc: "Sparks scraped off the spinning shield: a white pinpoint with a short off-centre flash, a few uneven sparks flung to one side cooling to dark gold.",
  tags: ["impact", "spark", "one-shot"],
  size: [32, 32],
  origin: [16, 16],
  duration: 0.2,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.hoshiguma, seed: 4 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[4], C[3], C[2], C[1]] });   // 火星头用第 4 阶（近白 ≤ 12%）
  const W = C[C.length - 1]; for (let i = 5; i < C.length; i++) C[i] = C[4];   // 近白 ≤ 12%（docs/229 §2.4）：本体只到第 4 阶，白只留核心（W）
  for (let i = 0; i < 6; i++) {
    const a = -0.6 + Rg.range(-0.7, 0.9), sp = Rg.range(80, 150);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.06, 0.14), 0, 1);
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      if (t < 0.05) { p.disc(0, 0, 1.6, C[6], 1); p.line(-3, 1, 7, -2, C[6]); }
      ps.draw(p);
    },
  };
}
