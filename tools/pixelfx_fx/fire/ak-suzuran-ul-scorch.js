// 铃兰狐火灼印（精一「狐火灼印」：被狐火打中的敌人脚下，pixelfx 放开版，docs/242 §11.2 #6 附件）：1x，原点 = 敌人脚底，循环。
// 旧版是一枚金色小圆印（Codex fx_suzuran_seal）。本作不画环：一块贴地、边缘不规则的焦痕，里面几点余烬一明一暗地烧，
// 偶尔窜起一条很矮的火苗；颜色压在暖橙的暗半段，和队友脚下的狐火印记（亮、带小火苗）分开。游戏按 e.r ÷ 12（0.8–2.0）缩放。
import { fit, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameTongue, LAYERS } from "./_lib.js";
import { SCALE, ACC, tongueTip, bladeTip } from "./_suzuran_ul.js";   // 分档体量 + E2 淡紫灵光（组长 B 11-04）
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire brand unleashed",
  desc: "A smouldering scorch on the ground under a branded enemy: a ragged dark patch with embers pulsing in it and a tiny flame licking up now and then.",
  tags: ["fire", "status", "mark", "foxfire", "loop"],
  size: [36, 24],
  origin: [18, 14],
  duration: 1.2,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 5 },
};

const D = meta.duration, NL = noiseFor(D), RX0 = 10, PY = 0.5;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D, el = +o.elite, K = SCALE[el], RX = RX0 * K;   // 分档：E2 窜起的火苗变两条、苗梢淡紫
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  if (core) {
    // 焦痕：噪声边的压扁斑块，外圈暗、内圈余烬色（不画轮廓线）
    p.shade(-RX - 2, -RX * PY - 2, (RX + 2) * 2, (RX * PY + 2) * 2, (x, y) => {
      const a = Math.atan2(y / PY, x) / TAU, d = Math.hypot(x, y / PY), rim = RX * (0.75 + 0.25 * pnoise(a * 7, 7, S));
      if (d > rim) return;
      const h = 1 - d / rim + 0.25 * pnoise(x * 0.4 + 3, 13, S + 1) * pnoise(y * 0.6 + 5, 7, S + 2);
      return h > 0.55 ? H[6] : h > 0.25 ? H[7] : H[8];
    });
    // 余烬：几点固定位置一明一暗（各自错相位）
    for (let i = 0; i < 5; i++) {
      const a = i * 2.3 + S, r = RX * (0.2 + 0.12 * i), x = Math.cos(a) * r, y = Math.sin(a) * r * PY;
      const b = 0.5 + 0.5 * Math.sin(TAU * (ph * (i % 2 ? 1 : 2) + i * 0.37));
      p.px(x, y, b > 0.7 ? H[2] : b > 0.35 ? H[4] : H[6]);
      if (b > 0.8) p.px(x + 1, y, H[4]);
    }
    // 偶尔一条很矮的火苗（一个循环里窜一次）
    const u = (ph * 1 + 0.3) % 1, g = u < 0.35 ? Math.sin(Math.PI * u / 0.35) : 0;
    if (g > 0.1) flameTongue(p, 2, 0, 6 * K * g, 1.4 * K, 1, N, S * 3, H, LAYERS, 0.3, 0.6);
    if (g > 0.1 && el === 2) {
      flameTongue(p, -3, 0.5, 4.5 * K * g, 1.2 * K, -1, N, S * 3 + 1, H, LAYERS, 0.3, 0.6);
      if (g > 0.3) tongueTip(p, 2, 0, 6 * K * g, 1.4 * K, 1, N, S * 3, LAYERS, 0.3, 0.6), tongueTip(p, -3, 0.5, 4.5 * K * g, 1.2 * K, -1, N, S * 3 + 1, LAYERS, 0.3, 0.6);
    }
  }
  if (deco) p.glow(0, 0, 8, F[5], 0.1 + 0.06 * Math.sin(TAU * ph * 2));
}
