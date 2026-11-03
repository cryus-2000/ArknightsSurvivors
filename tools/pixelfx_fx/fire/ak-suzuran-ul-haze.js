// 铃兰狐火渺然的地面旋流（S3 光域，pixelfx 放开版，docs/242）：1x，原点 = 光域中心（脚底），循环；游戏按光域半径缩放（单位半径 R = 92 美术像素）。
// 原作 lisa_skill_03_range：脚下铺开的青蓝旋流纹 + 范围描边。本作：三条贴地的暖橙火带从内往外旋开（透视压扁 0.55），绕中心慢慢转；
// 每条外端最亮、往里逐级冷成余烬色，沿途冒一两条矮火舌、飘两三颗余烬。不画范围描边、不画实心底、不往外扩。
// 11-04 §0「不碎」：火带加厚成有体量的实心带（外端半宽约 4），火光铺在地上（floorLight），不画圆光团。
// 精英档（组长 B 11-04 分档硬标准）：E0 三条火带短一截、细一档、不冒火舌；E1 火带长 / 粗 ×1.25、每条一条火舌；
// E2 质变：火带再粗一档，外段分叉成两股（一条 → 狐尾分岔），叉梢 E2 专属淡紫灵光，每条两条火舌。
import { fit, clamp, hex, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, ember, looped, floorLight, LAYERS, BACK_LAYERS } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定，样板 843736ef8）

export const meta = {
  name: "Suzuran foxfire haze swirl unleashed",
  desc: "Three low streaks of foxfire spiralling out from the centre across the ground in perspective, turning slowly, brightest at their outer ends and cooling inward, with a few short tongues and embers.",
  tags: ["fire", "ground", "field", "foxfire", "loop"],
  size: [200, 116],
  origin: [100, 58],
  duration: 2.4,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 8 },
};

const D = meta.duration, NL = noiseFor(D), R = 92, PY = 0.55, ACC = ["#f1e6ff", "#cdb4ff", "#9a78e0"].map(hex);   // E2 专属淡紫灵光

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const el = +o.elite, ARMS = 3, AL = [0.72, 0.9, 1][el], AW = [0.7, 0.9, 1.1][el], NT = el, NE = [2, 3, 4][el];
  const rot = ph * TAU / ARMS;   // 一个循环转过 1/3 圈，三条臂轮换接上，无缝
  // 臂上 s ∈ [0,1]：从内（r0）旋到外（r1），角度沿逆时针走 SPAN
  const arm = (i, s) => {
    const a = rot + i * TAU / ARMS + s * 0.75 * AL * Math.PI, r = R * (0.3 + 0.62 * AL * s);
    return [Math.cos(a) * r, Math.sin(a) * r * PY];
  };
  if (core) {
    for (let i = 0; i < ARMS; i++) {
      for (let s = 0; s <= 1; s += 0.0035) {
        const [x, y] = arm(i, s), k = s;   // k 越大越外、越亮
        const half = (1.1 + 3.0 * k) * AW * Math.min(1, (1 - s) * 8) + 0.6 * N(6, S, s * 10);
        if (half < 0.4) continue;
        const c = k > 0.85 ? H[2] : k > 0.6 ? H[3] : k > 0.35 ? H[5] : H[7];
        for (let q = -half; q <= half; q += 0.5) p.px(x, y + q * 0.6, Math.abs(q) > half * 0.6 ? (k > 0.5 ? H[5] : H[7]) : c);
        if (el === 2 && s > 0.55) {   // 外段分叉：第二股往外偏、细一档、略短
          const f = (s - 0.55) / 0.45, a = rot + i * TAU / ARMS + (0.55 + (s - 0.55) * 0.7) * 0.75 * Math.PI, r = R * (0.3 + 0.62 * s) * (1 + 0.13 * f);
          if (s < 0.93) {
            const bx = Math.cos(a) * r, by = Math.sin(a) * r * PY, bh = half * 0.6;
            for (let q = -bh; q <= bh; q += 0.5) p.px(bx, by + q * 0.6, Math.abs(q) > bh * 0.6 ? H[5] : k > 0.8 ? H[2] : H[3]);
          } else if (s < 0.95) {
            const bx = Math.cos(a) * r, by = Math.sin(a) * r * PY;
            p.px(bx, by, ACC[0]), p.px(bx + 1, by, ACC[1]), p.px(bx - 1, by, ACC[1]), p.px(bx, by + 1, ACC[2]);
          }
        }
      }
      if (el === 2) { const [x, y] = arm(i, 0.985); p.px(x, y, ACC[0]), p.px(x + 1, y, ACC[1]), p.px(x - 1, y, ACC[1]), p.px(x, y - 1, ACC[2]); }   // 主股梢灵光
      // 矮火舌：每条臂外段两条，此起彼伏
      for (let j = 2 - NT; j < 2; j++) {
        const s = 0.62 + 0.28 * j, life = ((ph * 2 + j * 0.5) % 1), g = Math.sin(Math.PI * life);
        const [x, y] = arm(i, s);
        if (g > 0.15) flameTongue(p, x, y, (5 + 3 * j) * g, 1.8 * (0.5 + 0.5 * g), 1.2, N, S * 13 + j, H, life < 0.5 ? LAYERS : BACK_LAYERS, 0.35, 0.8);
      }
    }
  }
  if (deco) {
    for (let i = 0; i < ARMS; i++) for (const s of [0.55, 0.85]) { const [x, y] = arm(i, s); floorLight(p, x, y, 22 * AL, 9 * AL, F[6], 0.14 + 0.1 * s); }
    // 火星：固定在地上的几处（不跟着转，循环接缝不跳）
    looped(t, D, NE, S + 40, (r) => ({ a: r.range(0, TAU), rr: R * r.range(0.4, 0.95), vy: -r.range(8, 18), vx: r.range(-5, 5), life: r.range(0.5, 1.0), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, Math.cos(q.a) * q.rr + q.vx * age, Math.sin(q.a) * q.rr * PY - 2 + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 20);
    });
  }
}
