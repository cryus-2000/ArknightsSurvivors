// 德克萨斯钉剑碎裂（docs/229，替 fx_texas_pin_shatter 的棋盘格碎光）：@2x 48×48，5 帧 @18，原点 = 帧中心。
// 插着的剑从中间崩开：首帧白闪，几片大小不一的琥珀碎片往外上方飞、边飞边转边冷却，细碎光点落下，末段散尽。
import { Bits, Particles, P, B, Rng, fit } from "../../core/index.js";

export const meta = {
  name: "Texas pin shatter",
  desc: "The pinned sword bursts: a white flash, amber shards of uneven size tumbling up and out while cooling, fine motes falling.",
  tags: ["impact", "shatter", "one-shot"],
  size: [48, 48],
  origin: [24, 24],
  duration: 0.3,
  loop: false,
  fps: 18,
  bg: "dark",
  options: { palette: ["#2a1606", "#5c3208", "#a8620e", "#f0a020", "#ffe053", "#ffe58a", "#ffffff"], seed: 7 },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed);
  C[6] = C[5];   // 近白 ≤ 12%（docs/229 §2.4）：本体不用纯白，亮处交给光晕层
  const bits = new Bits({ ground: () => 1e9 }), ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  for (let i = 0; i < 7; i++) {
    const a = -Math.PI / 2 + Rg.range(-1.4, 1.4), sp = Rg.range(60, 150);
    bits.add({ kind: B.SHARD, x: Rg.range(-2, 2), y: Rg.range(-10, 4), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, a: Rg.range(0, 6), va: Rg.range(-18, 18), s: Rg.range(2.5, 5), ramp: [C[2], C[3], C[4], C[5]], g: 300, drag: 1.5, life: Rg.range(0.2, 0.3) });
  }
  for (let i = 0; i < 9; i++) {
    const a = Rg.range(0, Math.PI * 2), sp = Rg.range(40, 110);
    ps.spawn(P.SPARK, 0, -4, Math.cos(a) * sp, Math.sin(a) * sp - 30, Rg.range(0.08, 0.2), 0, 1);
  }
  let t = 0;
  return {
    update(dt) { t += dt; bits.update(dt); ps.update(dt); },
    draw(p) {
      if (t < 0.06) { p.disc(0, -4, 4, C[6], 0.9); p.line(-9, -2, 11, -6, C[6]); }
      bits.draw(p);
      ps.draw(p);
    },
  };
}
