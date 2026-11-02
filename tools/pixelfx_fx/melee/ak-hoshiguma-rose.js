// 星熊「战意」盾斧斩普攻（docs/229 §3 普攻档，替 fx_hoshiguma_slash_rose 的 2.8 倍放大小条）。
// 1x，原点 = 帧中心 = 星熊前方 along 0.5 处（游戏 fit 47 → 每 1x 像素 2 世界像素），正右为出手方向。
// 刀弧圆心在星熊（x = -HALF），半径 = 攻击距离 × 0.85：首帧白热钢刃，随后冷却成色阶；
// 弧尾细、刃头厚，外缘按噪声起伏；刃头甩出两三点火星。≤ 5 帧 @24。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Hoshiguma shield-axe cut",
  desc: "Heavy shield-axe crescent: white-hot steel edge on the first frame cooling down the operator ramp, ragged rim, a few sparks off the head.",
  tags: ["melee", "slash", "basic", "one-shot"],
  size: [44, 56],
  origin: [22, 28],
  duration: 0.21,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: OP.hoshiguma,
    half: 23.5,      // 帧中心到星熊的距离（1x）：攻击距离 94 × along 0.5 / 2
    radius: 40,      // 刀弧半径（1x）：94 × 0.85 / 2
    seed: 4,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), cx = -o.half, R = o.radius;
  const W = C[C.length - 1]; for (let i = 5; i < C.length; i++) C[i] = C[4];   // 近白 ≤ 12%（docs/229 §2.4）：本体只到第 4 阶，白只留核心（W）
  const A0 = -0.62, A1 = 0.62;                      // 刀从上往下扫（俯视），弧端到帧边
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  lights.add(cx + Math.cos(A1) * R, Math.sin(A1) * R, 12, C[5], 0.5, 0.12);
  for (let i = 0; i < 4; i++) {
    const a = A1 + Rg.range(-0.6, 0.5), sp = Rg.range(60, 120);
    ps.spawn(P.SPARK, cx + Math.cos(A1) * (R - 2), Math.sin(A1) * (R - 2), Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.06, 0.14), 0, 1);
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      const sweep = ease.outExpo(clamp((t + 0.03) / 0.06)), tail = smooth(0.05, 0.19, t), cool = clamp(t / 0.15);
      const a1 = A0 + (A1 - A0) * sweep, a0 = A0 + (A1 - A0) * tail;
      if (a1 - a0 < 0.03) { ps.draw(p); return; }
      const W = 9 * (1 - 0.5 * tail);
      for (let y = -27.5; y <= 27.5; y++)
        for (let x = -21.5; x <= 21.5; x++) {
          const dx = x - cx, ang = Math.atan2(y, dx);
          if (ang < a0 || ang > a1) continue;
          const v = (ang - a0) / (a1 - a0);           // 0 尾 → 1 刃头
          const rim = R + 1.3 * noise(ang * 14, o.seed) + 0.6 * noise(ang * 31, o.seed + 3);
          const w = W * Math.pow(Math.sin(Math.PI * Math.min(1, v * 0.62 + 0.05)), 1.2) + 0.6, q = (rim - Math.hypot(dx, y)) / w;
          if (q < 0 || q > 1) continue;
          const ci = q < 0.18 && t < 0.045 ? 6 : clamp(Math.round(5.4 - q * 4.6 - cool * 2.4 - (1 - v) * 1.6), 0, 5);   // 只有首帧刃口白热
          if (q < 0.5) p.px(x, y, C[ci]);
          else p.blend(x, y, C[ci], 1.3 - q);
        }
      ps.draw(p);
      lights.draw(p);
    },
  };
}
