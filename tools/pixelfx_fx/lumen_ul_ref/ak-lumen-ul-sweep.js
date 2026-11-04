// 流明成长「灯塔守望」旋转光束（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 出光处，正右为光束方向，无缝循环。
// 判定：长 beam_len（1x = beam_len / 2），绕队长 beam_period 秒一圈，扫到的敌人受伤并被照亮。原作无（本作成长），借原作 S3 的直线光。
// 一道从出光处往外张开的实心光扇（§0）：白芯 + 钢蓝实体，扇内几颗往外漂的光尘；
// 末端不收成圆，用 noise 打散淡出。只用钢蓝 7 阶（旧版暖黄光扇作废）。分层：core = 白芯线、两条边；deco = 扇内淡光、光尘。
import { Rng, fit, clamp, noise } from "../../core/index.js";
import { OP, LAMP } from "../house.js";   // 色阶唯一来源（§11.1 第 12 条）

export const meta = {
  name: "Lumen lighthouse sweep unleashed",
  desc: "A long thin fan of light from the lamp: a white core line, two steel-blue edges and faint drifting motes inside.",
  tags: ["beam", "light", "loop"],
  size: [264, 44],
  origin: [4, 22],
  duration: 0.6,
  loop: true,
  fps: 15,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", len: 130, seed: 5, elite: 2 },
};

export function draw(p, t, o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), L = o.len, ph = (t % meta.duration) / meta.duration, Rg = new Rng(o.seed);
  // 分档（组长 B 11-04 硬标准；成长「灯塔守望」精二前就能拿到）：E0 窄光扇；E1 扇宽 ×1.25、白芯加粗；
  // E2 质变——整道光幕（扇宽 ×1.5、白芯铺满中段），出光处一点灯火橙（E2 专属点缀）
  const E = o.elite ?? 2, EW = [1, 1.25, 1.5][E], AC = fit([LAMP], 1)[0];
  const half = (x) => (1 + 12 * (x / L)) * EW;   // 扇半宽：出光处 1 → 末端 13（× 档位）
  const fade = (x) => clamp((L - x) / (L * 0.25)) * (0.85 + 0.15 * noise(x * 0.2 + ph * 6, o.seed));
  if (deco) {
    for (let x = 2; x <= L; x += 1)
      for (let y = -half(x); y <= half(x); y += 1) p.blend(x, y, C[3], 0.1 * fade(x) * (1 - Math.abs(y) / (half(x) + 1)));
    for (let i = 0; i < 6; i++) {
      const u = (ph + Rg.next()) % 1, x = 10 + u * (L - 14), y = Rg.range(-0.8, 0.8) * half(x);
      p.dot(x, y, C[5], Math.sin(u * Math.PI) * 0.8);
    }
  }
  if (!core) return;
  // §0（用户 11-04）：实心的光扇（不是三根细线）——中段 3 像素白芯，往外一圈钢蓝实体，扇边用 noise 起伏淡出
  for (let x = 0; x <= L; x += 0.5) {
    const f = fade(x), run = Math.max(0, 1 - Math.abs(((x / L - ph + 1) % 1) - 0.5) * 6), w = half(x) * [0.55, 0.6, 0.8][E], cq = [0.25, 0.35, 0.5][E];
    for (let y = -w; y <= w; y += 0.5) {
      const q = Math.abs(y) / Math.max(w, 0.5);
      p.blend(x, y, q < cq ? (x < L * 0.5 || run > 0.3 ? C[6] : C[5]) : q < 0.6 ? C[5] : C[4], f * (q < 0.6 ? 1 : 1.4 - q));
    }
  }
  if (E === 2) for (let y = -1; y <= 1; y++) for (let x = 0; x <= 3; x++) if (Math.abs(y) + Math.abs(x - 1.5) <= 2) p.px(x, y, AC);   // E2 专属：出光处一点灯火橙
}
