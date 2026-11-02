// 塞雷娅钙晶（D 组）：@2x 密度，原点 = 底边中点。8 帧 @10，帧号即阶段（游戏按槽位状态挑帧）：0–3 长出、4 立着、5–7 碎裂。替换 Codex fx_saria_calcite。
// 一簇冷白偏琥珀的钙晶（主晶 + 两根矮的，高矮倾角随机），长出时晶尖先亮、立着时一道高光扫过，碎裂时晶体缩回、碎片往外蹦。
import { Rng, fit, clamp, crystal } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria calcite",
  desc: "An amber-edged calcite cluster in eight phase frames: four growing with a bright tip, one standing with a glint sweep, three breaking as it sinks and shards pop out.",
  tags: ["earth", "crystal", "phases"],
  size: [72, 80],
  origin: [36, 78],
  duration: 0.8,
  loop: false,
  fps: 10,
  bg: "ground",
  options: { palette: ["#06142a", "#3a2a1c", OP.saria[1], OP.saria[2], OP.saria[3], "#ffe6c0", "#f4f8ff", "#ffffff"], seed: 2 },
};

export function draw(p, t, o) {
  const f = Math.floor(t * 10 + 1e-6);
  if (f >= 8) return;
  const C = fit(o.palette, 8), R = new Rng(o.seed);
  const xs = [{ x: 0, h: 58, w: 18, lean: R.range(-4, 4) }, { x: R.range(-16, -10), h: R.range(26, 36), w: 11, lean: R.range(-8, -2) }, { x: R.range(9, 15), h: R.range(20, 30), w: 10, lean: R.range(2, 7) }];
  const grow = f <= 3 ? [0.3, 0.6, 0.88, 1.05][f] : f === 4 ? 1 : [0.75, 0.45, 0.2][f - 5];
  const ramp = f === 0 ? C.slice(1, 8) : C.slice(0, 7);
  for (const s of [xs[1], xs[2], xs[0]]) {
    const h = s.h * grow;
    crystal(p, s.x, 0, h, s.w * (f >= 5 ? 0.8 : 1), s.lean, ramp, { white: f === 0, glint: f === 4 ? 0.55 : f === 3 ? 0.8 : -1 });
  }
  if (f >= 5) {   // 碎片往外蹦：位置随帧外移，大小不一
    const k = f - 4;
    for (let i = 0; i < 7; i++) {
      const a = R.range(-Math.PI, 0), d = R.range(8, 16) * k, s = R.range(1.5, 3.5) / (1 + k * 0.3);
      p.rect(Math.cos(a) * d, -14 + Math.sin(a) * d * 0.8 + k * k * 2, s, s, C[R.int(3, 6)]);
    }
  }
  for (let i = 0; i < 5; i++) p.px(R.range(-14, 14), R.range(-1, 1), C[R.int(2, 4)]);   // 脚下碎晶
}
