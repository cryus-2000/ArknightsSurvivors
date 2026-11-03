// 拉普兰德精一「狼之舞」（docs/242 放开版，用户 11-03「所有美术换新版」）：每 dance_n 次横扫换成一次绕身回旋斩，判定圆 r = dance_r，原点 = 拉普兰德脚底。
// 旧画面是程序画的一道正圆环（pfx ring）—— §12.3 禁止项。本作写成：一道新月刀光绕身旋一圈多（地面透视 sy 0.55），
// 半径从里往外螺旋放大到判定圆、刀弧长度和亮度沿途起伏；扫过处甩出几片切线方向的碎光，最后在圈上烙两枚封印纹（精神摧毁，命中封印）。
// 主形「绕身螺旋刀弧」，和普攻月牙（单道扇形）、S3 十字、终结技剑气帘都不同。
// elite：E1 一道刀弧；E2 两道刀弧错开半圈同时旋（双生刃）。精一才有，所以只出 E1 / E2。
// 分层：core = 刀弧前沿、内沿、封印纹；deco = 刀弧后的淡拖影、碎光。
import { Rng, fit, hex, clamp, ease, TAU } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Lappland wolf dance spin",
  desc: "A crescent blade spirals once and a bit around her feet in ground perspective, growing out to the hit radius, flinging tangent sparks, then two seal marks burn on the circle; elite 2 adds a second blade half a turn apart.",
  tags: ["melee", "slash", "spin", "topdown", "one-shot"],
  size: [150, 100],
  origin: [75, 52],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    r: 60,            // 判定半径 dance_r ÷ PX（1x），由 targets judge 覆盖
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 51,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 1, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", BLUE = hex("#d6ebf6");
  const R = +o.r, TS = 0.32, A0 = Rg.range(0, TAU), SPAN = TAU * 1.15;
  const blades = el >= 2 ? [0, Math.PI] : [0];
  const sparks = jitterSteps(Rg, SPAN, 0.5, 1.0).map((a) => ({ a, t0: (a / SPAN) * TS, sp: Rg.range(30, 60), life: Rg.range(0.15, 0.3) }));
  const seals = [Rg.range(0, TAU), Rg.range(0, TAU)].map((a) => ({ a }));
  let t = 0;
  const P = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * SY];
  const rad = (u) => R * (0.55 + 0.45 * ease.outQuad(clamp(u)));
  return {
    update(dt) { t += dt; },
    draw(p) {
      const u = clamp(t / TS);
      for (const off of blades) {
        const head = A0 + off + SPAN * ease.outQuad(u), L = (0.9 + 0.3 * Math.sin(u * 5)) * (t < TS ? 1 : Math.max(0, 1 - (t - TS) / 0.12));
        if (L <= 0.02) continue;
        for (let a = head - L; a <= head; a += 0.025) {
          const k = (a - (head - L)) / L, r = rad(u - (1 - k) * 0.15);
          const [x, y] = P(a, r), [xi, yi] = P(a, r - 2 - 3 * k);
          if (core && k > 0.25) {
            p.dot(Math.round(x), Math.round(y), k > 0.85 ? (el >= 2 && k > 0.95 ? BLUE : C[6]) : C[k > 0.55 ? 5 : 4]);   // 前沿 1 格
            if (k > 0.5) p.dot(Math.round(xi), Math.round(yi), C[3]);                                                // 内沿
          }
          if (deco) p.blend(Math.round((x + xi) / 2), Math.round((y + yi) / 2), C[2], 0.35 * k);
        }
      }
      if (deco && !quick) for (const s of sparks) {
        const v = t - s.t0;
        if (v < 0 || v > s.life) continue;
        const a = A0 + s.a, r = rad(s.t0 / TS), [x, y] = P(a, r), d = s.sp * v;
        const tx = -Math.sin(a), ty = Math.cos(a) * SY;   // 切线方向甩出
        p.blend(Math.round(x + tx * d), Math.round(y + ty * d), C[5], 1 - v / s.life);
      }
      if (core && t > TS - 0.04 && t < TS + 0.22) for (const s of seals) {   // 圈上两枚封印纹（一长一短歪十字）
        const [x, y] = P(s.a, R), c = C[t < TS + 0.06 ? 6 : t < TS + 0.14 ? 5 : 3];
        p.line(x - 3, y - 2, x + 3, y + 2, c); p.line(x - 2, y + 2, x + 2, y - 2, c);
      }
    },
  };
}
