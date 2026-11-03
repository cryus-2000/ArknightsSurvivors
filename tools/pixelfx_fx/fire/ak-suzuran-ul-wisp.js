// 铃兰的小狐火（pixelfx 放开版，docs/242）：1x，原点 = 火苗根部，循环。
// 用在两处：身边绕转的待发狐火（原 fx_suzuran_wisp），和暖光 / 狐火渺然光域边上一圈贴地的小狐火（代替原来的椭圆边线）。
// 一条主火舌 + 一条矮的副火舌，根部一点白热，偶尔掉一颗火星；不画底圆。ground=1 时根部压扁贴地、副火舌更矮。
import { fit, TAU } from "../../core/index.js";
import { noiseFor, hotFirst, flameTongue, ember, looped, LAYERS, BACK_LAYERS } from "./_lib.js";

export const meta = {
  name: "Suzuran small foxfire unleashed",
  desc: "A small standing foxfire: one main tongue and a shorter side tongue, a white-hot root, an ember dropping now and then.",
  tags: ["fire", "wisp", "foxfire", "loop"],
  size: [28, 36],
  origin: [14, 30],
  duration: 1.2,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: ["#3a1a10", "#7a3414", "#c2561a", "#ff8426", "#ffb257", "#ffdca6", "#ffffff"], layer: "all", ground: 0, seed: 7 },
};

const D = meta.duration, NL = noiseFor(D);

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const F = fit(o.palette, 9), H = hotFirst(F), S = +o.seed, gr = +o.ground > 0;
  const N = (rate, seed = 0, off = 0) => NL(t, rate, seed, off);
  // 明暗闪烁：一个循环里亮起一次再暗下去（暗时矮一截、换冷一档的层），一圈里各簇错相位，免得读成匀速散点（组长 B 11-04）
  const br = 0.5 + 0.5 * Math.cos(TAU * t / D), lay = br > 0.45 ? LAYERS : BACK_LAYERS, hk = 0.7 + 0.3 * br;
  if (core) {
    flameTongue(p, 2, 0, ((gr ? 5 : 6) + 1.2 * N(4, S + 1)) * hk, 1.6, 2 + N(3, S + 2), N, S * 3 + 1, H, BACK_LAYERS, 0.3, 0.8);
    flameTongue(p, -0.5, 0, ((gr ? 10 : 13) + 2 * N(5, S)) * hk, gr ? 2.6 : 2.4, N(2, S + 3) * 2.5, N, S * 3, H, lay, 0.4, 1.1);
  }
  if (deco) {
    p.glow(0, -4, 7, F[6], 0.08 + 0.16 * br);
    looped(t, D, 3, S + 50, (r) => ({ x: r.range(-2, 2), vy: -r.range(14, 26), vx: r.range(-5, 5), life: r.range(0.25, 0.45), ph: r.range(0, TAU) }), (q, age) => {
      ember(p, q.x + q.vx * age, -10 + q.vy * age, 1 - age / q.life, 1, [H[0], H[2], H[4], H[6]], q.ph + age * 26);
    });
  }
}
