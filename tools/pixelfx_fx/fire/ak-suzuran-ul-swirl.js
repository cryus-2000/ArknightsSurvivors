// 铃兰身上的狐火回旋（S2 / S3 期间常驻，pixelfx 放开版，docs/242）：1x，原点 = 脚底中心，循环。
// 原作 lisa_skill_02_buff：两道光带绕身体交叉回旋。用户 11-04：火带长条读成触手 → 改成几团圆胖的小狐火绕身打转、一边转一边往上走，
// 转到身后变暗一档、在身前最亮，各自闪动；不连成带。side=back 只画身后半圈，side=front 只画身前半圈（游戏里分别画在立绘下 / 上）。
// 分档：E0 ×0.8 / E1 ×1 两团；E2 ×1.2 质变：四团、高低错开成两层，火梢淡紫。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, looped } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire swirl unleashed",
  desc: "A few plump foxfire balls circling the body and climbing as they go, dimmer behind and brightest in front, each flickering.",
  tags: ["fire", "aura", "buff", "foxfire", "loop"],
  size: [56, 60],
  origin: [28, 52],
  duration: 1.0,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, side: "both", seed: 6 },
};

const D = meta.duration;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D;
  const front = o.side !== "back", back = o.side !== "front";
  const el = +o.elite, K = SCALE[el], RX = 14 * K, RY = 5 * K;
  // 每团：[相位, 起始高度, 一圈升高, 半径]；一个循环转一圈、升到顶再回到底（接缝处在身后最暗时）
  const balls = el === 2 ? [[0, 4, 18, 3.4], [0.5, 4, 18, 3.2], [0.25, 18, 12, 2.8], [0.75, 18, 12, 2.7]] : [[0, 4, 18, 3.4], [0.5, 4, 18, 3.2]];
  const C = { H, t, fps: meta.fps };
  if (core) {
    const list = balls.map(([p0, y0, rise, r0], i) => {
      const u = (ph + p0) % 1, a = u * TAU, dep = Math.sin(a);
      return { x: Math.cos(a) * RX, y: -(y0 + rise * u) * K + dep * RY, dep, r: r0 * K * (0.85 + 0.15 * dep), i, u };
    }).sort((a, b) => a.dep - b.dep);
    for (const b of list) {
      if ((b.dep > 0 && !front) || (b.dep <= 0 && !back)) continue;
      const fade = Math.min(1, Math.min(b.u, 1 - b.u) * 8);   // 升到顶 / 回到底时缩小，接缝不跳
      foxClump(p, b.x, b.y, b.r * (0.4 + 0.6 * fade), { ...C, seed: S + b.i * 9, tips: b.r > 3 ? 3 : 2, heat: b.dep > 0 ? 1 : 0.6, up: 1.1, acc: el === 2 });
    }
  }
  if (deco) {
    if (front) p.glow(0, -16 * K, 14 * K, F[5], 0.1);
    looped(t, D, 2, S + 90, (r) => ({ a: r.range(0, TAU), y: -r.range(4, 26), vy: -r.range(10, 24), life: r.range(0.3, 0.6), ph: r.range(0, TAU) }), (q, age) => {
      const dep = Math.sin(q.a);
      if ((dep > 0 && !front) || (dep <= 0 && !back)) return;
      ember(p, Math.cos(q.a) * RX, q.y * K + dep * RY + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 24);
    });
  }
}
