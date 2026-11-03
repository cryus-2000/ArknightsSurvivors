// 铃兰狐火命中（pixelfx 放开版，docs/242）：1x，原点 = 命中点，狐火从左边来。
// 原作 lisa_attack_01_hit：白闪 → 火团 → 星点散开。本作：首帧噪声边白热爆点（顺来向拉长，不是正圆）→ 火舌从命中点往上、往前舔起，
// 逐级冷却 → 火星往前上方迸、慢慢飘散。精英档（docs/242 §10，docs/91）：
//   E0 三条短火舌；E1 加一缕「狐尾」火（顺来向甩出、末端上卷的长火舌，对应精一狐火灼印「打中留下印记」）；E2 两缕狐尾 + 首帧白热十字闪、余韵更长。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameTongue, flameBlade, ember, spark, LAYERS, BACK_LAYERS } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定，样板 843736ef8）

export const meta = {
  name: "Suzuran foxfire hit unleashed",
  desc: "A foxfire hit: a ragged white-hot pop stretched along the shot, flame tongues licking up and forward, a fox-tail lick lashing on at higher elite, embers drifting off.",
  tags: ["fire", "impact", "hit", "foxfire", "one-shot"],
  size: [84, 72],
  origin: [30, 46],
  duration: 0.6,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, quick: 0, seed: 5 },
};

const NL = noiseFor(0);

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const LQ = +o.quick > 0 ? 0.5 : 1;   // 队友版（_tm）：装饰余韵减半
  const el = +o.elite, S = +o.seed, F = fit(o.palette, 9), H = hotFirst(F);
  const Rg = new (class { constructor(s) { this.s = s; } next() { this.s = (this.s * 1103515245 + 12345) % 2147483648; return this.s / 2147483648; } range(a, b) { return a + (b - a) * this.next(); } })(S * 7919 + 13);
  const D = [0.4, 0.5, 0.6][el] * (LQ < 1 ? 0.75 : 1);
  // 火舌：[x 偏移, 高, 半宽, 往前偏, 起始延迟]，间距随机、高矮不一
  const tongues = [];
  for (let x = -5 + Rg.range(0, 2), i = 0; i < 3; i++, x += Rg.range(4.5, 7))
    tongues.push([x, Rg.range(11, 18) * (i === 1 ? 1.25 : 1) * (el === 2 ? 1.1 : 1), Rg.range(1.8, 2.6), Rg.range(3, 7), Rg.range(0, 0.05)]);
  // 狐尾：顺来向（往右）甩出、末端往上卷（bend 为负 = 往上）
  const tails = el === 0 ? [] : el === 1 ? [[0, 0.85, -0.52, 30, -10]] : [[0, 0.85, -0.52, 34, -12], [1, 0.97, -0.24, 26, -8]];
  const embers = [];
  const ne = [5, 7, 10][el];
  for (let i = 0; i < ne; i++) {
    const a = -Rg.range(0.1, 1.4), sp = Rg.range(30, 110);
    embers.push({ vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: Rg.range(0.25, 0.5) * D / 0.6 * LQ + 0.1, s: Rg.next() < 0.25 ? 2 : 1, ph: Rg.range(0, TAU), sk: Rg.next() < 0.35 });
  }
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
      const u = clamp(t / D), pop = 1 - clamp(t / 0.085);
      if (core) {
        // 爆点：首帧满白热，噪声边、往前（来向的反方向）拉长
        if (pop > 0) {
          const R = (7 + el * 1.2) * (0.6 + 0.4 * pop);
          p.shade(-R * 1.4, -R * 1.2, R * 2.4, R * 1.2, (x, y) => {
            const d = Math.hypot(x * (x > 0 ? 0.5 : 1.1), y * 1.15), a = Math.atan2(y, x) / TAU, sp = pnoise(a * 11, 11, S + 3), rim = R * (0.32 + 0.95 * Math.max(0, sp) ** 1.4) + 0.5 * pnoise(a * 23, 23, S + 4);
            if (d > rim) return;
            const h = 1 - d / rim;
            return pop > 0.5 ? (h > 0.5 ? H[0] : h > 0.25 ? H[1] : H[3]) : h > 0.5 ? H[1] : H[3];
          });
          if (el === 2 && pop > 0.4) for (const [dx, dy, l] of [[1, 0, 18], [-1, 0, 6], [0, -1, 11], [0, 1, 5]]) for (let d = 0; d <= l * pop; d += 0.5) p.px(dx * d, dy * d, d < l * 0.4 ? H[0] : H[2]);
        }
        // 火舌：长起来再塌，后半程换冷一档的层
        for (const [x, h, w, sx, d0] of tongues) {
          const v = clamp((t - d0) / D), grow = ease.outCubic(clamp(v / 0.25)) * (1 - ease.inQuad(clamp((v - 0.35) / 0.65)));
          if (grow > 0.05) flameTongue(p, x, 2, h * grow, w * (0.6 + 0.4 * grow), sx, N, S * 31 + x * 7, H, v < 0.45 ? LAYERS : BACK_LAYERS, 0.55, 1.2);
        }
        // 狐尾（E1 / E2）：顺来向甩出去再往上卷，比火舌晚一点、长一点
        tails.forEach(([y0, ux, uy, len, bend], i) => {
          const v = clamp((t - 0.03 - i * 0.04) / (D * 0.9)), grow = ease.outCubic(clamp(v / 0.3)) * (1 - ease.inQuad(clamp((v - 0.4) / 0.6)));
          if (grow > 0.05) flameBlade(p, 1, y0 - 1, ux, uy, len * grow, 2.0 * (0.5 + 0.5 * grow), bend * grow, N, S * 53 + i, H, v < 0.5 ? LAYERS : BACK_LAYERS, 0.35, 1.2);
        });
      }
      if (deco) {
        p.glow(2, -4, 12 + el * 3, F[6], (0.22 + 0.08 * el) * (1 - u) * (1 - u) + 0.15 * pop);
        for (const q of embers) {
          const age = t - 0.02;
          if (age < 0 || age > q.life) continue;
          const k = 1 - age / q.life, x = q.vx * age, y = q.vy * age - 10 * age * age;
          q.sk && age < q.life * 0.5 ? spark(p, x, y, q.vx, q.vy, k, [H[0], H[2], H[4], H[6]]) : ember(p, x, y, k, q.s, [H[0], H[2], H[4], H[6]], q.ph + age * 26);
        }
      }
    },
  };
}
