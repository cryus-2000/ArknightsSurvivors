// 推进之王精二「破阵」地裂（D 组）：@2x 密度，横向帧条（代码沿地裂方向平铺，随寿命换帧：裂开 → 发光 → 冷却 → 暗）。替换 Codex fx_siege_fissure_tile。
// 帧宽 192（≥ 判定长度 180，一般不重复；更长时左右无缝接上）。主裂缝按可平铺噪声起伏、粗细不一，沿途不等距地岔出短支缝。
import { Rng, fit, clamp, tileFbm, tileNoise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Siege fissure",
  desc: "A tileable ground fissure in four life frames (split, glow, cool, dark): a ragged main crack of uneven width with short side cracks at irregular spacing.",
  tags: ["earth", "crack", "ground", "tile"],
  size: [192, 32],
  origin: [96, 16],
  duration: 0.4,
  loop: false,
  fps: 10,
  bg: "ground",
  options: { palette: ["#0e0c0a", "#2a241c", "#4a3e2e", OP.siege[1], OP.siege[2], OP.siege[3], OP.siege[5], "#ffffff"], seed: 5 },
};

const W = 192, PER = 12;   // 噪声周期：W / 16 = 12 格，左右边缘无缝

export function draw(p, t, o) {
  const f = Math.floor(t * 10 + 1e-6);
  if (f >= 4) return;
  const C = fit(o.palette, 8), R = new Rng(o.seed);
  const hot = [7, 6, 4, 2][f], rim = [5, 4, 3, 1][f];
  const yAt = (x) => 5 * (tileFbm((x + 96) / 16, 0.5, PER, 0, o.seed, 2) - 0.5) * 2;
  const wAt = (x) => 1 + 2.2 * tileNoise((x + 96) / 10, 3.3, W / 10, 0, o.seed + 7);
  for (let x = -96; x < 96; x++) {
    const y = yAt(x), w = wAt(x);
    for (let d = -w; d <= w; d++) {
      const q = Math.abs(d) / Math.max(w, 1);
      p.px(x, Math.round(y + d), C[q < 0.4 ? hot : q < 0.8 ? rim : 1]);
    }
    p.px(x, Math.round(y - w - 1), C[f < 2 ? 3 : 1]);
  }
  // 支缝：起点间距随机，离边缘留 6 像素免得跨缝断开
  for (let x = -90 + R.range(0, 10); x < 88; x += R.range(14, 34)) {
    let px = x, py = yAt(x), a = R.sign() * R.range(0.7, 1.3) + (R.chance(0.5) ? Math.PI : 0) * 0;
    const len = R.range(4, 9), dir = R.sign();
    for (let s = 0; s < len; s++) {
      px += Math.cos(a) * 1; py += Math.sin(a) * dir * 1;
      if (Math.abs(px) > 94) break;
      p.px(px, py, C[s < len * 0.5 ? rim : 2]);
    }
  }
  if (f === 0) for (let x = -96; x < 96; x += 2) p.glow(x, yAt(x), 5, C[6], 0.12);
}
