// 拉普兰德 S2「狼魂」开技期间双剑光焰（docs/242 放开版，用户 11-03 定第 3 条「只加轻量版，双剑带光焰，不加环绕狼首」）：
// 原点 = 脚底，循环播放，画在本体前面。原作 whitew_skill_02_buff_01_l / _r：两手剑上各一簇灰白细焰（fire_15）+ 剑形亮片（jian_02）+ 星点。
// 本作只取细焰：左右两柄剑的位置（腰侧偏下、剑身斜向外下）各一簇往上舔的冷白细焰，几根 1 格宽的焰舌长短交替，
// 焰尖偶尔脱出一粒亮屑。不铺光晕团、不画狼首（用户定）。一圈 0.8 秒首尾相接。
// 分层：core = 焰舌；deco = 焰根淡光、脱出的亮屑。
import { Rng, fit, clamp } from "../../core/index.js";

export const meta = {
  name: "Lappland wolf-spirit sword flames",
  desc: "Light looping cool-white flame tongues licking up along both swords at her sides, a stray spark leaving the tips; no glow blobs.",
  tags: ["buff", "flame", "topdown", "loop"],
  size: [56, 50],
  origin: [28, 40],
  duration: 0.8,
  loop: true,
  fps: 12,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 41,
  },
};

const P = 0.8;
// 两柄剑：剑根（手）→ 剑尖，1x 坐标，脚底为原点；拉普兰德双手持剑垂在两侧、剑尖朝外下
const SWORDS = [[[-8, -12], [-15, -3]], [[8, -12], [15, -3]]];

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const tongues = SWORDS.map(([a, b]) => Array.from({ length: 4 }, (_, i) => ({ u: (i + 0.5) / 4 + Rg.range(-0.06, 0.06), ph: Rg.range(0, 1), L: Rg.range(3, 6), a: b, h: a })));
  const sparks = SWORDS.map(() => ({ ph: Rg.range(0, 1), dx: Rg.range(-1.5, 1.5) }));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const tt = (t % P) / P;
      SWORDS.forEach(([h, b], si) => {
        for (const q of tongues[si]) {
          const x0 = h[0] + (b[0] - h[0]) * q.u, y0 = h[1] + (b[1] - h[1]) * q.u;
          const fl = 0.55 + 0.45 * Math.sin((tt + q.ph) * Math.PI * 2 * 2);   // 一周期两次起伏，首尾相接
          const L = q.L * fl;
          if (core) for (let k = 0; k < L; k++) {
            const sway = Math.round(Math.sin((tt + q.ph) * Math.PI * 2 + k * 0.6) * 0.7);
            p.dot(Math.round(x0) + sway, Math.round(y0 - k), C[k > L - 1.5 ? 6 : k > L * 0.4 ? 5 : 4]);
          }
          if (deco) p.blend(Math.round(x0), Math.round(y0), C[3], 0.35);
        }
        if (deco && !quick) {   // 焰尖脱出的亮屑：每周期一粒，往上飘 0.3 周期
          const s = sparks[si], u = ((tt + s.ph) % 1) / 0.35;
          if (u < 1) p.blend(Math.round(h[0] + (b[0] - h[0]) * 0.5 + s.dx * u), Math.round(h[1] - 6 - u * 10), C[5], 0.8 * (1 - u));
        }
      });
    },
  };
}
