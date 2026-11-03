// 铃兰身上的狐火回旋（S2 / S3 期间常驻，pixelfx 放开版，docs/242）：1x，原点 = 脚底中心，循环。
// 原作 lisa_skill_02_buff：两道光带绕身体交叉回旋。本作：两条细火带沿螺旋绕身上升，转到身后变暗一档、在身前最亮，
// 带子两头收尖、边缘噪声抖；偶尔从带上甩出一颗火星往上飘。layer=back 只画身后半圈，layer=front 只画身前半圈（游戏里分别画在立绘下 / 上）。
import { fit, clamp, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, ember, looped } from "./_lib.js";

export const meta = {
  name: "Suzuran foxfire swirl unleashed",
  desc: "Two thin ribbons of foxfire spiralling up around the body, dimmer behind and brightest in front, tapering at both ends, with an ember flicked off now and then.",
  tags: ["fire", "aura", "buff", "foxfire", "loop"],
  size: [56, 56],
  origin: [28, 48],
  duration: 1.0,
  loop: true,
  fps: 20,
  bg: "dark",
  options: { palette: ["#3a1a10", "#7a3414", "#c2561a", "#ff8426", "#ffb257", "#ffdca6", "#ffffff"], layer: "all", side: "both", seed: 6 },
};

const D = meta.duration, NL = noiseFor(D);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const front = o.side !== "back", back = o.side !== "front";
  const RX = 14, RY = 5;
  // 两条：[起始相位, 起点高, 升高, 跨角, 半宽]
  const ribbons = [[0, 0, 24, 0.9 * TAU, 0.9], [0.5, -4, 20, 0.8 * TAU, 0.7]];
  if (core) {
    ribbons.forEach(([p0, y0, rise, span, w], i) => {
      const a0 = (ph + p0) * TAU;
      for (let s = 0; s <= 1; s += 0.004) {
        const a = a0 + s * span, dep = Math.sin(a), isFront = dep > 0;
        if ((isFront && !front) || (!isFront && !back)) continue;
        const x = Math.cos(a) * RX, y = y0 - s * rise + dep * RY;
        const taper = Math.sin(Math.PI * s) ** 0.7, half = w * taper + 0.35 * N(9, S + i, s * 6);
        if (half < 0.35) continue;
        const hot = taper * (isFront ? 1 : 0.6);
        for (let q = -half; q <= half; q += 0.5) {
          const e = Math.abs(q) / Math.max(0.5, half);
          const c = e > 0.7 ? H[isFront ? 5 : 7] : hot > 0.75 ? H[isFront ? 1 : 3] : hot > 0.4 ? H[isFront ? 3 : 5] : H[isFront ? 4 : 6];
          p.px(x, y + q, c);
        }
      }
    });
  }
  if (deco) {
    if (front) p.glow(0, -16, 16, F[5], 0.12);
    looped(t, D, 4, S + 90, (r) => ({ a: r.range(0, TAU), y: -r.range(4, 26), vy: -r.range(10, 24), life: r.range(0.3, 0.6), ph: r.range(0, TAU) }), (q, age) => {
      const dep = Math.sin(q.a);
      if ((dep > 0 && !front) || (dep <= 0 && !back)) return;
      ember(p, Math.cos(q.a) * RX, q.y + dep * RY + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 24);
    });
  }
}
