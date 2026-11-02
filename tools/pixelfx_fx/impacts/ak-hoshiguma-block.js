// 星熊完全格挡（docs/229，替 fx_hoshiguma_block 的等距放射线 + 同心圈）：@2x，原点 = 盾面受击点，挂在盾牌精灵上（JSON scale 1.0 → 1 世界像素 / 贴图像素）。
// 首帧白热偏心十字闪（朝外一臂最长），一道只有半圈、外缘不齐的金色弧光沿盾面扫开，几片钢屑和火星往外上方崩，0.25 s 收尽。
import { Particles, Lights, P, Rng, fit, clamp, smooth, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Hoshiguma perfect block",
  desc: "Perfect block on the shield face: an off-centre white-hot cross flash, a single ragged half-arc of gold sweeping across the face, steel chips and sparks thrown up and out.",
  tags: ["impact", "block", "shield", "one-shot"],
  size: [80, 80],
  origin: [40, 40],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.hoshiguma, seed: 5 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  lights.add(0, 0, 16, C[5], 0.3, 0.15);
  for (let i = 0; i < 10; i++) {   // 火星：集中在右上（外侧），角度、速度、寿命各异
    const a = -0.5 + Rg.range(-1.0, 0.8), sp = Rg.range(90, 240);
    ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.08, 0.2), 0, 1);
  }
  for (let i = 0; i < 4; i++) {    // 钢屑：暗色小块
    const a = -0.4 + Rg.range(-1.2, 1.0), sp = Rg.range(50, 120);
    ps.spawn(P.MOTE, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.15, 0.25), C[2], 1);
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      if (t < 0.1) {   // 偏心十字闪：右臂最长、左臂最短
        const k = 1 - t / 0.1, c = t < 0.05 ? C[6] : C[5];
        p.line(0, 0, 22 * k, -3 * k, c); p.line(0, 0, -7 * k, 1 * k, c);
        p.line(0, 0, 2 * k, -14 * k, c); p.line(0, 0, -1 * k, 9 * k, c);
        p.disc(0, 0, 3 * k + 1, C[6], 0.9 * k);
      }
      // 半圈弧光：从 -1.9 扫到 0.9 rad，外缘按噪声起伏，随时间冷却变暗
      const sw = smooth(0, 0.08, t), fade = 1 - smooth(0.1, 0.25, t);
      if (fade > 0) {
        const a0 = -1.9, a1 = a0 + 2.8 * sw;
        for (let a = a0; a < a1; a += 0.025) {
          const v = (a - a0) / 2.8, R = 15 + 3 * sw + 1.6 * noise(a * 7, o.seed), w = 2.2 * Math.sin(Math.PI * Math.min(1, v * 1.1)) + 0.4;
          for (let d = 0; d < w; d += 0.6) {
            const ci = clamp(Math.round(6 - d * 1.2 - (1 - fade) * 3 - (1 - v) * 1.2), 1, 6);
            p.blend(Math.cos(a) * (R - d), Math.sin(a) * (R - d), C[ci], fade);
          }
        }
      }
      ps.draw(p);
      lights.draw(p);
    },
  };
}
