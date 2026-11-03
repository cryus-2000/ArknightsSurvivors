// 流明终结技「灯塔」光柱（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底。终结技不分档（§10）。
// 本作设计（docs/199 §4.20：队长脚下升起灯塔光柱 → 光圈 → 光柱亮 2 秒、光束扫过 → 熄灭），原作无；语汇借原作 S3（四芒灯光 star_03、竖直光 trail_15）。
// 0–0.2 s 一道细光从脚下冲上去（rise，与 ult/lu_rise 对齐）；0.2 s 灯塔点亮：顶端一颗横长四芒灯光 + 光柱两侧张开成窄光束，首帧白；
// 这张只到点亮后 0.3 s；之后的 2 秒稳住由循环小帧条 ak-lumen-ul-ult-hold（白芯 + 钢蓝边轻微呼吸、灯光缓慢明暗）接上，熄灭靠游戏里淡出（省显存）。
// warm = 1 时灯芯一点用我方灯火橙（等组长 / 用户定，缺省 0 = 全钢蓝）。分层：core = 光柱、灯光；deco = 光柱外淡光、往上飘的光点。
import { Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Lumen ultimate beacon unleashed",
  desc: "A thin light shoots up from the feet, the lighthouse lamp ignites into a long four-pointed flare and the beam holds for two seconds before folding away.",
  tags: ["light", "beam", "ultimate", "one-shot"],
  size: [150, 330],
  origin: [75, 314],
  duration: 0.5,
  loop: false,
  fps: 15,
  bg: "dark",
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], lamp: ["#a8471a", "#ff9640", "#ffc48a"], warm: 0, seed: 2, layer: "all" },
};

export function create(o, hold = false) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), Lw = fit(o.lamp, 3), Rg = new Rng(o.seed);
  const H = 290, LY = -H, T_ON = 0.2, T_OFF = 2.2;
  const motes = [];
  for (let i = 0; i < 12; i++) motes.push({ x: Rg.range(-10, 10), t0: Rg.range(0.3, 2.0), v: Rg.range(30, 60) });
  let t = 0;
  return {
    update(dt) { t += dt; },
    // hold = 稳住段：时间从点亮后 0.35 s 起算并循环
    get t() { return t; },
    draw(p) {
      if (hold) t = T_ON + 0.35 + ((t - T_ON - 0.35) % 0.4 + 0.4) % 0.4;
      const rise = ease.outCubic(clamp(t / T_ON)), on = t >= T_ON, off = smooth(T_OFF, 2.55, t);
      const W = on ? 9 * (1 - off) * (0.9 + 0.1 * Math.sin(t * TAU / 0.4)) : 1;
      const top = -H * rise, bot = -H * off * 0.9;   // 熄灭时从下往上熄
      if (deco && on && off < 1) p.glowLine(0, top, 0, bot, W + 14, C[3], 0.22 * (1 - off));
      if (core && W > 0.3)
        for (let y = bot; y >= top; y -= 1) {
          const v = -y / H, w = W * (0.6 + 0.4 * v) * (0.9 + 0.2 * noise(y * 0.08 + 1.5 * Math.sin(t * TAU / 0.4), o.seed));
          for (let x = -w; x <= w; x += 0.5) {
            const q = Math.abs(x) / Math.max(w, 0.5);
            const hot = t >= T_ON && t < T_ON + 0.07, c = !on ? (y < top + 12 ? C[6] : C[5]) : hot ? (q < 0.7 ? C[6] : C[5]) : q < 0.3 ? C[6] : q < 0.75 ? C[5] : C[4];   // 冲上去时只有头亮；点亮只白 1 帧
            p.blend(x, y, c, q > 0.8 ? 0.7 : 1);
          }
        }
      // 灯光：顶端四芒（横长），点亮那一下最大，之后慢慢明暗
      if (core && on && off < 1) {
        const k = (t < T_ON + 0.25 ? 1.3 - (t - T_ON) * 1.2 : 1 + 0.08 * Math.sin(t * TAU / 0.4 + 1)) * (1 - off);
        const rays = [[1, 0, 70], [-1, 0, 70], [0, -1, 28], [0, 1, 18], [0.7, 0.7, 11], [-0.7, 0.7, 11], [0.7, -0.7, 13], [-0.7, -0.7, 13]];
        for (const [dx, dy, L] of rays) {
          const len = L * k;
          for (let s = 0; s <= len; s += 0.5) {
            const v = s / Math.max(len, 1);
            p.blend(dx * s, LY + dy * s, t < T_ON + 0.07 ? (v < 0.6 ? C[6] : C[5]) : v < 0.2 ? C[6] : v < 0.7 ? C[5] : C[4], 1 - v * 0.6);
          }
        }
        for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) if (Math.abs(x) + Math.abs(y) <= 2) p.px(x, LY + y, o.warm && Math.abs(x) + Math.abs(y) <= 1 ? Lw[2] : C[6]);
        if (o.warm) p.px(0, LY, Lw[1]);
      }
      if (deco)
        for (const m of motes) {
          const a = t - m.t0;
          if (a > 0 && a < 0.8 && off < 1) p.dot(m.x, -20 - a * m.v * 2, C[5], Math.sin((a / 0.8) * Math.PI) * 0.8 * (1 - off));
        }
    },
  };
}
