// 艾雅法拉普攻「火山弹」命中（docs/229 §3 普攻档）：@2x，1 贴图像素 = 1 世界像素，原点 = 爆点。
// 一团不规整的熔岩先白热爆开，外缘按噪声起伏、逐级冷却成暗红；熔滴偏向上方抛出（不等距、不对称），最后碎成余烬。
import { Particles, P, Rng, fit, clamp, ease, noise, noise2 } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla hit",
  desc: "A small lava shell bursts: a white-hot lump pops, its ragged rim cools down the volcano ramp, molten drops fly up and fall as embers.",
  tags: ["impact", "fire", "lava", "one-shot"],
  size: [48, 48],
  origin: [24, 26],
  duration: 0.21,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.eyjafjalla, seed: 5 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[2]] });
  // 熔滴：偏向上方，角度和速度都随机
  for (let i = 0; i < 7; i++) {
    const a = -Math.PI / 2 + Rg.range(-1.5, 1.5), sp = Rg.range(80, 210);
    ps.spawn(P.SPARK, Math.cos(a) * 3, Math.sin(a) * 3, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.09, 0.18));
  }
  const S = o.seed;
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      // 熔岩团：半径先冲出去再收；热度 0.05 s 降一阶，外缘先暗
      const grow = ease.outQuart(clamp(t / 0.06)), r0 = 8 + 8 * grow, fade = 1 - clamp((t - 0.09) / 0.11);
      if (fade > 0) {
        const step = Math.floor(t / 0.05);
        p.shade(-r0 - 4, -r0 - 4, r0 + 4, r0 + 4, (x, y, out) => {
          const a = Math.atan2(y, x), d = Math.hypot(x, y * 1.08);
          const R = r0 * (1 + 0.24 * noise(a * 2.3 + 1.7, S) + 0.12 * noise(a * 6.1, S + 3));
          if (d > R) return;
          const u = d / R;   // 0 芯 → 1 外缘
          // 中段被「掏空」：爆开后中间变成透出的暗洞（不画同心圈，洞的边也按噪声）
          const hole = clamp((t - 0.05) / 0.1) * (0.75 + 0.2 * noise(a * 3.3, S + 9));
          if (u < hole) return;
          const ci = clamp(Math.round(6 - step - u * 2.2), 1, 6);
          // 收尾：按噪声溶解（不是棋盘格），剩下的真半透明
          if (noise2(x * 0.45, y * 0.45, S + 21) * 0.5 + 0.5 > fade + 0.15) return;
          p.blend(x, y, C[ci], fade > 0.6 ? 1 : 0.55 + 0.45 * fade);
        });
      }
      if (t < 0.045) p.disc(0, 0, 6, C[6], 1);
      p.glow(0, 0, 12, C[4], 0.28 * (1 - clamp(t / 0.12)));
      ps.draw(p);
    },
  };
}
