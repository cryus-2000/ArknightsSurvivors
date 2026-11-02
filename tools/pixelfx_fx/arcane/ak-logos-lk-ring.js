// 逻各斯连携的黑金咒文环（静帧，俯视圆，代码压成 sy 0.55 并转动；@2x 344×344，原点 = 中心，目标半径 r + 20 ≈ 170 世界像素）：
// 一道墨色细环、环外一道金边；环内一串长短、间距、笔画数都随机的墨划（像咒文但不是可读字），几处墨点洇开。只一道环。
import { Rng, fit, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Logos link script ring",
  desc: "Logos's link ring of black-gold script: a thin ink ring edged in gold, strung with ink strokes of random length, spacing and stroke count.",
  tags: ["arcane", "ink", "ring", "still"],
  size: [344, 344],
  origin: [172, 172],
  duration: 0.05,
  loop: true,
  fps: 20,
  bg: "dark",
  // 黑金：逻各斯色阶的墨色暗阶 + 连携原定的金边（同旧 fx_lk_lo_ring 的黑金）
  options: { palette: ["#141626", "#2a2d4a", "#545c99", "#8c99ff", "#c9a24a", "#f2d27a", "#ffffff"], seed: 5 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), S = o.seed, R = 160;
  for (let a = 0; a < TAU; a += 0.6 / R) {
    const r = R * (1 + 0.012 * noise(a * 5, S));
    for (let q = -1.5; q <= 1.5; q += 0.75) p.px(Math.cos(a) * (r + q), Math.sin(a) * (r + q), C[Math.abs(q) > 1 ? 1 : 0]);
    p.px(Math.cos(a) * (r + 3), Math.sin(a) * (r + 3), C[noise(a * 14, S + 2) > 0.3 ? 5 : 4]);
  }
  for (let a = Rg.range(0, 0.2); a < TAU - 0.1; a += Rg.range(0.12, 0.34)) {
    const n = Rg.int(1, 4);
    for (let k = 0; k < n; k++) {
      const aa = a + k * 0.022, r0 = R - 6 - Rg.range(0, 6), len = Rg.range(4, 11), dir = Rg.range(-0.9, 0.9);
      for (let s = 0; s < len; s += 0.5) {
        const r = r0 - s * Math.cos(dir), b = aa + (s * Math.sin(dir)) / r;
        p.px(Math.cos(b) * r, Math.sin(b) * r, C[s < 1.5 ? 5 : 4]);
        p.px(Math.cos(b) * (r - 1), Math.sin(b) * (r - 1), C[0]);   // 金色笔画带一道墨影
      }
    }
    if (Rg.chance(0.25)) p.disc(Math.cos(a) * (R - 10), Math.sin(a) * (R - 10), Rg.range(1.5, 3), C[0], 0.8);
  }
}
