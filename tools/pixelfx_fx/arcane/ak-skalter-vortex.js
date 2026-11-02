// 浊心斯卡蒂 S3 地面漩涡（docs/229 §2.2，替 fx_skalter_vortex_floor 的海嗣青 + 洋红点缀，40 KB）：1x，8 帧循环 @10，原点 = 帧中心；
// JSON fit 146 不变：外缘在 1x 半径 146 处（原条 @2x，库画布上限 480，改按 1x 画，屏上密度相同），地面透视 sy 0.55。用户 11-02 定：保留设定红、靠明暗区分——暗血红色阶 + 近黑 + 白高光。
// 一群长短不一、半径各异的弧形流痕绕中心慢旋：每条按自己的相位淡入、沿圆周滑一段、淡出（cycle 无缝），头部亮、尾部暗；
// 半径随机分布（不排成等距同心圈），零星白高光点只在少数流痕的头上。
import { fit, clamp, Rng } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skadi the Corrupting Heart floor vortex",
  desc: "Slow blood-red ground vortex: uneven arcs at scattered radii fade in, slide and fade out on their own phases; bright heads, dark tails, rare white glints.",
  tags: ["floor", "vortex", "aura", "loop"],
  size: [304, 168],
  origin: [152, 84],
  duration: 0.8,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.skalter, seed: 11, radius: 146 },
};

const SY = 0.55;
export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration, Rg = new Rng(o.seed), R = o.radius;
  for (let i = 0; i < 46; i++) {
    const r = R * Math.sqrt(Rg.range(0.04, 1)), a0 = Rg.range(0, Math.PI * 2), len = Rg.range(0.25, 0.9) * (0.6 + 0.4 * r / R);
    const off = Rg.range(0, 1), slide = Rg.range(0.12, 0.3), bright = Rg.chance(0.18), w = r > R * 0.6 ? 1.5 : 1;
    const u = (ph + off) % 1, life = Math.sin(Math.PI * u);              // 淡入淡出（相位 0 / 1 处为 0，循环无缝）
    if (life < 0.08) continue;
    const head = a0 + slide * u * Math.PI * 2 * 0.25;
    const step = 0.8 / r;
    for (let s = 0; s < len; s += step) {
      const v = s / len, a = head - s;                                    // v 0 头 → 1 尾
      const x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
      const ci = clamp(Math.round(4.6 - v * 3.4 - (1 - life) * 1.5 - (Math.sin(a) < 0 ? 0.6 : 0)), 1, 5);
      for (let d = 0; d < w; d++) p.blend(x, y + d, C[ci], life * (1 - v * 0.75) * 0.9);
    }
    if (bright && life > 0.5) { const x = Math.cos(head) * r, y = Math.sin(head) * r * SY; p.px(x, y, C[6]); p.blend(x + 1, y, C[5], life); }
  }
}
