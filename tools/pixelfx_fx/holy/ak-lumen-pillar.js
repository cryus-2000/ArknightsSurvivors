// 流明 S1 / S3 灯火光柱（docs/229 技能档）：@2x，1 贴图像素 = 1 世界像素，原点 = 脚底（游戏里 bottom 锚定）。
// 一道光从上方直落到地面，落地那一帧整根爆亮，随后边缘先冷、芯最后冷，光柱收细后从上往下断开；
// 地面泛开一圈不规整的光（透视 sy 0.55，远半圈在后），光屑高低不一、不等距地往上飘。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lumen pillar",
  desc: "A shaft of lantern light lands white-hot, cools from its rims inward, thins and breaks from the top, over a ragged pool of light on the floor.",
  tags: ["holy", "pillar", "light", "heal", "ground", "one-shot"],
  size: [112, 200],
  origin: [56, 160],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, height: 150, radius: 44, seed: 6 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), H = o.height, R = o.radius, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  // 光屑：位置、速度、出现时刻都随机
  for (let i = 0; i < 14; i++) {
    const a = Rg.range(0, TAU), d = Rg.range(0.2, 0.9) * R;
    ps.spawn(P.FLAKE, Math.cos(a) * d, Math.sin(a) * d * SY, Rg.range(-8, 8), -Rg.range(30, 90), Rg.range(0.2, 0.4), Rg.pick([C[5], C[4], C[4]]), Rg.range(1, 2), Rg.range(0.02, 0.2));
  }
  for (let i = 0; i < 6; i++) {
    const a = -Math.PI / 2 + Rg.range(-1.2, 1.2), sp = Rg.range(60, 150);
    ps.spawn(P.SPARK, 0, -2, Math.cos(a) * sp, Math.sin(a) * sp * 0.6, Rg.range(0.1, 0.22), 0, 1, 0.05);
  }
  let t = 0;
  // 地面光：一整圈不规整（噪声外缘），从脚下推出去后淡掉；keep 选远 / 近半圈
  function pool(p, far) {
    const u = t;
    const g = ease.outQuart(clamp(u / 0.18)), rr = R * (0.3 + 0.7 * g), k = 1 - smooth(0.2, 0.55, t);
    if (k <= 0) return;
    p.shade(-rr * 1.3, -rr * SY * 1.3, rr * 1.3, rr * SY * 1.3, (x, y) => {
      if ((y < 0) !== far) return;
      const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (rr * (1 + 0.16 * noise(a * 3.1, S) + 0.07 * noise(a * 8.3, S + 1)));
      if (d > 1) return;
      if (noise2(x * 0.2, y * 0.35, S + 3) * 0.5 + 0.5 > k + 0.3) return;
      // 外沿一道亮边、里面是薄薄一层光（只一圈，不叠第二圈；不按距离分多阶，免得出放射纹）
      const rim = d > 0.78 - 0.1 * noise(a * 5.7, S + 2);
      const ci = clamp(Math.round((rim ? 4 : 2) - (1 - k) * 2.5), 0, 6);
      p.blend(x, y, C[ci], (rim ? 0.9 : 0.35) * Math.min(1, k * 1.4));
    });
  }
  function shaft(p) {
    // 之后收细，0.3 s 起从上往下断开
    const top = -H, bot = 0;   // 20 fps 下光落地不到一帧：首帧就是整根爆亮
    const cut = -H + H * ease.inCubic(smooth(0.28, 0.56, t));   // 断开处往下走
    const w0 = 7.5 * (1 - 0.6 * smooth(0.08, 0.45, t)) + (t < 0.04 ? 3 : 0);
    if (w0 <= 0.6) return;
    for (let y = Math.floor(Math.max(top, cut)); y < bot; y++) {
      const v = (y + H) / H;   // 0 顶 → 1 地
      const w = w0 * (0.7 + 0.3 * v) * (1 + 0.15 * noise(y * 0.13 + t * 30, S + 7));
      for (let x = -Math.ceil(w); x <= Math.ceil(w); x++) {
        const q = Math.abs(x) / w;
        if (q > 1) continue;
        // 冷却：每 0.05 s 降一阶，边先暗、芯最后
        const ci = t < 0.04 ? clamp(Math.round(6.2 - q * 3.4), 3, 6) : clamp(Math.round(6.4 - (t - 0.1) / 0.05 * 0.55 - q * 2.8), 1, 4);
        p.blend(x, y, C[ci], q > 0.75 ? 0.55 : 0.95);
      }
    }
    // 光柱底部溅开的小光冠（只首几帧）
    if (t < 0.16) p.glow(0, -3, 16, C[5], 0.3 * (1 - t / 0.16));
  }
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) { pool(p, true); },
    draw(p) {
      shaft(p);
      pool(p, false);
      ps.draw(p);
    },
  };
}
