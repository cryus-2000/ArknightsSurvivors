// 铃兰狐火聚拢（S2「儿时的舞乐」/ S3「狐火渺然」出手，pixelfx 放开版，docs/242）：1x，原点 = 聚拢点（脚底）。
// 原作 lisa_skill_02_start：三团狐火在身侧聚起 → 收拢 → 合一爆闪。本作：几团小狐火绕着聚拢点打旋收进来（脚下地面渐亮 = 蓄势），
// 收齐的一刻噪声边白热爆点定帧两帧，随即爆成一簇往上跳的圆胖狐火（每团 2–3 个火尖、闪动、往上飘着冷却变小），再抛两三颗碎火落地。
// 用户 11-04：不画长弯火舌 / 火尾（读成触手），一律短胖火团。n = 3（S2）/ 5（S3）；k = 体量倍数（S2 2.4，组长 B 11-04 要约 2 倍身高）。
// 分档：E0 ×0.8 / E1 ×1 / E2 ×1.2，E2 质变：爆开的火团外侧多两团、扇开更宽，火梢淡紫。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { pnoise, hotFirst, ember, sparkAt, floorLight } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire gathering unleashed",
  desc: "A few small foxfires spiral in on one point, then burst into a cluster of plump flickering foxfire balls leaping upward, with embers falling off.",
  tags: ["fire", "cast", "foxfire", "one-shot"],
  size: [128, 112],
  origin: [64, 86],
  duration: 0.8,
  loop: false,
  fps: 24,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, n: 3, k: 1, seed: 4 },
};

const TM = 0.38;   // 收齐、爆开的时刻

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const el = +o.elite, F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, n = Math.max(1, +o.n | 0), big = n > 3;
  const K0 = Math.max(1, +o.k || 1), K = (1 + (K0 - 1) * 0.6) * SCALE[el];
  const C = { H, t, fps: meta.fps };
  const pos = (i, tt) => {   // 第 i 团在 tt 时的位置：半径收拢、角度越转越快（压扁成透视椭圆）
    const J = [0, 0.42, -0.31, 0.55, -0.18][i % 5], JR = [1, 0.82, 1.12, 0.9, 1.05][i % 5];   // 不等角、不等半径
    const k = ease.inQuad(clamp(tt / TM)), a0 = (i + J) * TAU / n + 0.6, a = a0 + 2.6 * k;
    const r = (big ? 34 : 28) * JR * (1 - k);
    return [Math.cos(a) * r, Math.sin(a) * r * 0.55 - 6 * (1 - k)];
  };
  if (core && t < TM) for (let i = 0; i < n; i++) {
    const [x, y] = pos(i, t);
    foxClump(p, x, y - 3, 3.2 + 0.8 * clamp(t / TM), { ...C, seed: S * 5 + i, tips: 2, up: 1.1 });
  }
  const v = t - TM;
  if (core && v >= 0) {
    // 爆开后的一簇火团：往上跳，长起来再缩小冷却；E2 外侧多两团
    const balls = big ? [[-9, 16, 4.2], [-2, 26, 5.4], [6, 21, 4.8], [12, 11, 3.6]] : [[-7, 17, 4.2], [1, 25, 5.0], [9, 11, 3.4]];
    if (el === 2) balls.push([big ? -17 : -14, 13, 3.4], [big ? 21 : 17, 4, 2.6]);   // 两侧不对称（等距放射会被图案检查拦）
    balls.forEach(([x, h, r0], i) => {
      const u = clamp((v - 0.012 * i) / (meta.duration - TM));
      if (u <= 0 || u >= 1) return;
      const g = ease.outCubic(clamp(u / 0.3)), rr = r0 * K * (0.6 + 0.4 * g) * (1 - 0.6 * ease.inQuad(clamp((u - 0.4) / 0.6)));
      foxClump(p, x * K * 0.9, 3 - rr - h * K * 0.55 * g - 4 * u, rr, { ...C, seed: S * 11 + i, tips: 3, heat: 1 - 0.7 * u, up: 1.15, lean: x * 0.02, acc: el === 2 });
    });
    const pop = v < 0.08 ? 1 : 1 - clamp((v - 0.08) / 0.08);   // 定帧：收齐后满白热停两帧
    if (pop > 0) {
      const R = (big ? 9 : 7.5) * K * 0.75 * (0.6 + 0.4 * pop);
      p.shade(-R * 1.3, -R * 1.8, R * 1.3, R * 1.4, (x, y) => {
        const d = Math.hypot(x * 1.05, y * (y < 0 ? 0.6 : 1.3)), a = Math.atan2(y, x) / TAU, rim = R * (0.3 + 0.95 * Math.max(0, pnoise(a * 10, 10, S + 5)) ** 1.4);
        if (d > rim) return;
        const h = 1 - d / rim;
        return pop > 0.5 ? (h > 0.45 ? H[0] : H[2]) : h > 0.4 ? H[1] : H[3];
      });
    }
  }
  if (deco) {
    if (t < TM) floorLight(p, 0, 3, (big ? 30 : 24), 6, F[6], 0.12 + 0.2 * clamp(t / TM));   // 蓄势：脚下地面渐亮
    if (v >= 0) {
      const u = clamp(v / (meta.duration - TM)), pop = v < 0.08 ? 1 : 1 - clamp((v - 0.08) / 0.08);
      floorLight(p, 0, 3, (big ? 34 : 28) * K, 7, F[6], 0.45 * (1 - u) + 0.2 * pop);
      if (pop > 0) p.glow(0, -2, 8 * K, F[7], 0.3 * pop);
      const ne = big ? 3 : 2;
      for (let i = 0; i < ne; i++) {
        const a = -Math.PI / 2 + [-0.7, 0.6, -0.2][i], sp = (70 + 15 * i) * K, age = v - 0.06;
        if (age < 0) continue;
        const [x, y] = sparkAt(0, -8, Math.cos(a) * sp, Math.sin(a) * sp, age, 3, 320, 2.2);
        ember(p, x, y, 1 - u, 1, [H[0], H[2], H[4], H[6]], i * 2.3 + v * 30);
      }
    }
  }
}
