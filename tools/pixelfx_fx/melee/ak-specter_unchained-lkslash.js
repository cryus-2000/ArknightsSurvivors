// 归溟幽灵鲨连携「替身冲斩」斩痕（link_fx_b.gd SP_SLASH，替换 fx_lk_sp_slash1–3）：@2x 单帧，代码按冲刺全长沿 x 拉伸、淡出（life 0.9）。
// 原点 = 左端（代码锚在 (0, h/2)），斩痕向右。中段最宽、两端收尖；外缘按噪声崩口、两侧零星溅出血珠；芯一道白热细线，往外冷却成暗血红。
// 红色避开敌方危险色 0.92–0.98：色相取 0.99–0.03，高光往橙偏（docs/229 §2.2）。variant 1–3 换宽度曲线与崩口。
import { Rng, fit, clamp, noise } from "../../core/index.js";
import { FPS } from "../house.js";

export const meta = {
  name: "Specter link slash scar",
  desc: "A single long blood-red slash scar: widest in the middle, tapering to points, ragged edges with a few flecks, a white-hot core line cooling outward.",
  tags: ["melee", "slash", "still", "one-shot"],
  size: [392, 48],
  origin: [196, 24],
  duration: 0.05,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#3b0d0b", "#651612", "#861d19", "#a8241f", "#e0553a", "#ffc9b0", "#ffffff"],   // 设定暗血红 #a8241f × 35 / 60 / 80% 明度（docs/229 §2.2，11-02）
    variant: 1,
  },
};

export function draw(p, t, o) {
  if (t >= 0.05) return;
  const C = fit(o.palette, 8), v = o.variant, Rg = new Rng(v * 7 + 1), L = 380, x0 = -190;
  const peak = [0.5, 0.38, 0.62][(v - 1) % 3], W = [7, 11, 9][(v - 1) % 3];
  for (let i = 0; i <= L; i++) {
    const s = i / L, x = x0 + i;
    const taper = s < peak ? Math.pow(s / peak, 0.7) : Math.pow((1 - s) / (1 - peak), 0.9);
    const w = W * taper * (0.8 + 0.4 * (0.5 + 0.5 * noise(s * 9, v * 3)));
    const yc = 2.5 * noise(s * 2.2, v * 5);
    for (let d = -w - 1; d <= w + 1; d += 1) {
      const q = Math.abs(d) / Math.max(w, 0.6);
      if (q > 1 && noise(x * 0.7 + d, v) < 0.6) continue;   // 外缘崩口
      const ci = clamp(Math.round(7 - q * 5.5 - (1 - taper) * 2), 1, 7);
      p.blend(x, Math.round(yc + d), C[ci], q > 0.85 ? 0.7 : 1);
    }
  }
  for (let k = 0, n = Rg.int(6, 10); k < n; k++) {         // 血珠：位置、大小不等
    const s = Rg.range(0.1, 0.9), x = x0 + s * L, y = Rg.sign() * Rg.range(W * 0.9, 18);
    p.px(Math.round(x), Math.round(y), C[Rg.int(3, 5)]);
    if (Rg.chance(0.4)) p.px(Math.round(x) + 1, Math.round(y), C[3]);
  }
}
