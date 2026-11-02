// 德克萨斯冲刺斩的刀痕（docs/229，替 fx_texas_dash 的棋盘格尾 + 等距竖条）：@2x 128×32，4 帧 @20；
// seg_texas 按冲刺长度沿 x 拉伸、右端锚定（anchor 63/64），所以整条朝右、终点在右边缘。
// 一道细长的斩线：右端刃口白热、往左冷却成琥珀再到深褐，上下几根长短不一的残光线；第 2 帧起从左往右断开、碎成小光点。PRTS 橙剑 #FFE053。
import { fit, clamp, noise } from "../../core/index.js";

export const meta = {
  name: "Texas dash cut",
  desc: "Dash slash trail: a long thin cut white-hot at the right end cooling through amber to dark brown, a few uneven afterglow lines, breaking apart from the left into motes.",
  tags: ["melee", "dash", "trail", "sheet"],
  size: [128, 32],
  origin: [64, 16],
  duration: 0.2,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#2a1606", "#5c3208", "#a8620e", "#f0a020", "#ffe053", "#fff6c4", "#ffffff"], seed: 6 },
};

const LINES = [[-6, 0.55, 0.5], [-3, 0.8, 0.7], [4, 0.4, 0.45], [7, 0.25, 0.35]];   // [y, 长度占比, 亮度]：行距与长短不等
export function draw(p, t, o) {
  if (t >= meta.duration - 1e-6) return;
  const C = fit(o.palette, 7), f = Math.floor(t * meta.fps + 1e-6), cut = [0, 0.25, 0.6, 0.85][f];   // 从左往右断开的进度
  for (let x = -63; x <= 63; x++) {
    const u = (x + 63) / 126;                                   // 0 左 → 1 右（刃口）
    if (u < cut) continue;
    const w = 0.5 + 2.2 * Math.pow(u, 1.6);
    const ci = clamp(Math.round(1 + u * 5.5 - f * 1.2), 0, 6);
    for (let y = -w; y <= w; y++) p.blend(x, y, C[clamp(ci - (Math.abs(y) > w - 1 ? 1 : 0), 0, 6)], u < 0.15 ? u / 0.15 : 1);
  }
  for (const [y, L, b] of LINES) {
    const x0 = 63 - L * 126;
    for (let x = x0; x < 60; x++) {
      const u = (x + 63) / 126;
      if (u < cut + 0.1 || noise(x * 0.3 + y, o.seed) > 0.55) continue;
      p.blend(x, y, C[clamp(Math.round(2 + u * 3 - f), 1, 5)], b * (1 - f * 0.25));
    }
  }
  if (f >= 2) for (let i = 0; i < 10; i++) {                    // 断口处的碎光
    const x = -63 + (cut - 0.1 + noise(i * 1.7, o.seed + 3) * 0.12) * 126 + i * 3, y = noise(i * 2.9, o.seed + 4) * 6;
    p.px(x, y, C[4 + (i % 2)]);
  }
  if (f === 0) p.glow(58, 0, 8, C[5], 0.25);
}
