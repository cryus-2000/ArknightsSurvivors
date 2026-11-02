// 浊心斯卡蒂技能里飘起的音符（docs/229 §2.2，替 fx_skalter_note 的亮洋红）：@2x，4 帧循环 @8，原点 = 帧中心。
// 用户 11-02 定：保留设定红、靠明暗区分——暗血红的八分音符，近黑描边，符头一点白高光沿符干往下走；不出亮洋红中间阶。
import { fit, clamp } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skadi the Corrupting Heart note",
  desc: "A floating eighth note in deep blood red with a near-black outline and a white glint running down the stem; seamless 4-frame loop.",
  tags: ["music", "note", "loop"],
  size: [32, 40],
  origin: [16, 20],
  duration: 0.5,
  loop: true,
  fps: 8,
  bg: "dark",
  options: { palette: OP.skalter, seed: 1 },
};

// 符头：斜椭圆；符干：右侧竖线；符尾：向右下摆的一撇（形状按帧微微摆动）
function inNote(x, y, sway) {
  const hx = x + 4, hy = y - 9, u = hx * 0.8 + hy * 0.45, v = -hx * 0.45 + hy * 0.8;
  if ((u * u) / 26 + (v * v) / 12 <= 1) return 1;                          // 符头
  if (x >= 0.5 && x <= 2.5 && y >= -12 && y <= 8) return 2;                 // 符干
  const fy = y + 12, fx = x - 2;
  if (fy >= 0 && fy <= 9 && fx >= 0 && fx <= 4 + fy * 0.35 + sway && fx >= fy * 0.55 - 0.5 + sway * 0.5) return 3;   // 符尾
  return 0;
}

export function draw(p, t, o) {
  const C = fit(o.palette, 7), f = Math.floor((t / meta.duration) * 4 + 1e-6) % 4;
  const sway = [0, 0.8, 1.4, 0.6][f], glint = [-11, -5, 1, 7][f];
  for (let y = -19.5; y <= 19.5; y++)
    for (let x = -15.5; x <= 15.5; x++) {
      const k = inNote(x, y, sway);
      if (k) {
        let ci = k === 1 ? 4 : 3;
        if (x + y < -6 && k === 1) ci = 5;                                  // 符头左上受光
        if (k === 2 && Math.abs(y - glint) < 1.5) ci = 6;                    // 白高光沿符干往下走
        if (k === 1 && Math.abs(x + 6) < 1.2 && Math.abs(y - 7) < 1) ci = 6;
        p.px(x, y, C[ci]);
      } else if (inNote(x - 1, y, sway) || inNote(x + 1, y, sway) || inNote(x, y - 1, sway) || inNote(x, y + 1, sway)) {
        p.px(x, y, C[1]);                                                   // 近黑描边，在深色地面上靠高光读出形状
      }
    }
  p.glow(-5, 9, 9, C[4], 0.12);
}
