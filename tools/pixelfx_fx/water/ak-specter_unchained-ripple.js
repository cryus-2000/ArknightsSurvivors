// 归溟幽灵鲨精一「卷入」（progression.elite1，displace pull，curl_r 160）：1x 帧条（大面积半透明地面圈，@2x 显存超 2 MB），地面透视 sy 0.55，原点 = 本人脚底。
// 游戏里 fit 80：半径 160 时每个 1x 像素 2 世界像素，帧里外沿半径 = 80 px。
// 一道苍白的暗潮从外沿收拢：外缘按噪声起伏、越收越快越亮，身后拖着长短不一、方向朝心的水痕；收到普攻圈附近（约 0.62）时拍碎成水沫。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Specter undertow",
  desc: "A pale undertow ring collapses inward on the floor, speeding up and brightening, dragging uneven inward streaks, then breaks into foam near her blade's reach.",
  tags: ["water", "ring", "pull", "floor", "topdown", "one-shot"],
  size: [176, 104],
  origin: [88, 52],
  duration: 0.42,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.specter_unchained],
    radius: 80,
    inner: 0.62,
    seed: 5,
  },
};

const SY = 0.55, PULL = 0.27;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]], haze: C[3] });
  const rad = (t) => R * (1 - (1 - o.inner) * ease.inCubic(clamp(t / PULL)));
  const jag = (a) => 1 + 0.05 * noise(a * 3.3, o.seed) + 0.03 * noise(a * 11, o.seed + 9);
  // 朝心的水痕：角度、长度、出现早晚都不等
  const streaks = [];
  for (let a = Rg.range(0, 0.25); a < TAU; a += Rg.range(0.16, 0.42))
    streaks.push({ a, L: Rg.range(5, 14), d: Rg.range(0, 0.08) });
  let t = 0, broke = false;

  function ring(p, keepFar) {
    if (t >= PULL + 0.03) return;
    const rc = rad(t), k = Math.max(clamp(t / PULL), 1 - t / 0.05), W = 2.5 + 2.5 * k, B = rc * 1.1 + 2;   // 首帧外沿一闪（爆亮），之后先暗再越收越亮
    p.shade(-B, -B * SY - 1, B, B * SY + 1, (x, y, out) => {
      if ((y < 0) !== keepFar) return;
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / jag(a);
      const q = (r - rc) / W;                              // 0 = 内缘（前沿，朝心）… 1 = 外缘
      if (q < 0 || q > 1) return;
      const c = C[clamp(Math.round(3 + k * 3.4 - q * 2.5 - (keepFar ? 1 : 0) + (t < 0.03 ? 2 : 0)), 1, 7)];
      p.blend(x, y, c, (1 - q * 0.6) * (0.45 + 0.5 * k));   // 暗潮是半透明的，越收越实
    });
  }

  function trails(p, keepFar) {
    if (t >= PULL + 0.06) return;
    const rc = rad(t), k = Math.max(clamp(t / PULL), 1 - t / 0.05);
    for (const s of streaks) {
      const sn = Math.sin(s.a);
      if ((sn < 0) !== keepFar || t < s.d) continue;
      const r0 = rc * jag(s.a) + 1, L = Math.min(s.L * (0.3 + k), R * 1.04 - r0);   // 水痕拖在暗潮外侧，不出外沿
      for (let d = 0; d < L; d += 1) {
        const r = r0 + d, x = Math.cos(s.a) * r, y = sn * r * SY;
        p.blend(Math.round(x), Math.round(y), C[clamp(Math.round(2 + k * 3 - d / L * 2), 1, 6)], (1 - d / L) * (0.35 + 0.5 * k));
      }
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!broke && t >= PULL) {
        broke = true;
        const rc = rad(PULL);
        for (let a = Rg.range(0, 0.4); a < TAU; a += Rg.range(0.4, 0.95)) {
          const x = Math.cos(a) * rc, y = Math.sin(a) * rc * SY;
          const da = a + Math.PI + Rg.range(-0.6, 0.6), sp = Rg.range(15, 45);
          ps.spawn(Rg.chance(0.8) ? P.VAPOUR : P.FLAKE, x, y, Math.cos(da) * sp, Math.sin(da) * sp * SY - Rg.range(5, 20), Rg.range(0.08, 0.14), C[Rg.int(4, 7)], Rg.range(1, 2));
        }
      }
      ps.update(dt);
    },
    drawBack(p) {
      trails(p, true);
      ring(p, true);
    },
    draw(p) {
      trails(p, false);
      ring(p, false);
      ps.draw(p);
    },
  };
}
