// 铃兰狐火命中（pixelfx 放开版，docs/242）：1x，原点 = 命中点，狐火从左边来。
// 爆点噪声边白热（顺来向拉长）、定帧两帧 → 几团圆胖的狐火从命中点往前上方跳起、闪动、冷却变小 → 两三颗有重量的碎火落地弹一下。
// 用户 11-04：不画长弯火舌（读成触手），一律短胖火团；光照在地上、不画圆光团。
// 分档：E0 两团；E1 ×1.25、三团、爆点两连亮；E2 质变：五团扇形展开（= 狐尾），×1.5，火梢淡紫，余韵更长。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { pnoise, hotFirst, ember, sparkAt, floorLight } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire hit unleashed",
  desc: "A foxfire hit: a ragged white-hot pop stretched along the shot, then plump flickering foxfire balls leaping up and forward and cooling, fanning out like fox tails at high elite, a couple of heavy embers bouncing.",
  tags: ["fire", "impact", "hit", "foxfire", "one-shot"],
  size: [84, 72],
  origin: [30, 46],
  duration: 0.6,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, quick: 0, seed: 5 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const LQ = +o.quick > 0 ? 0.5 : 1;   // 队友版（_tm）：余韵减半
  const el = +o.elite, S = +o.seed, F = fit(o.palette, 9), H = hotFirst(F), K = SCALE[el] * 1.25;
  const Rg = new (class { constructor(s) { this.s = s; } next() { this.s = (this.s * 1103515245 + 12345) % 2147483648; return this.s / 2147483648; } range(a, b) { return a + (b - a) * this.next(); } })(S * 7919 + 13);
  const D = [0.4, 0.5, 0.6][el] * (LQ < 1 ? 0.75 : 1);
  // 火团：[往前上方的角度, 跳起距离, 半径, 起跳延迟]；E2 五团扇形
  const angs = el === 0 ? [-1.25, -0.6] : el === 1 ? [-1.4, -0.85, -0.3] : [-1.55, -1.15, -0.78, -0.42, -0.08];
  const balls = angs.map((a, i) => ({ a: a + Rg.range(-0.08, 0.08), d: Rg.range(10, 15) * K * (el === 2 && (i === 1 || i === 3) ? 1.15 : 1), r: Rg.range(3.4, 4.4) * K * (i === Math.floor(angs.length / 2) ? 1.15 : 1), d0: Rg.range(0, 0.04) + 0.012 * i }));
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
      const u = clamp(t / D), pop1 = t < 0.045 ? 1 : 1 - clamp((t - 0.045) / 0.07);   // 定帧：头两帧满白热不动
      const pop2 = el >= 1 && t > 0.12 && t < 0.2 ? 0.75 * (1 - clamp((t - 0.12) / 0.08)) : 0;   // E1 / E2 第二下爆亮
      const pop = Math.max(pop1, pop2);
      if (core) {
        for (const [i, b] of balls.entries()) {   // 火团：往前上方跳起、闪动，后半程冷却缩小、再往上飘一点
          const v = clamp((t - 0.03 - b.d0) / (D * 0.92));
          if (v <= 0 || v >= 1) continue;
          const g = ease.outCubic(clamp(v / 0.35)), x = Math.cos(b.a) * b.d * g, y = Math.sin(b.a) * b.d * g - 5 * v * v * K;
          const rr = b.r * (0.55 + 0.45 * ease.outCubic(clamp(v / 0.2))) * (1 - 0.55 * ease.inQuad(clamp((v - 0.45) / 0.55)));
          foxClump(p, x, y, rr, { H, t, fps: meta.fps, seed: S * 13 + i, tips: rr > 3 ? 3 : 2, heat: 1 - 0.75 * v, up: 1.05, lean: Math.cos(b.a) * 0.3, acc: el === 2 && v < 0.85 });
        }
        if (pop > 0) {   // 爆点：噪声边、往前（来向的反方向）拉长
          const R = 7 * SCALE[el] * 1.25 * (0.6 + 0.4 * pop) * (pop2 > pop1 ? 0.75 : 1);
          p.shade(-R * 1.4, -R * 1.2, R * 2.4, R * 1.2, (x, y) => {
            const d = Math.hypot(x * (x > 0 ? 0.5 : 1.1), y * 1.15), a = Math.atan2(y, x) / TAU, sp = pnoise(a * 11, 11, S + 3), rim = R * (0.32 + 0.95 * Math.max(0, sp) ** 1.4) + 0.5 * pnoise(a * 23, 23, S + 4);
            if (d > rim) return;
            const h = 1 - d / rim;
            return pop > 0.5 ? (h > 0.5 ? H[0] : h > 0.25 ? H[1] : H[3]) : h > 0.5 ? H[1] : H[3];
          });
        }
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
