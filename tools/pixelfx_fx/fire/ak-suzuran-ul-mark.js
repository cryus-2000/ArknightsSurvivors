// 铃兰狐火印记（S2「儿时的舞乐」受影响目标脚下，pixelfx 放开版，docs/242 §11.2 #6 附件）：1x，原点 = 目标脚底，循环。
// 原作 lisa_skill_02：每个受影响目标身上一圈绿环。本作不画环：两条贴地的「狐尾」小火卷（粗头细尾的逗号形）绕脚底慢转半圈，
// 中间立一簇小狐火；转半圈正好两条互换，循环无缝。游戏按 e.r ÷ 12（0.8–2.0）缩放。
import { fit, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, ember, looped, floorLight, LAYERS, BACK_LAYERS } from "./_lib.js";
import { SCALE, ACC, tongueTip, bladeTip } from "./_suzuran_ul.js";   // 分档体量 + E2 淡紫灵光（组长 B 11-04）
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定，样板 843736ef8）

export const meta = {
  name: "Suzuran foxfire mark unleashed",
  desc: "A small foxfire mark under a target: two little fox-tail curls of flame circling flat on the ground around a tiny standing foxfire.",
  tags: ["fire", "status", "mark", "foxfire", "loop"],
  size: [40, 32],
  origin: [20, 22],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 3 },
};

const D = meta.duration, NL = noiseFor(D), RX = 11, PY = 0.5;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, rot = (t / D) * Math.PI, el = +o.elite, K = SCALE[el];   // 分档：E2 中间一舌 → 三舌、梢淡紫
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  if (core) {
    // 身后的半圈先画（y < 0 的部分），再画小狐火，再画身前半圈，叠层前后分明
    const curls = (front) => {
      for (let i = 0; i < 2; i++) {
        for (let s = 0; s <= 1; s += 0.01) {
          const a = rot + i * Math.PI + s * 1.9, r = RX * K * (1 - 0.35 * s);   // 往里卷
          const x = Math.cos(a) * r, y = Math.sin(a) * r * PY;
          if ((y > 0) !== front) continue;
          const half = 1.6 * K * (1 - s) ** 0.8 + 0.3 * N(8, S, s * 6);
          if (half < 0.35) continue;
          const c = s < 0.25 ? H[front ? 1 : 3] : s < 0.6 ? H[front ? 3 : 4] : H[5];
          for (let q = -half; q <= half; q += 0.5) p.px(x, y + q * 0.7, Math.abs(q) > half * 0.6 ? H[6] : c);
        }
      }
    };
    curls(false);
    const mh = (7 + 1.5 * N(5, S)) * K, msx = N(2, S + 1) * 1.5;
    if (el === 2) for (const [dx, hk, j] of [[-3.5, 0.7, 1], [3.5, 0.62, 2]]) {
      flameTongue(p, dx, 0.5, mh * hk, 1.4 * K, dx * 0.4, N, S * 5 + j, H, BACK_LAYERS, 0.3, 0.8);
      tongueTip(p, dx, 0.5, mh * hk, 1.4 * K, dx * 0.4, N, S * 5 + j, BACK_LAYERS, 0.3, 0.8);
    }
    flameTongue(p, 0, 0, mh, 1.8 * K, msx, N, S * 5, H, LAYERS, 0.3, 0.8);
    if (el === 2) tongueTip(p, 0, 0, mh, 1.8 * K, msx, N, S * 5, LAYERS, 0.3, 0.8);
    curls(true);
  }
  if (deco) {
    floorLight(p, 0, 0, 12, 4, F[6], 0.3);
    looped(t, D, 2, S + 20, (r) => ({ x: r.range(-6, 6), vy: -r.range(10, 18), life: r.range(0.35, 0.6), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, q.x, -4 + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 22);
    });
  }
}
