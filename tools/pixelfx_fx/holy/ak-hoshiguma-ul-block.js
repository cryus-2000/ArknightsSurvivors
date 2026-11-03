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
  const C = fit(o.palette, 7), E = fit(o.ember, 5), core = o.layer !== "deco", deco = o.layer !== "core";
  const u = t / meta.duration, fade = 1 - clamp((u - 0.45) / 0.55);
  // 盾沿：从上沿中点（受击点）沿周长往两边亮，亮头过后留钢灰余辉
  const L = V.map((v, i) => Math.hypot(V[(i + 1) % 3][0] - v[0], V[(i + 1) % 3][1] - v[1])), tot = L[0] + L[1] + L[2];
  const head = ease.outQuart(clamp(u / 0.5)) * tot * 0.5;   // 两头各走半圈
  if (core) {
    let acc = 0;
    for (let i = 0; i < 3; i++) {
      const [x0, y0] = V[i], [x1, y1] = V[(i + 1) % 3];
      for (let s = 0; s <= L[i]; s += 0.5) {
        const pos = acc + s, d = Math.min(Math.abs(pos - L[0] / 2), tot - Math.abs(pos - L[0] / 2));   // 离受击点（上沿中点）的周长距离
        if (d > head) continue;
        const k = head - d, ci = k < 2 ? 6 : k < 6 ? 5 : 4;
        const x = x0 + (x1 - x0) * s / L[i], y = y0 + (y1 - y0) * s / L[i] + 0.5 * noise(pos * 0.4, o.seed);
        p.blend(x, y, C[clamp(ci - (u > 0.6 ? 1 : 0), 3, 6)], fade);
      }
      acc += L[i];
    }
    if (u < 0.45) {   // 盾面擦痕：一道短横的白热切口，往右拖一点
      const k = 1 - u / 0.45, hw = 5 + 4 * (1 - k);
      for (let x = -hw; x <= hw; x += 0.5) {
        const v = Math.abs(x) / hw;
        p.blend(x + 1, -3 + 0.8 * noise(x * 0.5, o.seed + 3), C[v < 0.5 && u < 0.2 ? 6 : 5], k * (1 - v * 0.6));
      }
    }
  }
  if (deco && u < 0.7) for (const [x, y] of [V[0], V[1]]) {   // 两上角蹭出的暗红：角上 2–3 像素的小块，不画光
    const k = 1 - u / 0.7;
    for (let dy = 0; dy < 2; dy++) for (let dx = -1; dx <= 1; dx++) p.blend(x + dx, y + dy, E[dy ? 2 : 3], 0.8 * k);
  }
}
