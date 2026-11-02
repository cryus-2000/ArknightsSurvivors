// 流明治疗队长时脚下的灯光（docs/229 技能档，地面 + 上飘）：@2x，原点 = 脚底，透视 sy 0.55。
// 脚下先泛开一小片不规整的暖亮（首帧中心一点白），随后几片光屑高低快慢不一地往上飘、慢慢变暗消失。只一圈，不画同心圈。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Lumen heal",
  desc: "Lumen's heal under the leader: a ragged pool of lantern light spreads at the feet and flecks of light drift up unevenly and fade.",
  tags: ["holy", "heal", "light", "floor", "one-shot"],
  size: [72, 72],
  origin: [36, 52],
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, seed: 5 },
};

const SY = 0.55, R = 24;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), S = o.seed;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  for (let i = 0; i < 9; i++) {
    const a = Rg.range(0, TAU), d = Rg.range(0.1, 0.9) * R;
    ps.spawn(P.FLAKE, Math.cos(a) * d, Math.sin(a) * d * SY, Rg.range(-6, 6), -Rg.range(35, 80), Rg.range(0.2, 0.35), Rg.pick([C[4], C[4], C[5]]), Rg.range(1, 1.8), Rg.range(0, 0.1));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {
      const k = 1 - smooth(0.15, 0.4, t), rr = R * (0.5 + 0.5 * ease.outQuart(clamp(t / 0.12)));
      if (k <= 0) return;
      p.shade(-rr * 1.3, -rr * SY * 1.3, rr * 1.3, rr * SY * 1.3, (x, y) => {
        const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (rr * (1 + 0.15 * noise(a * 3.3, S) + 0.06 * noise(a * 8.7, S + 1)));
        if (d > 1) return;
        const ci = clamp(Math.round((t < 0.04 ? 4.5 : 3.6) - d * 2 - (1 - k) * 2), 0, 5);
        p.blend(x, y, C[ci], (0.6 - 0.35 * d) * k);
      });
    },
    draw(p) {
      if (t < 0.04) p.px(0, 0, C[6]);
      ps.draw(p);
    },
  };
}
