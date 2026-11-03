// 铃兰狐火印记（S2「儿时的舞乐」受影响目标脚下，pixelfx 放开版，docs/242 §11.2 #6 附件）：1x，原点 = 目标脚底，循环。
// 原作 lisa_skill_02：每个受影响目标身上一圈绿环。本作不画环：两条贴地的「狐尾」小火卷（粗头细尾的逗号形）绕脚底慢转半圈，
// 中间立一簇小狐火；转半圈正好两条互换，循环无缝。游戏按 e.r ÷ 12（0.8–2.0）缩放。
import { fit, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, ember, looped, LAYERS } from "./_lib.js";

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
  options: { palette: ["#3a1a10", "#7a3414", "#c2561a", "#ff8426", "#ffb257", "#ffdca6", "#ffffff"], layer: "all", seed: 3 },
};

const D = meta.duration, NL = noiseFor(D), RX = 11, PY = 0.5;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, rot = (t / D) * Math.PI;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  if (core) {
    // 身后的半圈先画（y < 0 的部分），再画小狐火，再画身前半圈，叠层前后分明
    const curls = (front) => {
      for (let i = 0; i < 2; i++) {
        for (let s = 0; s <= 1; s += 0.01) {
          const a = rot + i * Math.PI + s * 1.9, r = RX * (1 - 0.35 * s);   // 往里卷
          const x = Math.cos(a) * r, y = Math.sin(a) * r * PY;
          if ((y > 0) !== front) continue;
          const half = 1.6 * (1 - s) ** 0.8 + 0.3 * N(8, S, s * 6);
          if (half < 0.35) continue;
          const c = s < 0.25 ? H[front ? 1 : 3] : s < 0.6 ? H[front ? 3 : 4] : H[5];
          for (let q = -half; q <= half; q += 0.5) p.px(x, y + q * 0.7, Math.abs(q) > half * 0.6 ? H[6] : c);
        }
      }
    };
    curls(false);
    flameTongue(p, 0, 0, 7 + 1.5 * N(5, S), 1.8, N(2, S + 1) * 1.5, N, S * 5, H, LAYERS, 0.3, 0.8);
    curls(true);
  }
  if (deco) {
    p.glow(0, -2, 9, F[6], 0.16);
    looped(t, D, 2, S + 20, (r) => ({ x: r.range(-6, 6), vy: -r.range(10, 18), life: r.range(0.35, 0.6), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, q.x, -4 + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 22);
    });
  }
}
