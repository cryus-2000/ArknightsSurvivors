// 铃兰狐火渺然的地面旋流（S3 光域，pixelfx 放开版，docs/242）：1x，原点 = 光域中心（脚底），循环；游戏按光域半径缩放（单位半径 R = 92 美术像素）。
// 原作 lisa_skill_03_range：脚下铺开的青蓝旋流纹 + 范围描边。用户 11-04：长火带读成触手 → 三路狐火团沿旋臂排开（透视压扁 0.55），
// 绕中心慢慢转；每路从里到外一团比一团大、越外越亮，各自闪动；火光铺在地上（floorLight）。不画范围描边、不画实心底、不往外扩。
// 组长 B 11-04：十几团小火远看是撒点 → 每路团数降到 1 / 2 / 2、单团放大约 1.6 倍，同一路的火团之间贴地铺一道暗橙受光带连起来（地面层、无硬边）。
// 分档：E0 每路一团；E1 每路两团 ×1.25；E2 每路两团、团更大（×1.5）+ 火梢淡紫，不靠团更多。
import { fit, TAU } from "../../core/index.js";
import { hotFirst, ember, looped, floorLight } from "./_lib.js";
import { SCALE, foxClump } from "./_suzuran_ul.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire haze swirl unleashed",
  desc: "Three spiral arms of plump foxfire balls laid out across the ground in perspective, turning slowly, each arm growing bigger and brighter toward its outer end, every ball flickering.",
  tags: ["fire", "ground", "field", "foxfire", "loop"],
  size: [200, 120],
  origin: [100, 62],
  duration: 2.4,
  loop: true,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", elite: 2, seed: 8 },
};

const D = meta.duration, R = 92, PY = 0.55;

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, ph = t / D, el = +o.elite, K = SCALE[el], ARMS = 3;
  const NB = [1, 2, 2][el], AL = [0.75, 0.9, 1][el], KB = [0.8, 1, 1.25][el] * 1.6;
  const rot = ph * TAU / ARMS;   // 一个循环转过 1/3 圈，三条臂轮换接上，无缝
  const arm = (i, s) => {   // 臂上 s ∈ [0,1]：从内旋到外
    const a = rot + i * TAU / ARMS + s * 0.75 * AL * Math.PI, r = R * (0.32 + 0.6 * AL * s);
    return [Math.cos(a) * r, Math.sin(a) * r * PY];
  };
  const pts = [];
  for (let i = 0; i < ARMS; i++) {
    for (let j = 0; j < NB; j++) {
      const s = NB === 1 ? 0.92 : [0.42, 0.95][j], [x, y] = arm(i, s);
      pts.push({ x, y, r: (3.0 + 2.2 * s) * KB, heat: 0.65 + 0.35 * s, seed: S + i * 17 + j * 3, tip: true });
    }
  }
  pts.sort((a, b) => a.y - b.y);   // 远的（上方）先画
  if (core) for (const q of pts) foxClump(p, q.x, q.y - q.r * 0.6, q.r, { H, t, fps: meta.fps, seed: q.seed, tips: q.r > 4 ? 3 : 2, heat: q.heat, sq: 0.8, up: 1.1, acc: el === 2 && q.tip });
  if (deco) {
    // 每路一道贴地暗橙受光带：沿旋臂密铺软光，把同一路的火团连起来（无硬边）
    for (let i = 0; i < ARMS; i++) for (let s = 0.05; s <= 1.0001; s += 0.06) { const [x, y] = arm(i, s); floorLight(p, x, y, (9 + 9 * s) * AL, (4 + 4 * s) * AL, F[3], 0.13 + 0.17 * s); }   // 暗橙（F[3]），F[6] 在地面上发灰
    looped(t, D, el + 2, S + 40, (r) => ({ a: r.range(0, TAU), rr: R * r.range(0.4, 0.95), vy: -r.range(8, 18), vx: r.range(-5, 5), life: r.range(0.5, 1.0), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, Math.cos(q.a) * q.rr + q.vx * age, Math.sin(q.a) * q.rr * PY - 2 + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 20);
    });
  }
}
