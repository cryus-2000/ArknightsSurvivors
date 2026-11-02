// 德克萨斯剑雨的源石剑（docs/229 §7，替 fx_texas_blade）：@2x，画布与帧语义同原条（verb.fx_rain 按帧号用，不改代码）：
// 16×40，锚点 = 剑尖 (8, 36)（fx_rain 缺省锚点 = 帧底往上 2 个 1x 像素）；游戏 scale 0.93 / 0.8 → 每 1x 像素 1.9 / 1.6 世界像素（原条 0.47 倍缩小画）；第 0–1 帧下落循环（剑身 + 上方不等长的下落拖光），第 2–5 帧插在地上按停留时间铺开（插地白闪 → 冷却 → 剑身碎光散尽）。
// 剑色按 PRTS 立绘「橙剑」#FFE053（色阶 opts.palette，见 targets_a.json），暗部压到深琥珀，不用纯黑。
import { fit, clamp, noise } from "../../core/index.js";

export const meta = {
  name: "Texas rain sword",
  desc: "Originium sword for Texas's sword rain: two falling frames with uneven light trails, then planted with a white flash, cooling and breaking into motes.",
  tags: ["melee", "sword", "rain", "sheet"],
  size: [16, 40],
  origin: [8, 36],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2a1606", "#5c3208", "#a8620e", "#f0a020", "#ffe053", "#ffe58a", "#ffffff"],
    seed: 2,
  },
};

const L = 31;   // 剑长（剑尖到柄头，@2x 像素）
function sword(p, C, life, heat, brk, sd) {
  for (let d = 0; d <= L; d++) {
    const y = -d, guard = d >= 21 && d <= 22, grip = d > 22, w = guard ? 5 : grip ? 0.6 : d < 4 ? d * 0.45 : 1.8;
    for (let x = -w; x <= w + 0.01; x++) {
      if (brk > 0 && 0.5 + 0.5 * noise(d * 0.4 + x * 0.6, sd) < brk) continue;
      let ci = grip ? (d === 25 || d === 28 ? 1 : 2) : guard ? (x < 0 ? 4 : 3) : x < -0.5 ? 5 : x < 1 ? 4 : 3;         // 剑身左亮右暗，中脊一道
      if (!grip && !guard && Math.abs(x) < 0.5 && d > 3) ci = 6;
      ci = clamp(Math.round(ci + heat - (1 - life) * 3), 1, 6);
      if (life >= 0.95) p.px(x, y, C[ci]);
      else p.blend(x, y, C[ci], life);
    }
  }
}

export function draw(p, t, o) {
  if (t >= meta.duration - 1e-6) return;
  const C = fit(o.palette, 7), f = Math.floor(t * meta.fps + 1e-6), sd = o.seed;
  C[6] = C[5];   // 近白 ≤ 12%（docs/229 §2.4）：本体不用纯白，亮处交给光晕层
  if (f <= 1) {   // 下落：剑身 + 上方拖光（几根不等长、不等距的竖线）
    const off = f === 0 ? 0 : 1;
    sword(p, C, 1, 0, 0, sd);
    for (const [x, len, a] of [[-2, 2 + off, 0.5], [0, 4 - off, 0.75], [1, 1 + off, 0.45]]) {
      for (let k = 0; k < len; k++) p.blend(x, -L - 1 - k, C[clamp(Math.round(5 - (k / len) * 4), 1, 5)], a * (1 - k / len));
    }
    p.glow(0, -11, 8, C[4], 0.15);
    return;
  }
  const u = (f - 2) / 3;   // 0 插地 → 1 散尽
  sword(p, C, 1 - u * 0.75, 0, u * 0.7, sd);
  if (f === 2) {   // 插地白闪：剑尖处不对称的一道横光
    for (let x = -6; x <= 7; x++) p.blend(x, -1, C[x < -3 || x > 4 ? 5 : 6], 0.9);
    p.glow(0, -2, 8, C[5], 0.3);
  }
  for (let i = 0; i < 5 + f; i++) {   // 碎光：沿剑身往上飘，位置不等距
    const d = 3 + ((i * 5.3 + f * 2.1) % 24), x = noise(i * 1.9 + f, sd + 4) * 4;
    p.blend(x, -d - u * 6, C[5 + (i % 2)], 0.8 * (1 - u * 0.6));
  }
}
