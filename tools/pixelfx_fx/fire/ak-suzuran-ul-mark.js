// 铃兰狐火印记（S2「儿时的舞乐」受影响目标脚下，pixelfx 放开版，docs/242 §11.2 #6 附件）：1x，原点 = 目标脚底，循环。
// 原作 lisa_skill_02：每个受影响目标身上一圈绿环。本作不画环、不画弯卷长条（用户 11-04 读成触手）：
// 脚边一团立着的小狐火，两团更小的贴地狐火绕脚底慢转半圈（身后的先画），转半圈正好互换，循环无缝；地面受光。游戏按 e.r ÷ 12 缩放。
// 分档：E0 ×0.8 / E1 ×1 / E2 ×1.2，E2 质变：中间一团变三团扇开，火梢淡紫。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, looped, floorLight } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire mark unleashed",
  desc: "A small foxfire mark under a target: a little standing foxfire with two tiny ground foxfires slowly circling the feet.",
  tags: ["fire", "status", "mark", "foxfire", "loop"],
  size: [40, 32],
  origin: [20, 22],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 3 },
};

const D = meta.duration, RX = 10, PY = 0.5;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, el = +o.elite, K = SCALE[el], rot = (t / D) * Math.PI;
  const C = { H, t, fps: meta.fps };
  const orb = (front) => {
    for (let i = 0; i < 2; i++) {
      const a = rot + i * Math.PI, x = Math.cos(a) * RX * K, y = Math.sin(a) * RX * K * PY;
      if ((y > 0) !== front) continue;
      foxClump(p, x, y - 1.6 * K, 2.2 * K, { ...C, seed: S + 10 + i, tips: 2, sq: 0.7, heat: front ? 0.9 : 0.7, up: 0.9 });
    }
  };
  if (core) {
    orb(false);
    if (el === 2) for (const [dx, rk, i] of [[-3.6, 0.62, 1], [3.8, 0.58, 2]]) foxClump(p, dx * K, -2.4 * K, 3 * K * rk, { ...C, seed: S + i * 3, tips: 2, lean: dx > 0 ? 0.3 : -0.3, acc: true });
    foxClump(p, 0, -3 * K, 3 * K, { ...C, seed: S, tips: 3, up: 1.15, acc: el === 2 });
    orb(true);
  }
  if (deco) {
    floorLight(p, 0, 0, 12 * K, 4 * K, F[6], 0.3);
    looped(t, D, 1, S + 20, (r) => ({ x: r.range(-5, 5), vy: -r.range(10, 18), life: r.range(0.35, 0.6), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, q.x, -6 * K + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 22);
    });
  }
}
