// 星熊天赋「战术装甲」格挡闪放开版（remap fx_hoshiguma_block → fx_hoshiguma_ul_block）：贴在立绘盾面上，原点 = 盾心，约 0.3 s @20。
// 旧条是一团金光；这里是盾挡下一击的那一下：倒三角盾沿（PRTS 黑钢盾）从受击点往两边亮过去（白热 → 钢灰），盾面中间一道短横的白热擦痕，
// 盾沿两角各蹭出一点暗红（般若）。不外扩、不甩火星（用户 11-04），不画圆光（§12.3）；大小对齐旧条（逻辑约 32 格，游戏里 scale 照旧）。
import { fit, clamp, noise, ease } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma unleashed block flash",
  desc: "Shield block flash: the inverted-triangle shield rim lights up from the impact point outward along its edges, a short white-hot scrape crosses the shield face, and dark-red glints catch at the two upper corners.",
  tags: ["holy", "shield", "block", "one-shot"],
  size: [40, 40],
  origin: [20, 18],
  duration: 0.3,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // 钢色 = PRTS 黑钢盾（不用金，§12.6）
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    layer: "all",
    seed: 5,
  },
};

const V = [[-14, -12], [14, -12], [1, 14]];

export function draw(p, t, o) {
  // 11-04 §0：一个实心主形 = 盾面本身（实心倒三角钢板）——挨打那一下整面白热、受击点一道擦痕，然后逐阶冷成钢灰收掉；
  // 不用半透明淡出（会抖成网点），不画外扩、不甩火星；暗红只在盾下沿一道（反击架势），不另撒点。
  const C = fit(o.palette, 7), E = fit(o.ember, 5), core = o.layer !== "deco", deco = o.layer !== "core";
  const u = t / meta.duration;
  if (u > 0.85) return;
  const st = u < 0.15 ? 0 : u < 0.4 ? 1 : u < 0.65 ? 2 : 3;   // 白热 → 亮钢 → 钢 → 暗钢
  const sc = 0.92 + 0.08 * ease.outBack(clamp(u / 0.15));   // 挨打那一下盾面往里一缩再回位
  const P3 = V.map(([x, y]) => [x * sc, y * sc]);
  if (core) {
    p.poly(P3, [C[5], C[3], C[2], C[1]][st], 1);
    const rim = [C[6], C[5], C[4], C[3]][st];
    for (let i = 0; i < 2; i++) p.line(P3[i][0], P3[i][1], P3[(i + 1) % 3][0], P3[(i + 1) % 3][1], i === 0 ? rim : [C[6], C[4], C[3], C[2]][st], 1);
    p.line(P3[2][0], P3[2][1], P3[0][0], P3[0][1], [C[6], C[4], C[3], C[2]][st], 1);
    if (st < 3) {   // 受击点擦痕：盾面一道短横白热切口
      const hw = 4 + 2 * st;
      for (let x = -hw; x <= hw; x += 0.5) p.blend(x + 1, -4 + 0.8 * noise(x * 0.5, o.seed + 3), [C[6], C[6], C[5]][st], 1 - Math.abs(x) / hw * 0.5);
    }
  }
  if (deco && st >= 1 && st <= 2) {   // 盾下两条斜沿上一线暗红余热（贴边、不出形）
    for (const [a, b] of [[1, 2], [2, 0]]) p.line(P3[a][0] * 0.96, P3[a][1] * 0.96 + 0.5, P3[b][0] * 0.96, P3[b][1] * 0.96 + 0.5, E[st === 1 ? 3 : 2], 1);
  }
}
