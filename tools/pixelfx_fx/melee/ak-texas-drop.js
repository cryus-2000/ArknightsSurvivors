// 德克萨斯精二残像路径上落下的剑（docs/229，替 fx_texas_sword_drop 的蓝金剑）：@2x 24×80，5 帧 @20；
// JSON anchor [6, 38]（1x）= 剑尖 (12, 76)，fall_frames 4：第 0–3 帧下落（剑身 + 上方长短不一的拖光，逐帧变短），第 4 帧插地白闪。剑色按 PRTS「橙剑」#FFE053。
import { fit, clamp } from "../../core/index.js";

export const meta = {
  name: "Texas falling sword",
  desc: "Sword dropping along the afterimage path: four falling frames with uneven light trails shortening as it lands, then a white flash as it plants.",
  tags: ["melee", "sword", "rain", "sheet"],
  size: [24, 80],
  origin: [12, 76],
  duration: 0.25,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#2a1606", "#5c3208", "#a8620e", "#f0a020", "#ffe053", "#ffe58a", "#ffffff"], seed: 3 },
};

const L = 40;
export function draw(p, t, o) {
  if (t >= meta.duration - 1e-6) return;
  const C = fit(o.palette, 7), f = Math.floor(t * meta.fps + 1e-6);
  C[6] = C[5];   // 近白 ≤ 12%（docs/229 §2.4）：本体不用纯白，亮处交给光晕层
  for (let d = 0; d <= L; d++) {
    const guard = d >= 28 && d <= 29, grip = d > 29, w = guard ? 6 : grip ? 0.7 : d < 5 ? d * 0.45 : 2.2;
    for (let x = -w; x <= w + 0.01; x++) {
      let ci = grip ? (d === 33 || d === 37 ? 1 : 2) : guard ? (x < 0 ? 4 : 3) : x < -0.5 ? 5 : x < 1 ? 4 : 3;
      if (!grip && !guard && Math.abs(x) < 0.5 && d > 4) ci = 6;
      p.px(x, -d, C[clamp(ci + (f === 4 ? 1 : 0), 1, 6)]);
    }
  }
  if (f < 4) {
    for (const [x, len, a] of [[-2, 30, 0.45], [0, 34, 0.75], [1, 18, 0.4], [3, 24, 0.3]]) {
      const n = len * (1 - f * 0.22);
      for (let k = 0; k < n; k++) p.blend(x, -L - 1 - k, C[clamp(Math.round(5 - (k / n) * 4), 1, 5)], a * (1 - k / n));
    }
  } else {
    for (let x = -8; x <= 10; x++) p.blend(x, 0, C[Math.abs(x) > 5 ? 5 : 6], 0.9);
    p.glow(0, -2, 10, C[5], 0.3);
  }
}
