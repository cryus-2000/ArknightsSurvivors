// 铃兰大狐火（三火归一 / 精二九尾祈愿，pixelfx 放开版，docs/242）：原点 = 火头，正右为飞行方向，循环，直线贯穿。
// 原作 S2 lisa_skill_02_start：三团狐火聚拢合一再射出。用户 11-04（长条读成触手）：火头是一大团圆胖的狐火（三个火尖往后上方甩、内芯白热），
// 身后五团小一些的狐火扇形排开（九尾的意象，中间最远最大），各自闪动、往上飘；不画鬃毛长火舌。精二专属，火梢淡紫。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, looped } from "./_lib.js";
import { foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran great foxfire unleashed",
  desc: "A great foxfire: a big plump flame ball with three points streaming back and a white-hot heart, five smaller foxfire balls fanned out behind it like fox tails, each flickering.",
  tags: ["fire", "projectile", "foxfire", "loop"],
  size: [84, 60],
  origin: [60, 32],
  duration: 0.5,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", seed: 9 },
};

const D = meta.duration;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, R = 8;
  const C = { H, t, fps: meta.fps };
  if (core) {
    for (const [ang, d, rk, i] of [[1.05, 1.7, 0.44, 0], [-1.0, 1.65, 0.42, 1], [0.55, 2.3, 0.52, 2], [-0.5, 2.25, 0.5, 3], [0.03, 2.9, 0.58, 4]]) {
      const bx = -Math.cos(ang), by = Math.sin(ang) * 0.9;
      foxClump(p, bx * R * d, by * R * d - R * 0.3, R * rk, { ...C, seed: S + 20 + i, tips: 2, heat: 0.75, up: 0.95, acc: true });
    }
    foxClump(p, 0, 0, R, { ...C, seed: S, tips: 3, up: 0.8, lean: -0.6, acc: true });
  }
  if (deco) {
    p.glow(2, 0, 11, F[6], 0.26);
    looped(t, D, 4, S + 300, (r) => ({ x: -r.range(14, 36), y: r.range(-4, 5), vx: -r.range(20, 40), vy: -r.range(8, 20), life: r.range(0.3, 0.5), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, q.x + q.vx * age, q.y + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 28);
    });
  }
}
