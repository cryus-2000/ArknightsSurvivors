// 流明 S2「沛霖」开启（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队员脚底（每个在场队员各播一张）。
// 照原作 lumen_skill_02_hit（头顶一道水柱落下 → 落地溅开 → 水点、气泡和十字星散开）：
// 一道边缘起伏的窄水柱从上方落到脚底，落地那一下溅起一圈不规则的水冠（短刺往上翘，不是圆环），水柱随后从上往下断开、收掉；
// 落点甩出几组水珠，一两颗十字星浮起。不画外扩光环（用户 11-04）。S2 精一才解锁，只出 E1 / E2：
// E2 水柱里多一道白芯细光（灯塔），水冠更高。分层：core = 水柱、水冠、十字星、白芯；deco = 水柱外的淡光、水珠、雾点。只用钢蓝 7 阶。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, jitterAngles } from "../house.js";
import { LAMP } from "../house.js";

export const meta = {
  name: "Lumen downpour unleashed",
  desc: "A narrow column of water drops onto the target, bursts into an uneven crown and breaks up from the top.",
  tags: ["water", "buff", "one-shot"],
  size: [96, 176],
  origin: [48, 156],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", elite: 2, quick: 0, seed: 5 },
};

const SY = 0.5;

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), E = Math.max(1, o.elite), Rg = new Rng(o.seed + 7 * E);
  const tail = (E === 1 ? 0.8 : 1) * (o.quick ? 0.6 : 1);
  // 分档（组长 B 11-04 硬标准）：S2 精一解锁，E1 = 一道水柱；E2 质变——一道变三道（主柱 ×1.5 宽 + 左右两道细柱稍晚落下），
  // 落点一点灯火橙（E2 专属点缀），余韵更长。加码只加在水柱本身
  const H = 150, W = E === 2 ? 6 : 4, T_LAND = 0.12, AC = fit([LAMP], 1)[0];
  const cols = E === 2 ? [[0, 1, 0], [-10, 0.5, 0.05], [9, 0.45, 0.09]] : [[0, 1, 0]];
  const crown = jitterAngles(Rg, E === 2 ? 8 : 6, -2.0, 2.0, 0.4)   // 水冠偏向身前（用户 11-04）
    .map((a, i) => ({ a, h: (9 + 13 * noise(i * 1.9, o.seed)) * (E === 2 ? 1.3 : 1), r: 9 + 6 * noise(i * 2.7, o.seed + 1) }));
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  // 成组甩出的水珠去掉（用户 11-04，§14.7）
  const glints = [{ x: Rg.range(-10, 10), d: 0.3 }].concat(E === 2 ? [{ x: Rg.range(-12, 12), d: 0.45 }] : []);
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); ps.list.forEach((q) => (q.vy += 220 * dt)); },
    drawBack(p) {
      if (!deco) return;
      if (t < 0.4) p.glowLine(0, -H, 0, 0, W + 4, C[3], 0.2 * (1 - smooth(0.15, 0.4, t)));
    },
    draw(p) {
      // 水柱：0.12 s 从上落到脚底；之后从上往下断开（顶端往下收），边缘按高度用 noise 起伏
      for (const [cx, ck, cd] of cols) {
        const tc = t - cd, fall = ease.inQuad(clamp(tc / T_LAND)), cut = smooth(0.18, 0.55 * (0.7 + 0.3 * tail), tc);
        const yBot = -H + H * fall, yTop = -H + H * cut;
        if (core && tc > 0 && yBot > yTop)
          for (let y = yTop; y <= yBot; y += 1) {
            const v = (y + H) / H, w = W * ck * (0.6 + 0.4 * v) * (0.8 + 0.4 * noise(y * 0.15 + t * 12 + cx, o.seed));
            for (let x = -w; x <= w; x += 0.5) {
              const q = Math.abs(x) / w;
              p.dot(cx + x, y, q > 0.75 ? C[4] : tc < T_LAND + 0.05 && q < 0.4 ? C[6] : C[5], q > 0.85 ? 0.7 : 1);
            }
          }
      }
      if (core && E === 2 && t > T_LAND && t < T_LAND + 0.2) for (let y = -1; y <= 1; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(x, y - 1, AC);   // E2 专属：落点一点灯火橙
      // 水冠：落地时短刺往上翘、再往外垂成水珠
      const u = (t - T_LAND) / (0.35 * (0.7 + 0.3 * tail));
      if (core && u > 0 && u < 1)
        for (const c of crown) {
          const bx = Math.cos(c.a) * c.r * (0.6 + 0.4 * u), by = Math.sin(c.a) * c.r * SY, hh = c.h * Math.sin(Math.min(1, u * 1.6) * Math.PI * 0.5) * (1 - u * u);
          for (let s = 0; s <= hh; s += 0.5) for (const ox of [0, 0.7]) p.dot(bx + Math.cos(c.a) * s * 0.35 + ox, by - s, u < 0.12 ? C[6] : s > hh * 0.6 ? C[6] : C[5], 1 - u * 0.5);
        }
      if (core)
        for (const g of glints) {
          const a = t - g.d, life = 0.35;
          if (a <= 0 || a > life) continue;
          const k = Math.sin((a / life) * Math.PI), y = -14 - a * 30, m = Math.round(3.5 * k);
          p.px(g.x, y, C[6]);
          for (let d = 1; d <= m; d++) { const c = d <= 1 ? C[6] : C[5]; p.px(g.x + d, y, c); p.px(g.x - d, y, c); p.px(g.x, y + d, c); p.px(g.x, y - d, c); }
        }
      if (deco) ps.draw(p, "front");
    },
  };
}
