// 铃兰精二「狐火拖尾」的一处路火（pixelfx 放开版，docs/242）：1x，原点 = 路径点（地面），一次性（游戏按这处路火剩余寿命取帧）。
// 旧版每 22 像素放一张同样的小火苗帧条，连起来是一串等距相同的火苗（录像预审报拼接感）。本作每处是一段贴地的余烬带 + 两三条高矮不一的矮火舌，
// 先窜起、再塌成余烬、最后只剩几点暗红；seed 不同的几种轮着用，游戏里再按点序错开相位、左右翻转、缩放 0.85–1.15，连起来像一条烧过的路。
import { fit, clamp, ease, TAU } from "../../core/index.js";
import { noiseFor, pnoise, hotFirst, flameTongue, floorLight, LAYERS, BACK_LAYERS } from "./_lib.js";
import { OP } from "../house.js";   // 暖橙 7 阶（用户 11-04 定）

export const meta = {
  name: "Suzuran foxfire trail patch unleashed",
  desc: "One patch of a burning foxfire trail: a low ember band on the ground with two or three uneven short tongues that flare, collapse into embers and fade to a few dark-red points.",
  tags: ["fire", "ground", "trail", "foxfire", "one-shot"],
  size: [40, 30],
  origin: [20, 22],
  duration: 1.0,
  loop: false,
  fps: 12,
  bg: "dark",
  options: { palette: OP.suzuran, layer: "all", seed: 3 },
};

const NL = noiseFor(0);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, u = clamp(t / meta.duration);
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  const r1 = (k) => (Math.sin(S * 12.9898 + k * 78.233) * 43758.5453) % 1, rr = (k) => Math.abs(r1(k));
  if (core) {
    // 余烬带：贴地、两头收、噪声边；越到后面越暗越窄
    const L = 9 + 3 * rr(1), heat = 1 - u;
    for (let x = -L; x <= L; x += 0.5) {
      const e = 1 - Math.abs(x) / L, half = (0.6 + 1.4 * heat) * Math.sqrt(e) + 0.4 * pnoise(x * 0.5 + S, 17, S);
      if (half < 0.35) continue;
      const c = heat > 0.7 ? (e > 0.5 ? H[2] : H[4]) : heat > 0.35 ? (e > 0.5 ? H[4] : H[6]) : e > 0.6 && pnoise(x * 0.9, 23, S + 2) > 0.2 ? H[6] : H[8];
      for (let q = -half; q <= half; q += 0.5) p.px(x, q * 0.6, c);
    }
    // 矮火舌：两三条，高矮、起落时刻各不同
    const n = 2 + (rr(2) > 0.5 ? 1 : 0);
    for (let i = 0; i < n; i++) {
      const x = -6 + 12 * (i + 0.3 * rr(10 + i)) / n, h = 6 + 7 * rr(20 + i), d0 = 0.06 * i * rr(30 + i);
      const v = clamp((t - d0) / 0.7), g = ease.outCubic(clamp(v / 0.2)) * (1 - ease.inQuad(clamp((v - 0.25) / 0.75)));
      if (g > 0.06) flameTongue(p, x, 0, h * g, 1.6 * (0.5 + 0.5 * g), (rr(40 + i) - 0.5) * 4, N, S * 7 + i, H, v < 0.4 ? LAYERS : BACK_LAYERS, 0.35, 0.9);
    }
  }
  if (deco) floorLight(p, 0, 0, 12, 4, F[5], 0.3 * (1 - u) * (1 - u));
}
