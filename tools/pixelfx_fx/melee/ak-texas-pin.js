// 德克萨斯精一钉剑（docs/229，替 fx_texas_pin_sword 的蓝金剑）：@2x 24×48，4 帧 @12；JSON anchor [6, 22]（1x）= 剑尖 (12, 44)，
// stay：播完停在末帧插在敌人身上，所以末帧是完整的剑（不空）。第 0 帧插入白闪，1–2 帧冷却，3 帧静止发微光。剑色按 PRTS「橙剑」#FFE053。
import { fit, clamp } from "../../core/index.js";

export const meta = {
  name: "Texas pin sword",
  desc: "Originium sword pinned into an enemy: a white flash as it lands, cooling over two frames, then held with a faint amber glow on the last frame.",
  tags: ["melee", "sword", "pin", "sheet"],
  size: [24, 48],
  origin: [12, 44],
  duration: 0.25,
  loop: false,
  fps: 12,
  bg: "dark",
  options: { palette: ["#2a1606", "#5c3208", "#a8620e", "#f0a020", "#ffe053", "#fff6c4", "#ffffff"], seed: 1 },
};

const L = 34;
export function draw(p, t, o) {
  const C = fit(o.palette, 7), f = Math.min(3, Math.floor(t * meta.fps + 1e-6)), heat = [2, 1, 0, 0][f];
  for (let d = 0; d <= L; d++) {
    const guard = d >= 23 && d <= 24, grip = d > 24, w = guard ? 6 : grip ? 0.6 : d < 4 ? d * 0.45 : 1.8;
    for (let x = -w; x <= w + 0.01; x++) {
      let ci = grip ? (d === 28 || d === 31 ? 1 : 2) : guard ? (x < 0 ? 4 : 3) : x < -0.5 ? 5 : x < 1 ? 4 : 3;
      if (!grip && !guard && Math.abs(x) < 0.5 && d > 3) ci = 6;
      p.px(x, -d, C[clamp(ci + heat, 1, 6)]);
    }
  }
  if (f === 0) { for (let x = -8; x <= 9; x++) p.blend(x, 0, C[Math.abs(x) > 5 ? 5 : 6], 0.9); p.glow(0, -2, 10, C[5], 0.3); }
  if (f === 3) p.glow(0, -12, 7, C[4], 0.12);
}
