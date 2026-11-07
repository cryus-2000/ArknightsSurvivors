// 乌尔比安的四爪巨锚（概念动画用，约 22 px）：a = 朝向（0 = 锚冠朝下），深海青蓝 + 受光沿
import { hex } from "../../core/index.js";
export const UL = ["#0c1235", "#1a2766", "#2e45a0", "#4463c8", "#7b93e6", "#c0cbf6", "#ffffff"].map(hex);

export function anchor(p, x, y, a = 0, s = 1, al = 1) {
  const c = Math.cos(a), si = Math.sin(a), P = (u, v) => [x + (u * c - v * si) * s, y + (u * si + v * c) * s];
  const seg = (u0, v0, u1, v1, w, col) => { const [x0, y0] = P(u0, v0), [x1, y1] = P(u1, v1); p.beam(x0, y0, x1, y1, w * s, col, al); };
  seg(0, -14, 0, 8, 3, UL[2]);                  // 锚杆
  seg(-6, -9, 6, -9, 2.4, UL[2]);               // 横杆
  seg(0, 8, -9, 2, 2.6, UL[2]); seg(0, 8, 9, 2, 2.6, UL[2]);     // 两爪
  seg(0, 8, -5, 11, 2.2, UL[1]); seg(0, 8, 5, 11, 2.2, UL[1]);   // 后两爪（暗）
  const [rx, ry] = P(0, -16); p.ring(rx, ry, 3 * s, 1.2, UL[4], al);
  const [a0, b0] = P(-1, -13), [a1, b1] = P(-1, 7); p.line(a0, b0, a1, b1, UL[5], al);
  const [t0, u0] = P(-9, 2), [t1, u1] = P(9, 2); p.px(t0, u0, UL[6]); p.px(t1, u1, UL[6]);
}

export function chain(p, x0, y0, x1, y1, al = 1, sag = 0) {
  const n = Math.max(2, Math.floor(Math.hypot(x1 - x0, y1 - y0) / 5));
  for (let i = 0; i <= n; i++) {
    const u = i / n, x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u + sag * Math.sin(Math.PI * u);
    if (i % 2) p.ellipse(x, y, 2.4, 1.4, UL[3], al); else p.ellipse(x, y, 1.4, 2.2, UL[2], al);
    p.dot(x - 1, y - 1, UL[5], al);
  }
}
