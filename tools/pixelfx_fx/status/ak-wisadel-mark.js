// 维什戴尔残影标记 / 好礼标记（D 组）：@2x 密度，挂在敌人头顶的循环，原点 = 帧中心。
// mode 0（替换 fx_wisadel_mark，2 帧 @4）：一枚倒悬的暗红尖晶，高光在两帧间换边。
// mode 1（替换 fx_wisadel_gift_mark，6 帧 @10）：同一枚尖晶，外面几粒余烬碎屑不等距地绕着飘（不成圈），表示「好礼」。
import { Rng, fit, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Wisadel mark",
  desc: "A status mark over an enemy: an inverted dark-red spinel whose glint switches sides; gift mode adds a few ember flecks drifting round it at uneven spacing.",
  tags: ["status", "mark", "crystal", "loop"],
  size: [32, 32],
  origin: [16, 16],
  duration: 0.5,
  loop: true,
  fps: 4,
  bg: "dark",
  options: { palette: ["#0c0606", "#240a08", "#3e1814", "#7c2a24", OP.wisadel[2], "#ff5a3a", "#ffb08a"], gift: 0, seed: 2 },
};

export function draw(p, t, o) {
  const C = fit(o.palette, 7), gift = +o.gift > 0, n = gift ? 6 : 2, f = Math.floor(t * (gift ? 10 : 4) + 1e-6) % n;
  // 倒悬尖晶：上宽下尖，左右两面明暗不同
  const L = f % 2 === 0;
  p.tri(0, -7, -5, -2, 0, 8, C[L ? 4 : 3]);
  p.tri(0, -7, 5, -2, 0, 8, C[L ? 3 : 4]);
  p.line(0, -7, 0, 8, C[5]);
  p.line(-5, -2, 0, -7, C[2]); p.line(5, -2, 0, -7, C[2]);
  p.px(L ? -2 : 2, -3, C[6]);
  if (gift) {
    const R = new Rng(o.seed);
    for (let i = 0; i < 4; i++) {
      const a0 = R.range(0, TAU), r = R.range(9, 13), sp = R.range(0.8, 1.3) * (i % 2 ? 1 : -1);
      const a = a0 + sp * f * (TAU / 6);
      const x = Math.cos(a) * r, y = Math.sin(a) * r * 0.7;
      p.px(x, y, C[5]); p.px(x - Math.sign(sp), y, C[3]);
    }
  }
  p.glow(0, 0, 8, C[4], 0.15);
}
