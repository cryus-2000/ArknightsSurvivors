// 拉普兰德成长节点「断喝」（docs/202 路线 bark，docs/242 放开版，用户 11-03「所有美术换新版」）：判定圆 r = bark_r，原点 = 拉普兰德脚底。
// 旧画面是程序画的一道紫色正圆环（pfx ring）—— §12.3 禁止项、紫也不在她的冷灰白色阶里。本作写成「一声断喝震出去」：
// 很多根长短不一的短声纹划痕从身边往外冲（径向、地面透视 sy 0.55），不在同一半径上齐步走，前锋最远到判定圆；
// 外圈几处烙封印纹（bark_seal 封印）。没有完整的环、没有同心圈。
// 节点不分精英档：只出一档（px_ul_tex 退到不带档位后缀）。
// 分层：core = 声纹划痕、封印纹；deco = 划痕根部淡尘。
import { Rng, fit, clamp, ease, TAU } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Lappland bark shout",
  desc: "Many short uneven radial scratch-lines burst outward from her in ground perspective, staggered so they never form a ring, the front reaching the hit radius; a few seal marks burn near the edge.",
  tags: ["shout", "radial", "topdown", "one-shot"],
  size: [180, 120],
  origin: [90, 62],
  duration: 0.55,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    r: 75,            // 判定半径 bark_r ÷ PX（1x），由 targets judge 覆盖
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 61,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", R = +o.r;
  const lines = jitterAngles(Rg, quick ? 14 : 22, 0, TAU, 0.6).map((a) => ({ a, d0: Rg.range(0.1, 0.3), reach: Rg.range(0.6, 1.0), L: Rg.range(0.08, 0.2), dl: Rg.range(0, 0.08) }));
  const seals = jitterAngles(Rg, 3, 0, TAU, 0.8).map((a) => ({ a, r: Rg.range(0.8, 0.95) }));
  let t = 0;
  const P = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * SY];
  return {
    update(dt) { t += dt; },
    draw(p) {
      for (const l of lines) {
        const u = clamp((t - l.dl) / 0.28);
        if (u <= 0 || u >= 1) continue;
        const f = l.d0 + (l.reach - l.d0) * ease.outQuad(u), b = Math.max(l.d0, f - l.L * (1 - u * 0.5));
        const [x0, y0] = P(l.a, b * R), [x1, y1] = P(l.a, f * R);
        if (core) p.line(Math.round(x0), Math.round(y0), Math.round(x1), Math.round(y1), C[u < 0.3 ? 6 : u < 0.65 ? 5 : 3]);
        if (deco && u < 0.5) p.blend(Math.round(x0), Math.round(y0), C[2], 0.5 * (1 - u * 2));
      }
      if (core && t > 0.22 && t < 0.5) for (const s of seals) {
        const [x, y] = P(s.a, s.r * R), c = C[t < 0.28 ? 6 : t < 0.38 ? 5 : 3];
        p.line(x - 3, y - 2, x + 3, y + 2, c); p.line(x - 2, y + 2, x + 2, y - 2, c);
      }
    },
  };
}
