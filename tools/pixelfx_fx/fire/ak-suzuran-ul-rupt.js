// 铃兰终结技「忍冬一斩」刀痕爆裂的一处（ult_fx_c._sz_rupt_chain，pixelfx 放开版，docs/242 §14.15）：1x，原点 = 爆点，刀向 = +x，一次性。
// 旧版是每处 600 颗 ult_burst 粒子 + 一帧冷白圆。本作（11-04 §0）：一个实心主形——顺刀向拉长的噪声边冷白爆块，定帧两帧满白热，
// 再迅速冷成钢灰、塌成两三团往刀口两侧散开的烟；两块有重量的钢灰碎屑抛起落地弹一下。不画圆、不外扩、不撒点；狐火红不在这里（刀口另画）。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, solid, soft, sparkAt, floorLight } from "./_lib.js";

// 忍冬冷白钢灰（暗 → 亮）；沿用终结技定稿的冷白为主（用户 10-31），不进暖橙。待样板收进 house.js（OP.suzuran_ult）。
const COLD = ["#1c1f26", "#2f343e", "#4a515e", "#6d7584", "#9aa3b2", "#c9d0db", "#eef2f7", "#ffffff"];

export const meta = {
  name: "Suzuran ult slash rupture unleashed",
  desc: "One burst along a sword cut: a ragged cold-white block stretched along the cut holds white-hot for two frames, cools fast to steel grey and slumps into two or three puffs drifting off either side, two steel chips tossed and bouncing.",
  tags: ["impact", "ult", "slash", "cold", "one-shot"],
  size: [72, 56],
  origin: [36, 30],
  duration: 0.55,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: COLD, layer: "all", seed: 3 },
};

const NL = noiseFor(0), HOLD = 0.08;   // 定帧两帧：第一帧白热芯，第二帧降一档（白帧超标会被检查拦）

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed;
  const u = clamp((t - HOLD) / (meta.duration - HOLD)), heat = t < HOLD ? 1 : 1 - ease.outCubic(clamp((t - HOLD) / 0.16));
  if (core) {
    // 主形：顺刀向（x）拉长的爆块，定帧后缩小、冷却，噪声边
    const R = 11 * (t < HOLD ? 1 : 1 - 0.55 * ease.outQuad(clamp((t - HOLD) / 0.2)));
    if (t < HOLD + 0.2) p.shade(-R * 2.4, -R * 1.2, R * 2.4, R * 1.2, (x, y) => {
      const d = Math.hypot(x * 0.42, y), a = Math.atan2(y, x) / TAU, rim = R * (0.45 + 0.7 * Math.max(0, pnoise(a * 13, 13, S + 1)) ** 1.1) + 1.2 * pnoise(a * 29, 29, S + 2);
      if (d > rim) return;
      const h = 1 - d / rim;
      const lv = t < 0.042 ? (h > 0.6 ? 0 : h > 0.25 ? 1 : 2) : heat > 0.85 ? (h > 0.45 ? 1 : 2) : heat > 0.45 ? (h > 0.5 ? 2 : 3) : h > 0.5 ? 3 : 4;
      return H[lv];
    });
    // 碎屑：两块钢灰小块，往刀口两侧上方抛起，落地（y = 14）弹一下
    for (const [vx, vy, i] of [[-38, -95, 0], [52, -80, 1]]) {
      const age = t - HOLD * 0.5;
      if (age < 0) continue;
      const [x, y] = sparkAt(vx * 0.05, -2, vx, vy, age, 14, 380, 1.6);
      const k = 1 - clamp(age / (meta.duration - 0.02));
      const c = k > 0.6 ? H[3] : H[5];
      p.px(x, y, c), p.px(x + 1, y, c), p.px(x, y + 1, H[6]), p.px(x + 1, y + 1, H[6]);   // 2×2 钢灰小块
      if (k > 0.75) p.px(x, y, H[1]);
    }
  }
  if (deco) {
    floorLight(p, 0, 14, 30, 7, F[7], 0.5 * heat + 0.12 * (1 - u));   // 爆亮照在地上
    // 烟：冷却后从爆块塌出两三团，往刀口两侧（±y）慢慢散开、变淡
    for (const [sx, sy, r0, i] of [[-6, -1, 6, 0], [5, 1, 7, 1], [13, -1, 5, 2]]) {
      const age = t - HOLD - 0.04 * i;
      if (age < 0) continue;
      const k = clamp(age / (meta.duration - HOLD)), r = r0 * (0.6 + 0.6 * ease.outQuad(k)), a = 0.5 * (1 - k) * (1 - k);
      const cx = sx + 4 * k * Math.sign(sx || 1), cy = sy * (1 + 12 * k) - 5 * k, c = H[k < 0.3 ? 4 : 5];
      // 一团烟 = 三个错开的小团（不成正圆），越散越淡
      for (const [ox, oy, rk] of [[-0.5, 0.2, 0.7], [0.45, -0.25, 0.6], [0.1, 0.5, 0.5]]) soft(p, cx + ox * r, cy + oy * r * 0.7, r * rk, c, a);
    }
  }
}
