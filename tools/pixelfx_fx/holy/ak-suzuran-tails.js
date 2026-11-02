// 铃兰精二九尾虚影（循环 4 帧 @4，@2x 128×96，原点 (64, 92) = 腰后尾根；游戏 alpha 0.45、按朝向翻转，画在人物之下）：
// 九条狐尾从尾根往上扇开，张角和长短各不相同（不等距），尾尖白金、尾身金色、根部暗，各自按不同相位慢慢摆；实色画，透明度由游戏统一给。
import { fit, clamp, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Suzuran nine tails",
  desc: "Suzuran's ghostly nine tails fanning up behind her: nine golden tails of different angle and length swaying out of step, white-gold at the tips.",
  tags: ["holy", "fox", "tails", "aura", "loop"],
  size: [128, 96],
  origin: [64, 92],
  duration: 1,
  loop: true,
  fps: 4,
  bg: "dark",
  options: { palette: OP.suzuran, seed: 9 },
};

// 每条尾：张角（弧度，0 = 正上）、长度、粗细、摆动相位
const TAILS = [[-1.25, 70, 6, 0.1], [-0.95, 80, 7, 0.6], [-0.62, 86, 7.5, 0.3], [-0.33, 90, 8, 0.85], [0.02, 92, 8.5, 0.45],
  [0.31, 88, 8, 0.15], [0.66, 84, 7.5, 0.7], [0.97, 76, 7, 0.4], [1.3, 66, 6, 0.95]];

export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration;
  for (const [a0, L, W, p0] of TAILS) {
    const sway = 0.08 * Math.sin((ph + p0) * TAU);
    for (let s = 0; s <= 0.93; s += 0.5 / L) {
      // 尾身先往外再往上弯：角度随 s 往竖直收一点、加摆动
      const a = a0 * (1 - 0.35 * s) + sway * s * 1.6, r = L * 0.78 * s;
      const x = Math.sin(a) * r, y = -Math.cos(a) * r;
      const w = Math.max(1, W * Math.sin(Math.PI * Math.min(1, s * 1.05 + 0.08)) * (1 + 0.12 * noise(s * 6 + a0, o.seed)));
      for (let q = -w; q <= w; q += 0.8) {
        const e = Math.abs(q) / Math.max(0.5, w);
        const ci = clamp(Math.round(1.5 + s * 3 - e * 1.5), 1, s > 0.85 && e < 0.4 ? 5 : 4);
        p.px(x + Math.cos(a) * q, y + Math.sin(a) * q, C[ci]);   // 实色（游戏里整张再乘 alpha 0.45），叠画不出摩尔纹
      }
    }
  }
}
