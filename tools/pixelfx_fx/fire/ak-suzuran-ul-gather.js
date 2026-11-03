// 铃兰狐火聚拢（S2「儿时的舞乐」/ S3「狐火渺然」出手，pixelfx 放开版，docs/242）：1x，原点 = 聚拢点（杖头前方）。
// 原作 lisa_skill_02_start：三团狐火在身侧聚起 → 收拢 → 合一爆闪。本作：几团小狐火绕着聚拢点打旋收进来（各自拖一条短火尾），
// 收齐的一刻爆成一簇往上窜的火舌（噪声边，不画圆盘、不放外扩光环），再落几颗火星。n = 3（S2）/ 5（S3）。
// k = 火舌放大倍数：S2 用 2.4（火舌约 2 倍身高，组长 B 审 11-04：原 1 倍实战里等于没放），S3 用 1。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameBlade, flameTongue, ember, LAYERS, BACK_LAYERS, BIG_LAYERS } from "./_lib.js";

export const meta = {
  name: "Suzuran foxfire gathering unleashed",
  desc: "A few small foxfires spiral in on one point trailing short flame tails, then burst into a cluster of tongues leaping upward, with embers falling off.",
  tags: ["fire", "cast", "foxfire", "one-shot"],
  size: [128, 104],
  origin: [64, 80],
  duration: 0.8,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: ["#3a1a10", "#7a3414", "#c2561a", "#ff8426", "#ffb257", "#ffdca6", "#ffffff"], layer: "all", n: 3, k: 1, seed: 4 },
};

const NL = noiseFor(0), TM = 0.38;   // TM：收齐、爆开的时刻

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, n = Math.max(1, +o.n | 0), big = n > 3, K = Math.max(1, +o.k || 1), KW = 1 + (K - 1) * 0.55;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const pos = (i, tt) => {   // 第 i 团在 tt 时的位置：半径收拢、角度越转越快（压扁成透视椭圆）
    const J = [0, 0.42, -0.31, 0.55, -0.18][i % 5], JR = [1, 0.82, 1.12, 0.9, 1.05][i % 5];   // 不等角、不等半径（等距放射会被图案检查拦，也显得机械）
    const k = ease.inQuad(clamp(tt / TM)), a0 = (i + J) * TAU / n + 0.6, a = a0 + 2.6 * k;
    const r = (big ? 34 : 28) * JR * (1 - k);
    return [Math.cos(a) * r, Math.sin(a) * r * 0.55 - 6 * (1 - k)];
  };
  if (core && t < TM) {
    for (let i = 0; i < n; i++) {
      const [x, y] = pos(i, t), [px, py] = pos(i, Math.max(0, t - 0.06));
      const dx = px - x, dy = py - y, d = Math.hypot(dx, dy) || 1;
      // 火尾：顺着来路往后拖；火头本身是一条朝上的小火舌
      flameBlade(p, x, y, dx / d, dy / d, Math.min(14, 3 + d * 1.6), 1.8, 0, N, S * 7 + i, H, BACK_LAYERS, 0.3, 0.8);
      flameTongue(p, x, y + 2, 7 + 1.5 * N(6, S + i), 2.4, 0, N, S * 5 + i, H, LAYERS, 0.35, 0.8);
    }
  }
  const v = t - TM;
  if (core && v >= 0) {
    const pop = 1 - clamp(v / 0.09);
    if (pop > 0) {
      const R = (big ? 9 : 7.5) * KW * (0.6 + 0.4 * pop);
      p.shade(-R * 1.3, -R * 1.8, R * 2.6, R * 2.4, (x, y) => {
        const d = Math.hypot(x * 1.05, y * (y < 0 ? 0.6 : 1.3)), a = Math.atan2(y, x) / TAU, rim = R * (0.3 + 0.95 * Math.max(0, pnoise(a * 10, 10, S + 5)) ** 1.4);
        if (d > rim) return;
        const h = 1 - d / rim;
        return pop > 0.5 ? (h > 0.45 ? H[0] : H[2]) : h > 0.4 ? H[1] : H[3];
      });
    }
    // 爆开后的一簇火舌：往上窜，长起来再塌
    const tongues = big ? [[-8, 18, 2.0, -5], [-2, 27, 2.6, 1], [5, 22, 2.3, 5], [11, 12, 1.7, 7]] : [[-5, 15, 1.9, -4], [1, 23, 2.4, 2], [7, 13, 1.7, 5]];
    tongues.forEach(([x, h, w, sx], i) => {
      const u = clamp((v - 0.015 * i) / (meta.duration - TM)), g = ease.outCubic(clamp(u / 0.28)) * (1 - ease.inQuad(clamp((u - 0.3) / 0.7)));
      if (g > 0.05) flameTongue(p, x * KW, 3, h * K * g, w * KW * (0.55 + 0.45 * g), sx * K, N, S * 11 + i, H, u < 0.4 ? BIG_LAYERS : BACK_LAYERS, 0.5, 1.3);
    });
  }
  if (deco) {
    if (t < TM) for (let i = 0; i < n; i++) { const [x, y] = pos(i, t); p.glow(x, y - 3, 7, F[6], 0.22); }
    if (v >= 0) {
      const u = clamp(v / (meta.duration - TM));
      p.glow(0, -6 * K, (big ? 18 : 14) * KW, F[6], 0.34 * (1 - u) * (1 - u));
      const ne = Math.round((big ? 9 : 6) * KW);
      for (let i = 0; i < ne; i++) {
        const r1 = (S * 131 + i * 977) % 1000 / 1000, r2 = (S * 71 + i * 613) % 1000 / 1000;
        const a = -Math.PI / 2 + (r1 - 0.5) * 2.4, sp = (40 + 60 * r2) * KW, life = 0.22 + 0.2 * r2;
        if (v > life) continue;
        ember(p, Math.cos(a) * sp * v, Math.sin(a) * sp * v + 60 * v * v, 1 - v / life, r1 > 0.75 ? 2 : 1, [H[0], H[2], H[4], H[6]], i * 2.3 + v * 30);
      }
    }
  }
}
