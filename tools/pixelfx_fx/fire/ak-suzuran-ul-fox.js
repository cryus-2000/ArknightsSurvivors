// 铃兰狐火弹（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 火头，正右为飞行方向，循环（追踪弹由游戏按速度转向）。
// 用户 11-04（长条读成触手）：火头是一团圆胖的狐火（2–3 个火尖往上跳、内芯亮、外形每 2–3 帧一变），身后几小团往后上方飘散，不拖长带。
// 分档：E0 火头 + 两小团；E1 ×1.25、三小团、内芯更大；E2 质变：火头 ×1.5，身后三团狐火扇形排开（上 / 中 / 下，= 狐尾），火梢淡紫。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, looped } from "./_lib.js";
import { SCALE, foxClump, puffTrail } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire unleashed",
  desc: "A homing foxfire: a plump flickering flame ball with two or three leaping points and a bright heart, small puffs drifting up behind it; at high elite three puffs fan out behind like fox tails.",
  tags: ["fire", "projectile", "foxfire", "loop"],
  size: [56, 40],
  origin: [40, 22],
  duration: 0.4,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, big: 0, seed: 3 },
};

const D = meta.duration;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, el = +o.elite, K = SCALE[el];
  const r = 4.2 * K, C = { H, t, fps: meta.fps, seed: S };
  if (core) {
    if (el === 2) {   // 三尾扇：上 / 中 / 下三团，中间最大最远，各自往上飘
      for (const [ang, d, rk, i] of [[0.75, 2.2, 0.58, 0], [-0.7, 2.1, 0.55, 1], [0.02, 2.8, 0.66, 2]]) {
        const bx = -Math.cos(ang), by = Math.sin(ang) * 0.9;
        foxClump(p, bx * r * d, by * r * d - r * 0.35, r * rk, { ...C, seed: S + 20 + i, tips: 2, heat: 0.8, up: 0.9, acc: true });
      }
    } else puffTrail(p, 0, 0, -1, 0, el === 0 ? 2 : 3, r, { ...C, seed: S + 20 });
    foxClump(p, 0, 0, r, { ...C, tips: 3, up: 0.85, lean: -0.5, acc: el === 2 });   // 火尖往后上方甩（飞行时的迎风）
  }
  if (deco) {
    p.glow(0, 0, 6 + 2 * el, F[6], 0.28);
    looped(t, D, el + 1, S + 200, (r2) => ({ x: -r2.range(4, 14) * K, y: r2.range(-3, 2), vx: -r2.range(10, 25), vy: -r2.range(12, 26), life: r2.range(0.2, 0.36), ph: r2.range(0, TAU) }), (q, age) => {
      ember(p, q.x + q.vx * age, q.y + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 30);
    });
  }
}
