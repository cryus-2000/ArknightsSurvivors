// 拉普兰德 S1「日晷」（docs/242 放开版）：发动时脚下的画面，原点 = 拉普兰德脚底，地面按透视椭圆（sy 0.55）。
// 原作 S1（whitew_skill_01_buff，original_moves.md）：身周一圈断续细环（ray_15）+ 上飘的三角光点（star_10）。
// 本作照此并扣「日晷」：先从脚下立起一道细长的剑形晷针（起手信号），脚下一圈断续细环由上往下描出来（只一道，不画同心圈），
// 三角光点从环上随机位置往上飘。和普攻的月牙、S2 的狼首都不是一个主形。
// elite（同普攻 / S2 的标记）：E0 晷针 + 断续环 + 三角光点；E1 + 环的缺口处各烙一枚封印纹（精神摧毁）；
//   E2 + 两道剑影在地面上交叉成 X、像晷针的影子一样转过去（双生刃），晷针芯带原作的淡蓝。
// 分层：core = 晷针、环、封印纹、剑影；deco = 光晕、三角光点、余韵微尘。
import { Rng, fit, hex, clamp, ease, noise, TAU } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Lappland sundial",
  desc: "A thin sword-gnomon rises at her feet while one broken ground ring draws itself and small triangles drift up; seals on the ring at elite 1, twin crossing blade-shadows at elite 2.",
  tags: ["buff", "ring", "topdown", "one-shot"],
  size: [130, 110],
  origin: [65, 72],
  duration: 1.05,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],   // 同 S2（原作 langtou_02 冷灰白）
    ring: 24,         // 环半径（1x）：自身增益没有判定范围，取她站位一圈（约 48 世界像素）
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 4,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", BLUE = hex("#d6ebf6");
  const RR = +o.ring, DL = [0.3, 0.45, 0.65][el] * (quick ? 0.5 : 1), GK = [0.25, 0.35, 0.5][el];
  const T0 = 0.08, TR = 0.2;   // 晷针立起 / 环描完
  // 环的缺口：噪声决定哪里断（不规则），E1 的封印纹放在几个缺口中心
  const gapAt = (a) => noise(a * 3.1, o.seed) > 0.05;   // 缺口占一小半：读成几段断开的弧，不是一个完整的圈
  const gaps = [];
  for (let a = 0, inGap = false, s0 = 0; a < TAU + 0.05; a += 0.02) {
    const g = gapAt(a);
    if (g && !inGap) { inGap = true; s0 = a; } else if (!g && inGap) { inGap = false; gaps.push((s0 + a) / 2); }
  }
  const tris = jitterSteps(Rg, TAU, 0.35, 0.9).map((a) => ({ a, vy: Rg.range(18, 34), dx: Rg.range(-4, 4), t0: T0 + Rg.range(0, 0.25), life: Rg.range(0.35, 0.6) * (0.6 + DL), s: Rg.range(1.2, 2.2) }));
  const dust = jitterSteps(Rg, TAU, 0.25, 0.6).map((a) => ({ a, r: RR * Rg.range(0.5, 1.05), ph: Rg.range(0, 6), t0: T0 + TR + Rg.range(0, 0.2) }));
  let t = 0;
  const E = (a, r = RR) => [Math.cos(a) * r, Math.sin(a) * r * SY];
  const seal = (p, x, y, s, c, r) => {
    const cs = Math.cos(r), sn = Math.sin(r), Lp = (a, b) => [x + a * cs - b * sn * SY, y + a * sn * SY + b * cs * SY];
    p.line(...Lp(-s, -s * 0.8), ...Lp(s * 1.1, s * 0.9), c);
    p.line(...Lp(-s * 0.7, s), ...Lp(s * 0.6, -s * 0.7), c);
  };
  return {
    update(dt) { t += dt; },
    draw(p) {
      const hot = t < T0 + 0.05;
      // ---- 晷针：从脚下立起一道细长剑形（剑尖朝上），首帧白热、之后降阶，余韵里缩回去
      const gh = 34 * ease.outExpo(clamp(t / T0)) * (1 - clamp((t - 0.55) / 0.3));
      if (core && gh > 1) {
        for (let y = 0; y > -gh; y--) {
          const k = -y / gh, w = k < 0.85 ? 1 : 0;   // 剑尖一格宽，剑身两格
          const c = hot ? C[6] : k > 0.7 ? (el >= 2 ? BLUE : C[4]) : C[3];
          p.dot(0, y, c);
          if (w) p.dot(1, y, k > 0.4 ? C[3] : C[2]);
        }
        p.line(-3, -4, 4, -4, C[hot ? 6 : 4]);   // 护手
      }
      if (deco && gh > 1) p.glow(0, -gh * 0.6, 8 + 2 * el, C[3], GK * (hot ? 1.5 : 1));
      // ---- 环：从正上方顺时针描出来，只一道、断续；描完后外缘一格亮、逐渐变暗
      const draw = clamp((t - T0 * 0.6) / TR), fade = clamp((t - T0 - TR - 0.15) / (0.3 + DL));
      if (core && draw > 0 && fade < 1) {
        const c = draw < 1 && t < T0 + TR * 0.5 ? C[6] : fade < 0.5 ? C[4] : C[2];   // 白只在描环的头半段
        for (let a = -Math.PI / 2; a < -Math.PI / 2 + TAU * draw; a += 0.6 / RR) {
          if (gapAt(((a % TAU) + TAU) % TAU)) continue;
          const [x, y] = E(a); p.dot(x, y, c);
        }
      }
      // ---- E1+ 封印纹：环描过缺口时，在缺口中心烙一枚
      if (core && el >= 1) for (const g of gaps) {
        const reach = ((g + Math.PI / 2) % TAU + TAU) % TAU / TAU;   // 环描到这里的进度
        const u = t - (T0 * 0.6 + TR * reach);
        if (u < 0 || u > 0.2 + DL * 0.6) continue;
        const [x, y] = E(g);
        seal(p, x, y, 4.2, C[u < 0.06 ? 6 : u < 0.2 ? 4 : 3], g);
      }
      // ---- E2 双生刃：两道剑影在地面上交叉成 X，像晷针的影子一样一起转过去
      if (core && el >= 2 && t > T0 && t < T0 + 0.5) {
        const u = (t - T0) / 0.5, rot = -0.6 + 1.2 * ease.inOutQuad(u), L = RR * 1.4;
        for (const sg of [-1, 1]) {
          const a = rot + sg * 0.42;
          const [x0, y0] = E(a + Math.PI, L * 0.35), [x1, y1] = E(a, L);
          p.line(x0, y0, x1, y1, u < 0.12 ? C[6] : u < 0.6 ? BLUE : C[3]);
          p.line(x0, y0 + 1, x1, y1 + 1, C[u < 0.6 ? 3 : 2]);   // 剑影两格宽
        }
      }
      // ---- 装饰：三角光点从环上往上飘（不等距、大小不一）
      if (deco) for (const tr of tris) {
        const u = t - tr.t0;
        if (u < 0 || u > tr.life) continue;
        const [x, y] = E(tr.a), k = 1 - u / tr.life, yy = y - tr.vy * u, xx = x + tr.dx * u;
        const s = tr.s;
        if (k > 0.2) p.poly([[xx, yy - s], [xx + s * 0.8, yy + s * 0.6], [xx - s * 0.8, yy + s * 0.6]], C[k > 0.6 ? 5 : 3]);
      }
      // ---- 装饰：环内淡光（地面，压扁）+ 余韵微尘闪烁
      if (deco && draw > 0 && fade < 1) for (let a = 0; a < TAU; a += 0.7) {
        const [x, y] = E(a, RR * 0.6);
        p.glow(x, y, 7, C[2], 0.18 * (1 - fade) * draw);
      }
      if (deco) for (const d of dust) {
        const u = t - d.t0;
        if (u < 0 || u > DL) continue;
        const k = (1 - u / DL) * (0.5 + 0.5 * Math.sin(d.ph + u * 30));
        const [x, y] = E(d.a, d.r);
        if (k > 0.2) p.blend(x, y - u * 10, C[k > 0.6 ? 5 : 4], Math.min(1, k));
      }
    },
  };
}
