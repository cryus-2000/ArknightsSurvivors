// 星熊精一举盾的盾面光（docs/229，替 fx_hoshiguma_guard_glow 的红三角 + 棋盘格）：@2x，6 帧循环 @10，原点 = 盾牌中心（JSON scale 1.0）。
// 般若盾是倒三角（PRTS 立绘黑钢盾），沿三条边走一道不等速的金光，三个角先后各亮一下；边线是暗金细线，不画实心、不用棋盘格。
import { fit } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Hoshiguma guard glow",
  desc: "Guard light on the triangular shield: a thin dark-gold outline with a bright glint running unevenly round the edges and corners flaring one after another; seamless loop.",
  tags: ["aura", "shield", "loop"],
  size: [44, 44],
  origin: [22, 22],
  duration: 0.6,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.hoshiguma, seed: 2 },
};

const V = [[-17, -13], [17, -13], [1, 18]];   // 倒三角（略不对称）
export function draw(p, t, o) {
  const C = fit(o.palette, 7), ph = t / meta.duration;
  const L = V.map((v, i) => Math.hypot(V[(i + 1) % 3][0] - v[0], V[(i + 1) % 3][1] - v[1])), tot = L[0] + L[1] + L[2];
  const head = ((ph * ph * 0.6 + ph * 0.4) % 1) * tot;   // 不等速（相位 0 与 1 处同位，循环无缝）
  let acc = 0;
  for (let i = 0; i < 3; i++) {
    const [x0, y0] = V[i], [x1, y1] = V[(i + 1) % 3];
    for (let s = 0; s <= L[i]; s += 0.5) {
      const u = s / L[i], x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u;
      const d = (head - (acc + s) + tot) % tot;            // 光头后面的距离
      const ci = d < 2 ? 6 : d < 8 ? 5 : d < 18 ? 4 : 2;
      p.blend(x, y, C[ci], d < 18 ? 0.95 : 0.55);
    }
    acc += L[i];
  }
  V.forEach(([x, y], i) => {   // 角：先后亮
    const k = Math.max(0, Math.sin((ph * 2 + i * 0.37 + i * i * 0.11) * Math.PI * 2));
    if (k > 0.6) { p.px(x, y, C[6]); p.blend(x + 1, y, C[5], k); p.blend(x, y - 1, C[5], k); }
  });
}
