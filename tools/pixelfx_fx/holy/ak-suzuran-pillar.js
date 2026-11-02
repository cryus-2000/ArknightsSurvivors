// 铃兰狐火光柱（docs/229 技能档）：@2x，1 贴图像素 = 1 世界像素，原点 = 脚底。height 控制两档尺寸（中心大柱 / 光域边缘小柱）。
// 狐火从地面一窜而起：首帧整根爆亮，火舌左右摆、边缘按噪声起伏，顶端收成摇摆的火苗尖；
// 之后外缘先冷、芯最后冷，从下往上收走，顶上散成几点狐火往上飘。脚下一小片不规整的暖光（透视 sy 0.55）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran foxfire pillar",
  desc: "Foxfire leaps up from the floor white-hot, its tongues sway into a flickering tip, then it cools from the rims and lifts away into drifting wisps.",
  tags: ["holy", "pillar", "fire", "foxfire", "one-shot"],
  size: [96, 300],
  origin: [48, 150],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, height: 130, seed: 4 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), H = o.height, S = o.seed, W = Math.max(5, H * 0.075);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  for (let i = 0; i < Math.round(H / 18); i++)
    ps.spawn(P.EMBER, Rg.range(-W, W), -H * Rg.range(0.5, 1), Rg.range(-15, 15), -Rg.range(30, 70), Rg.range(0.15, 0.24), Rg.pick([C[5], C[4]]), 1, Rg.range(0.12, 0.3));
  let t = 0;
  // 某高度火柱的中心偏移和半宽
  const sway = (y) => 3.5 * noise(y * 0.035 - t * 9, S) * (-y / H);
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {
      const k = 1 - smooth(0.15, 0.5, t), r = W * 3.2;
      if (k <= 0) return;
      p.shade(-r * 1.3, -r * SY * 1.3, r * 1.3, 0, (x, y) => {
        const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (r * (1 + 0.2 * noise(a * 3.3, S + 2)));
        if (d > 1) return;
        p.blend(x, y, C[clamp(Math.round(4 - d * 2 - (1 - k) * 2), 0, 6)], 0.5 * (1 - d) * k + 0.1);
      });
    },
    draw(p) {
      // 从下往上收走：底端 lift 往上爬；整根高度先冲到顶
      const top = -H * (0.75 + 0.25 * ease.outQuart(clamp(t / 0.08))), lift = -H * ease.inQuad(smooth(0.25, 0.55, t));
      const w0 = W * (1 - 0.45 * smooth(0.1, 0.45, t)) + (t < 0.04 ? W * 0.4 : 0);
      for (let y = Math.floor(top); y < Math.min(0, lift); y++) {
        const v = -y / H, cx = sway(y);
        const tip = Math.pow(clamp((y - top) / (H * 0.3)), 0.6);   // 顶端收成火苗尖
        const w = w0 * (1 - 0.4 * v) * tip * (1 + 0.25 * noise(y * 0.11 - t * 14, S + 5));
        for (let x = Math.floor(cx - w); x <= Math.ceil(cx + w); x++) {
          const q = Math.abs(x - cx) / w;
          if (q > 1) continue;
          if (lift < 0 && y > lift - 6 && noise2(x * 0.4, y * 0.4, S + 8) > (y - lift + 6) / 6 - 1) continue;   // 收走的断口按噪声，不是平切
          const ci = t < 0.04 ? clamp(Math.round(6.8 - q * 1.8), 4, 6) : clamp(Math.round(6.2 - (t - 0.04) / 0.05 * 0.6 - q * 2.6 - v * 0.8), 1, 5);
          p.blend(x, y, C[ci], q > 0.7 ? 0.6 : 0.95);
        }
      }
      if (t < 0.12) p.glow(0, -H * 0.4, W * 3, C[5], 0.3 * (1 - t / 0.12));
      ps.draw(p);
    },
  };
}
