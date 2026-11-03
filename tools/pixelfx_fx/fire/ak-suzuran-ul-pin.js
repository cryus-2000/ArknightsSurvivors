// 铃兰定身标识（画地为牢 / 画地为牢·禁足，注册表 status.stun，docs/242 §14.18，附件在敌人脚下）：1x，原点 = 敌人脚底，循环。
// 旧版是金色双椭圆环 + 四根转辐。本作不画环：脚下三簇不等角的贴地小狐火（像三根钉住影子的火桩），各自错相位明暗闪烁；
// 按 e.r = 12 画（离脚底 10.5 美术像素、透视 0.5），游戏按 e.r ÷ 12 缩放。组长 B 11-04 过审的「定身三簇」。
import { fit, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, ember, floorLight, LAYERS, BACK_LAYERS } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire pin unleashed",
  desc: "A root marker under a held enemy: three small ground foxfires at uneven angles around the feet, like stakes pinning its shadow, each flickering on its own beat.",
  tags: ["fire", "status", "stun", "foxfire", "loop"],
  size: [36, 28],
  origin: [18, 18],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", seed: 7 },
};

const D = meta.duration, NL = noiseFor(D), R = 10.5, PY = 0.5, ANG = [0.3, 2.4, 4.3];

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  // 身后的先画（y < 0），再画身前的，前后分明
  const order = ANG.map((a, i) => [Math.sin(a), a, i]).sort((x, y) => x[0] - y[0]);
  for (const [, a, i] of order) {
    const x = Math.cos(a) * R, y = Math.sin(a) * R * PY;
    const br = 0.5 + 0.5 * Math.cos(TAU * (t / D + i * 0.33)), hk = 0.7 + 0.3 * br;
    if (core) {
      flameTongue(p, x + 1.5, y, 4 * hk, 1.3, 1.5, N, S * 3 + i * 5 + 1, H, BACK_LAYERS, 0.3, 0.7);
      flameTongue(p, x, y, (8 + 2 * N(5, S + i)) * hk, 2.0, N(2, S + 3 + i) * 2, N, S * 3 + i * 5, H, br > 0.45 ? LAYERS : BACK_LAYERS, 0.35, 0.9);
    }
    if (deco) {
      floorLight(p, x, y, 7, 3, F[6], 0.12 + 0.2 * br);
      const u = (t / D * 2 + i * 0.41) % 1;
      ember(p, x, y - 7 - 8 * u, 1 - u, 1, [H[0], H[2], H[4], H[6]], i * 2.1 + t * 20);
    }
  }
}
