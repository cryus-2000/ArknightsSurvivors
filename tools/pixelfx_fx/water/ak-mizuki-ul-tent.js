// 水月触手追击（claude/pixelfx-ul-mizuki-claude，开关 fx/px_unleashed）：俯视，原点 = 被追击敌人脚底，水月在左边（-x；在右时游戏里水平翻转）。
// 原作参照：skill_03_hit 的 mizuki_03（从地里钻出的发光触手，白芯 → 蓝 → 紫）、skill_01 的 mizuki_04。颜色按用户 11-04 改成立绘宝蓝 → 淡紫。
// 一根触手从敌人脚边地里钻出、抬起、抽下来缠住；收尾缩回地里。
//   elite（docs/91 §9）：E0 抽下即收；E1 = 精一「拖拽」：尖端卷钩，整根往水月那边（-x）拽一下；E2 = 精二「深蓝之籽」：身上淡紫荧光斑 + 落点淡紫水冠，白热首帧。
// move：chase（普攻追击，缺省）/ swarm（惊跳反射的身边触手：更粗、甩得更开）。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, hex } from "../../core/index.js";
import { MZ, tentacle } from "./mizuki-lib.js";

export const meta = {
  name: "Mizuki tentacle chase unleashed",
  desc: "A single tentacle bursts from the ground at the target, rears up, lashes down and binds, then sinks back.",
  tags: ["tentacle", "water", "topdown", "one-shot"],
  size: [120, 140],
  origin: [60, 96],
  duration: 0.8,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: MZ.blue, elite: 2, quick: 0, move: "chase", layer: "all", seed: 5 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), quick = +o.quick > 0, el = clamp(Math.round(+o.elite), 0, 2);
  const core = o.layer !== "deco", deco = o.layer !== "core", sw = o.move === "swarm";
  const DL = [0.45, 0.75, 1][el] * (quick ? 0.5 : 1), GK = [0.45, 0.8, 1][el], HOT = [0.6, 1.4, 2.6][el], LAV = hex(MZ.lav);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[5]], haze: C[4] }), lights = new Lights();
  const K = sw ? 1.3 : 1;
  // 根在敌人背后（背离水月一侧）地里，抬高后越过敌人抽下
  const base = [Rg.range(16, 22) * K, Rg.range(3, 6)], up = Rg.range(36, 44) * K, wig = Rg.range(0.6, 1) * (Rg.chance(0.5) ? 1 : -1);
  const hit = [Rg.range(-3, 2), -Rg.range(5, 8)], w0 = Rg.range(3.6, 4.2) * K * [0.9, 1, 1.1][el];
  const TE = 0.07, TS = 0.06, HOLD = (0.1 + 0.08 * el) * (0.6 + 0.4 * DL), OUT = 0.24 * (0.5 + 0.5 * DL);
  let t = 0.02, slammed = false;
  function pose(u) {
    if (u < TE) {   // 钻出：尖往上抬，略往后仰（背离水月）
      const k = ease.outCubic(clamp(u / TE));
      const tip = [base[0] + 4 * k, base[1] - up * k];
      return [base, [base[0], base[1] - up * 0.5 * k], tip, [base[0] + 3 * k, base[1] - up * 0.8 * k]];
    }
    const k = ease.inCubic(clamp((u - TE) / TS));   // 抽下：越过敌人头顶砸到身上
    const top = [base[0] + 4, base[1] - up];
    let tip = [top[0] + (hit[0] - top[0]) * k, top[1] + (hit[1] - top[1]) * k];
    let pull = 0;
    if (el >= 1) pull = 7 * smooth(TE + TS, TE + TS + 0.12, u) * (1 - smooth(TE + TS + HOLD, TE + TS + HOLD + OUT, u));   // 精一拖拽：往水月（-x）拽
    tip = [tip[0] - pull, tip[1]];
    return [base, [base[0] + 2, base[1] - up * (1.05 - 0.4 * k)], tip, [tip[0] + 10 + wig * 4 - pull * 0.5, Math.min(base[1], tip[1]) - up * (0.6 - 0.35 * k) + wig * 3]];
  }
  return {
    update(dt) {
      t += dt;
      if (!slammed && t >= TE + TS) {
        slammed = true;
        for (let k = 0, n = [6, 9, 12][el]; k < n; k++) {   // 落点水花：往上往两侧，不成圈
          const a = -Math.PI / 2 + Rg.range(-1.3, 1.3), v = Rg.range(50, 150);
          ps.spawn(k % 3 ? P.MOTE : P.SPARK, hit[0], hit[1], Math.cos(a) * v, Math.sin(a) * v, Rg.range(0.25, 0.5) * (0.6 + 0.4 * DL), el >= 2 && k % 3 === 0 ? MZ.lav : C[5 + Rg.int(0, 2)], Rg.range(0.6, 1.0));
        }
        if (deco) lights.add(hit[0], hit[1], 22, el >= 2 ? MZ.lav : C[5], 0.7 * GK, 0.22);
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (core) {   // 根部地洞：压扁、外缘噪声
        const k = smooth(0, 0.05, t) * (1 - smooth(TE + TS + HOLD + OUT * 0.6, TE + TS + HOLD + OUT + 0.05, t)), L = 4 + w0;
        if (k > 0) p.shade(base[0] - L * 1.7, base[1] - L, base[0] + L * 1.7, base[1] + L, (x, y, out) => {
          const dx = (x - base[0]) / 1.7, dy = y - base[1], a = Math.atan2(dy, dx), r = Math.hypot(dx, dy);
          if (r > L * (0.55 + 0.35 * noise(a * 3, o.seed + 41) + 0.15 * noise(a * 9, o.seed + 43)) * k) return;
          out.c = hex(MZ.ink); out.a = 0.65;
        });
      }
    },
    draw(p) {
      const end = TE + TS, back = ease.inCubic(smooth(end + HOLD, end + HOLD + OUT, t));
      if (back < 0.8) {
        const [b, c, tip, c2] = pose(t), hot = t > end && t < end + 0.05 ? HOT * 0.5 : t < 0.05 ? HOT * 0.4 : 0;
        tentacle(p, b, c, tip, 0, 1 - back, { c2, w0, seed: o.seed, el, hot, dis: 0, curl: el >= 1 ? smooth(end, end + 0.08, t) * (1 - back) : 0, cs: -1, glowK: GK }, core, deco);
      }
      if (core && el >= 2 && t > end && t < end + 0.18) {   // 精二落点淡紫水冠：往上张开的不规整一簇短线
        const k = 1 - smooth(end + 0.05, end + 0.18, t);
        for (let a = -2.4; a <= -0.7; a += 0.11) {
          const len = (3 + 6 * Math.max(0, noise(a * 3, o.seed + 61))) * k;
          for (let d = 1; d < len; d += 0.7) p.px(hit[0] + Math.cos(a) * d, hit[1] + Math.sin(a) * d, d > len - 1.5 ? LAV : C[5]);
        }
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
