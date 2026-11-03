// 铃兰定身标识（画地为牢 / 画地为牢·禁足，注册表 status.stun，docs/242 §14.18，附件在敌人脚下）：1x，原点 = 敌人脚底，循环。
// 旧版是金色双椭圆环 + 四根转辐。本作不画环：脚下三团不等角的贴地小狐火（像三根钉住影子的火桩），各自错相位明暗闪烁；
// 用户 11-04：一律短胖火团（火尖往上跳、外形每 2–3 帧一变），不画细长火舌。按 e.r = 12 画（离脚底 10.5 美术像素、透视 0.5），游戏按 e.r ÷ 12 缩放。
// 分档：E0 ×0.8 / E1 ×1 / E2 ×1.2，E2 质变：每簇旁边多一小团（火桩 → 双桩），火梢淡紫。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, floorLight } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire pin unleashed",
  desc: "A root marker under a held enemy: three small ground foxfire balls at uneven angles around the feet, like stakes pinning its shadow, each flickering on its own beat.",
  tags: ["fire", "status", "stun", "foxfire", "loop"],
  size: [40, 32],
  origin: [20, 20],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 7 },
};

const D = meta.duration, R = 10.5, PY = 0.5, ANG = [0.3, 2.4, 4.3];

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, el = +o.elite, K = SCALE[el];
  const order = ANG.map((a, i) => [Math.sin(a), a, i]).sort((x, y) => x[0] - y[0]);   // 身后的先画
  for (const [, a, i] of order) {
    const x = Math.cos(a) * R, y = Math.sin(a) * R * PY;
    const br = 0.5 + 0.5 * Math.cos(TAU * (t / D + i * 0.33)), heat = 0.6 + 0.4 * br, r = 2.6 * K;
    if (core) {
      if (el === 2) foxClump(p, x - 2.6 * K, y - r * 0.5, r * 0.62, { H, t, fps: meta.fps, seed: S + i * 7 + 3, tips: 2, heat: heat * 0.9, sq: 0.8, acc: true });
      foxClump(p, x, y - r * 0.8, r, { H, t, fps: meta.fps, seed: S + i * 7, tips: 3, heat, up: 1.2, sq: 0.8, acc: el === 2 });
    }
    if (deco) {
      floorLight(p, x, y, 7 * K, 3 * K, F[6], 0.12 + 0.2 * br);
      const u = (t / D * 2 + i * 0.41) % 1;
      ember(p, x, y - 7 * K - 8 * u, 1 - u, 1, [H[0], H[2], H[4], H[6]], i * 2.1 + t * 20);
    }
  }
}
