// 能天使连携「爆炸剑雨」落点爆炸（D 组）：@2x 密度（1 像素 = 1 世界像素），原点 = 爆点，判定半径 46。替换借用的终结技帧条 fx_ult_exusiai_burst_front。
// 首帧白芯 + 金色爆团（几团偏心火球叠成不规整外形），冷却往暖橙红走（不进敌方品红区），火星往外抛、带一点淡烟。
import { Particles, Lights, P, Rng, fit, clamp, ease, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Exusiai burst",
  desc: "A small grenade burst: a white core frame, a lumpy gold fireball of off-centre blobs cooling to warm orange-red, sparks thrown out and a thin wisp of smoke.",
  tags: ["explosion", "gun", "one-shot"],
  size: [112, 112],
  origin: [56, 60],
  duration: 0.45,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#1a0c08", "#4a1a10", "#9a3418", "#e0682a", "#ffb040", "#ffe08a", "#fff6dc", "#ffffff"], radius: 40, seed: 12 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R0 = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[3]] }), lights = new Lights();
  lights.add(0, 0, R0 * 1.2, C[5], 0.5, 0.22);
  for (let i = 0; i < 14; i++) {
    const a = Rg.range(0, TAU), sp = Rg.range(120, 320);
    ps.spawn(P.SPARK, Math.cos(a) * 4, Math.sin(a) * 4, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.08, 0.22));
  }
  for (let i = 0; i < 5; i++) {
    const a = Rg.range(0, TAU);
    ps.spawn(P.SMOKE, Math.cos(a) * R0 * 0.3, Math.sin(a) * R0 * 0.3, Math.cos(a) * 20, Math.sin(a) * 20 - 15, Rg.range(0.25, 0.35), 0, Rg.range(5, 9), 0.08);
  }
  const blobs = [[0, 0, 0.62]];
  for (let i = 0; i < 4; i++) { const a = Rg.range(0, TAU), d = Rg.range(0.25, 0.45); blobs.push([Math.cos(a) * d, Math.sin(a) * d, Rg.range(0.3, 0.5)]); }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); lights.update(dt); },
    draw(p) {
      ps.draw(p, "back");
      const u = t / 0.28;
      if (u < 1) {
        const rr = R0 * (0.45 + 0.55 * ease.outQuart(clamp(u * 2.5)));
        // 几团偏心火球合成一个外形（取各团里最「深」的那团算颜色），边缘按噪声起伏
        const B = Math.ceil(rr * 1.1);
        for (let y = -B; y <= B; y++)
          for (let x = -B; x <= B; x++) {
            let f = -9;
            for (const [dx, dy, s] of blobs) f = Math.max(f, 1 - Math.hypot(x - dx * rr, y - dy * rr) / (rr * s));
            f += 0.1 * noise(Math.atan2(y, x) * 3, o.seed);
            if (f <= 0) continue;
            const ci = clamp(Math.round(4 + f * 4 - u * 5.5), 1, 7);
            p.blend(x, y, C[ci], (1 - u * u) * Math.min(1, f * 4));
          }
        if (t < 0.03) p.circle(0, 0, R0 * 0.35, C[7]);
        p.glow(0, 0, R0, C[5], 0.3 * (1 - u));
      }
      ps.draw(p, "front");
      lights.draw(p);
    },
  };
}
