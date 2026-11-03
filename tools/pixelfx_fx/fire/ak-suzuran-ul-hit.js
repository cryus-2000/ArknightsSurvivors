// 铃兰狐火命中（pixelfx 放开版，docs/242）：1x，原点 = 命中点，狐火从左边来。
// 原作 lisa_attack_01_hit：白闪 → 火团 → 星点散开。本作：首帧噪声边白热爆点（顺来向拉长，不是正圆）→ 火舌从命中点往上、往前舔起，
// 逐级冷却 → 两三颗有重量的碎火往前抛、落地弹一下、慢慢熄（11-04 §0：爆点定帧 2 帧再塌；不画十字细线、不画圆光团，光照在地上）。精英档（docs/242 §10，docs/91）：
//   E0 三条短火舌；E1 加一缕「狐尾」火（顺来向甩出、末端上卷的长火舌，对应精一狐火灼印「打中留下印记」）；E2 两缕狐尾 + 首帧白热十字闪、余韵更长。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameTongue, flameBlade, ember, sparkAt, floorLight, LAYERS, BACK_LAYERS } from "./_lib.js";
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
  const ne = LQ < 1 ? 1 : [2, 2, 3][el];
  for (let i = 0; i < ne; i++) {
    const a = -(0.5 + 0.35 * i + Rg.range(0, 0.2)), sp = Rg.range(55, 85);
    embers.push({ vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: D * Rg.range(0.8, 0.95), ph: Rg.range(0, TAU) });
  }
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
      const u = clamp(t / D), pop = t < 0.045 ? 1 : 1 - clamp((t - 0.045) / 0.07);   // 定帧：头两帧满白热不动
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
        // 光照在命中点下方的地面上（命中点离脚底约 6），爆点时最亮
        floorLight(p, 4, 6, 16 + el * 3, 4.5, F[6], (0.3 + 0.08 * el) * (1 - u) + 0.25 * pop);
        if (pop > 0) p.glow(2, -1, 7 + el, F[7], 0.3 * pop);
        for (const q of embers) {
          const age = t - 0.04;
          if (age < 0 || age > q.life) continue;
          const [x, y] = sparkAt(2, -2, q.vx, q.vy, age, 6, 320, 2.2);
          ember(p, x, y, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 26);
        }
      }
    },
  };
}
