// 塞雷娅精一「钙化拳」挂在敌人身上的琥珀斑（D 组）：@2x 密度，4 帧 @8 循环，原点 = 帧中心。替换 fx_saria_amber_spot。
// 三四粒大小不一的琥珀钙晶小点贴在身上，轮流反光；不画圈。
import { Rng, fit } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria amber spot",
  desc: "A status mark: three or four uneven amber calcite flecks stuck on an enemy, glinting in turn.",
  tags: ["status", "crystal", "loop"],
  size: [24, 24],
  origin: [12, 12],
  duration: 0.5,
  loop: true,
  fps: 8,
  bg: "dark",
  options: { palette: ["#06142a", ...OP.saria], seed: 3 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 8), R = new Rng(o.seed), f = Math.floor(t * 8 + 1e-6) % 4;
  for (let i = 0; i < 4; i++) {
    const x = R.range(-7, 7), y = R.range(-7, 7), s = R.int(2, 4), lit = i === f;
    p.poly([[x, y - s], [x + s * 0.8, y], [x, y + s * 0.7], [x - s * 0.8, y]], C[lit ? 6 : 4]);
    p.px(x, y - s + 1, C[lit ? 7 : 5]);
    p.px(x + s * 0.8 - 1, y + 1, C[2]);
  }
}
