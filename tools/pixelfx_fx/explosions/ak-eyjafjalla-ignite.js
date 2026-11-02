// 艾雅法拉 S2「点燃」爆燃（docs/229 技能档）：导出为 1x（1 贴图像素 = 2 世界像素，radius 44），原点 = 爆点（地面），爆团半径 radius ≈ 伤害半径。
// 一团白热火球爆开，外围几团大小不一、位置不等距的火团鼓出来，外圈先冷、芯最后冷，冷成暗红烟后按噪声溶解；
// 地面留一片不规整的焦痕（透视 sy 0.55），熔滴和火星偏上方飞出。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla ignite",
  desc: "A fireball bursts white-hot, uneven lobes of flame bulge out and cool from the rim inward to dark smoke that dissolves, over a ragged scorch on the floor.",
  tags: ["explosion", "fire", "lava", "one-shot"],
  size: [176, 176],
  origin: [88, 100],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.eyjafjalla, radius: 58, seed: 11 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), R = o.radius, S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[2]] });
  // 火团：角度不等距、距离和大小都随机；越往上越大（火往上走）
  const lobes = [{ a: 0, d: 0, r: R * 0.52, dl: 0, up: 0 }];
  for (let a = Rg.range(0, 0.6); a < TAU - 0.3; a += Rg.range(0.55, 1.15)) {
    const top = Math.sin(a) < 0 ? 1.15 : 0.85;
    lobes.push({ a, d: R * Rg.range(0.32, 0.6), r: R * Rg.range(0.24, 0.4) * top, dl: Rg.range(0, 0.06), up: Rg.range(10, 26) });
  }
  for (let i = 0; i < 16; i++) {
    const a = -Math.PI / 2 + Rg.range(-1.7, 1.7), sp = Rg.range(120, 300);
    ps.spawn(P.SPARK, Math.cos(a) * R * 0.3, Math.sin(a) * R * 0.25 - R * 0.2, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.15, 0.4));
  }
  for (let i = 0; i < 6; i++)
    ps.spawn(P.EMBER, Rg.range(-R * 0.5, R * 0.5), -Rg.range(0, R * 0.6), Rg.range(-30, 30), -Rg.range(40, 90), Rg.range(0.3, 0.5), C[4], 1, Rg.range(0.1, 0.2));
  let t = 0;
  // 某点的火：各火团取最热的那个；热度随时间降，外缘先降
  function fire(x, y) {
    let best = -1, bu = 2;
    for (const l of lobes) {
      const tt = t - l.dl;
      if (tt < 0) continue;
      const g = 0.45 + 0.55 * ease.outQuart(clamp(tt / 0.12)), cx = Math.cos(l.a) * l.d * g, cy = Math.sin(l.a) * l.d * g * 0.8 - R * 0.35 - l.up * clamp(tt / 0.6);
      const dx = x - cx, dy = y - cy, ang = Math.atan2(dy, dx);
      const rr = l.r * (0.55 + 0.45 * g) * (1 + 0.1 * clamp(tt / 0.6)) * (1 + 0.22 * noise(ang * 2.1 + l.a * 7, S) + 0.1 * noise(ang * 5.3 + l.a, S + 4));
      const u = Math.hypot(dx, dy) / rr;
      if (u < bu) { bu = u; best = l; }
    }
    return [bu, best];
  }
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {
      // 焦痕：不规整椭圆，白热 → 色阶冷却 → 暗，0.35 s 后溶解
      const k = 1 - smooth(0.3, 0.58, t), rs = R * (0.5 + 0.5 * ease.outCubic(clamp(t / 0.1)));
      if (k <= 0) return;
      p.shade(-rs * 1.2, -rs * SY * 1.2, rs * 1.2, rs * SY * 1.2, (x, y) => {
        const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (rs * (1 + 0.18 * noise(a * 2.7, S + 30)));
        if (d > 1) return;
        if (noise2(x * 0.18, y * 0.3, S + 31) * 0.5 + 0.5 > k + 0.2) return;
        const ci = clamp(Math.round(4 - t / 0.05 * 0.6 - d * 2.5), 0, 5);
        p.blend(x, y, C[ci], (0.35 + 0.5 * (1 - d)) * Math.min(1, k * 1.5));
      });
    },
    draw(p) {
      const B = R * 1.3;
      const step = t / 0.05;
      const dis = smooth(0.32, 0.6, t);   // 溶解进度
      if (t < 0.58)
        p.shade(-B, -B - R * 0.6, B, B * 0.7, (x, y) => {
          const [u, l] = fire(x, y);
          if (u > 1) return;
          // 冷却：每 0.05 s 降一阶，外缘先暗；芯晚 0.1 s
          const h = t < 0.04 ? 6.7 - u * 1.3 : 6.4 - step * 0.75 - u * 2.6 + (l.d === 0 ? 1 : 0);   // 首帧整团爆亮
          if (dis > 0 && noise2(x * 0.12, y * 0.12, S + 40) * 0.5 + 0.5 < dis * 1.15) return;
          const ci = clamp(Math.round(h), 0, 6);
          // 冷到暗阶的是烟：真半透明
          const a = ci <= 1 ? 0.55 * (1 - dis) + 0.2 : ci === 2 ? 0.85 : 1;
          p.blend(x, y, C[ci], a);
        });
      // 首帧白热芯
      p.glow(0, -R * 0.35, R * 0.9, C[4], 0.3 * (1 - clamp(t / 0.3)));
      ps.draw(p);
    },
  };
}
