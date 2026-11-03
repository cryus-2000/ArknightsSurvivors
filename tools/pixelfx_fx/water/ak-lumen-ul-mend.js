// 流明「荧光」治疗落点（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 被治疗者脚底。每 3 秒一次，要克制。
// 照原作 lumen_buff_01_hit（一缕水流绕着目标转上去 → 十字星浮起 → 小水点落下）：
// 一条 1 像素的细水流从脚边起，绕身体螺旋往上一圈半（背面暗、正面亮），顶端化成一两颗十字星；不画脚下圆圈。
// 分档：E0 一缕水流；E1 顶端多一道斜着闪过的折光短线；E2 水流顶端接一截竖直的细光（灯塔），十字星 2 颗。
// 分层：core = 水流、十字星、折光、竖光；deco = 水流头的光、落下的小水点。颜色只用钢蓝 7 阶，不用红 / 品红（§11.2 #4）。
import { Particles, P, Rng, fit, clamp, smooth, ease, TAU } from "../../core/index.js";

export const meta = {
  name: "Lumen mend unleashed",
  desc: "A thin ribbon of water spirals up around the target and ends in a small glint.",
  tags: ["water", "heal", "one-shot"],
  size: [56, 96],
  origin: [28, 84],
  duration: 0.75,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", elite: 2, quick: 0, seed: 2 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), E = o.elite, Rg = new Rng(o.seed + 13 * E);
  const tail = (E === 0 ? 0.6 : E === 1 ? 0.8 : 1) * (o.quick ? 0.6 : 1);
  const H = 52, RX = 11, turns = 1.5, a0 = Rg.range(0, TAU), dir = Rg.next() < 0.5 ? 1 : -1;
  const pt = (u) => { const a = a0 + dir * u * turns * TAU; return [Math.cos(a) * RX * (1 - 0.35 * u), -u * H + Math.sin(a) * RX * 0.4, Math.sin(a)]; };
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  for (let i = 0; i < 3 + E; i++) {
    const [x, y] = pt(Rg.range(0.3, 0.9));
    ps.spawn(P.FLAKE, x, y, Rg.range(-6, 6), Rg.range(10, 30), Rg.range(0.25, 0.4) * tail + 0.1, C[5], 1, 0.2 + Rg.range(0, 0.15));
  }
  const top = pt(1);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    draw(p) {
      // 水流：头部 0.25 s 从脚边升到顶，尾部随后跟着收（只留一段 0.45 长的流），首帧头白
      const head = ease.outCubic(clamp(t / 0.25)), tl = clamp((t - 0.12) / (0.3 * (0.7 + 0.3 * tail))), u0 = Math.max(0, head - 0.5) + tl * 0.5;
      if (core && head > u0)
        for (let u = u0; u <= head; u += 0.006) {
          const [x, y, z] = pt(u), v = (u - u0) / Math.max(head - u0, 0.01);
          p.dot(x, y, z < -0.2 ? C[3] : v > 0.85 ? C[6] : C[5], z < -0.2 ? 0.7 : 1);
        }
      if (deco && head > u0 && t < 0.4) { const [x, y] = pt(head); p.glow(x, y, 5, C[4], 0.3 * (1 - t / 0.4)); }
      if (core) {
        const gl = [{ x: top[0], d: 0.24 }].concat(E === 2 ? [{ x: top[0] + 7 * dir, d: 0.34 }] : []);
        for (const g of gl) {
          const a = t - g.d, life = 0.3 * (0.7 + 0.3 * tail);
          if (a <= 0 || a > life) continue;
          const k = Math.sin((a / life) * Math.PI), x = g.x, y = top[1] - 3 - a * 25, m = Math.round(3 * k);
          p.px(x, y, C[6]);
          for (let d = 1; d <= m; d++) { const c = d <= 1 ? C[6] : C[5]; p.px(x + d, y, c); p.px(x - d, y, c); p.px(x, y + d, c); p.px(x, y - d, c); }
        }
        if (E >= 1 && t > 0.22 && t < 0.36) {   // 折光：顶端斜闪一道短线
          const u = (t - 0.22) / 0.14;
          for (let s = -7; s <= 7; s += 0.5) p.dot(top[0] + s, top[1] - 2 + s * 0.6 * dir, Math.abs(s) < 3 && u < 0.5 ? C[6] : C[5], (1 - u) * (1 - Math.abs(s) / 9));
        }
        if (E === 2 && t > 0.2 && t < 0.45) {   // 灯塔：顶端往上一截竖直细光
          const u = (t - 0.2) / 0.25;
          for (let y = 0; y <= 18; y += 1) p.blend(top[0], top[1] - 4 - y, y < 8 && u < 0.4 ? C[6] : C[5], (1 - u) * (1 - y / 22));
        }
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
