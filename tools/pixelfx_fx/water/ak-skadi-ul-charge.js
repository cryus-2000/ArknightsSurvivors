// 斯卡蒂放技能的起手信号（11-03 用户「放了技能等于没放」）：脚下 / 剑身周围的水汽和水珠往剑上聚拢（不等距、不等速），聚满一闪，0.18 秒内结束。
// v2（11-04 总组长：四周撒一圈方块小点 = 装饰撒点）：改成 3–5 道水流从身边绕弧收进剑身，收满一闪（短十字，不画圆盘、不放圆光）。
// 原点 = 斯卡蒂脚底，聚拢点在身前上方（剑身）。俯视；装饰层 = 水汽和光，核心层 = 聚拢的水珠与那一闪。
import { Rng, fit, clamp, smooth, ease, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skadi skill charge",
  desc: "A few curving streams of sea water are drawn in toward the greatsword, then a short bright glint.",
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
  // 水流：从身边不同方向起，绕一段弧（同一旋向）收进聚拢点；起点 / 先后 / 粗细都不一样
  const streams = [], n = big ? Rg.int(4, 5) : 3, a00 = Rg.range(0, TAU), spin = Rg.chance(0.5) ? 1 : -1;
  for (let i = 0; i < n; i++) streams.push({ a: a00 + (i + Rg.range(-0.25, 0.25)) * TAU / n, d: Rg.range(30, big ? 54 : 42), turn: spin * Rg.range(1.0, 1.6), t0: Rg.range(0, 0.04), T: Rg.range(0.11, 0.15), w: Rg.range(1.2, 2.0) * (big ? 1.2 : 1) });
  const at = (s, u) => {   // u = 0 起点，1 = 聚拢点；沿收拢的螺旋
    const r = s.d * (1 - u), a = s.a + s.turn * u;
    return [FX + Math.cos(a) * r, FY + Math.sin(a) * r * 0.7];
  };
  let t = 0;
  return {
    update(dt) { t += dt; },
    drawBack() {},
    draw(p) {
      if (core) for (const s of streams) {   // 水流头往里走、尾巴跟着收，头亮尾暗、越近越细
        const u = clamp((t - s.t0) / s.T);
        if (t < s.t0 || u >= 1) continue;
        const hd = ease.inQuad(u), tl = Math.max(0, hd - 0.45);
        for (let v = tl; v <= hd; v += 0.012) {
          const [x, y] = at(s, v), f = (v - tl) / Math.max(0.01, hd - tl), w = s.w * (0.4 + 0.6 * f) * (1 - 0.5 * v);
          for (let k = -w; k <= w; k += 0.6) p.px(x + k * 0.6, y + k * 0.8, C[clamp(Math.round(3 + f * 3.2 - Math.abs(k) / Math.max(w, 0.5)), 2, 7)]);
        }
      }
      if (core && t >= 0.14 && t < 0.24) {   // 收满一闪：短十字（不画圆盘）
        const k = 1 - smooth(0.14, 0.24, t), L = (big ? 7 : 5) * k + 1;
        for (let d = -L; d <= L; d += 0.5) { p.px(FX + d, FY, C[7]); p.px(FX, FY + d * 0.8, C[7]); }
      }
      if (deco && t < 0.24) for (const s of streams) {   // 光沿水流走（glowLine），不是一盏圆光
        const u = clamp((t - s.t0) / s.T);
        if (ease.inQuad(u) < 0.12) continue;   // 水流还没拉开时不铺光（零长度的光带就是一颗圆点）
        const [x0, y0] = at(s, Math.max(0, ease.inQuad(u) - 0.3)), [x1, y1] = at(s, ease.inQuad(u));
        p.glowLine(x0, y0, x1, y1, 6, C[5], 0.25 * (1 - smooth(0.14, 0.24, t)));
      }
    },
  };
}
