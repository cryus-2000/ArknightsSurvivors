// 近战怪攻击起手（怪物风格试点 11-04）：原点 = 爪尖，攻击方向朝右（+x）。
// 预警用危险色 #ff2667（用法不变：只给预警）：一道 1–2 px 的细锐弧光从爪根滑到爪尖，到尖端时一帧短十字闪；0.28 秒内结束。
// 元素 2 种（弧光、十字闪），不画圆、不放光团。
import { Rng, fit, clamp, smooth, ease } from "../../core/index.js";

export const meta = {
  name: "Monster claw windup",
  desc: "A thin danger-red glint slides along the claw to its tip and ends in a short cross flash.",
  tags: ["monster", "windup", "telegraph", "one-shot"],
  size: [48, 40],
  origin: [30, 22],
  duration: 0.3,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: ["#3a0b18", "#8a1838", "#ff2667", "#ff9ab3", "#fff0f4"],   // 危险色阶：#ff2667 居中
    seed: 2,
  },
};

export function create(o) {
  const C = fit(o.palette, 5), Rg = new Rng(o.seed);
  const R = 18, a0 = Math.PI * 0.95, a1 = Math.PI * 0.35 + Rg.range(-0.08, 0.08), cx = -6, cy = 8;
  let t = 0;
  const at = (u) => { const a = a0 + (a1 - a0) * u; return [cx + Math.cos(a) * R, cy - Math.sin(a) * R * 0.9]; };
  return {
    update(dt) { t += dt; },
    draw(p) {
      const head = ease.inQuad(clamp(t / 0.2)), tail = Math.max(0, head - 0.45);
      if (t < 0.24) for (let u = tail; u <= head; u += 0.01) {   // 弧光：头亮（危险色亮阶）尾暗
        const f = (u - tail) / Math.max(0.01, head - tail), [x, y] = at(u);
        p.px(x, y, C[clamp(Math.round(1 + f * 2.4), 1, 3)]);
        if (f > 0.3) p.px(x, y - 1, C[2]);
        if (f > 0.7) p.px(x, y + 1, C[1]);
      }
      if (t >= 0.18 && t < 0.28) {   // 十字闪：到尖端一帧
        const [x, y] = at(1), k = 1 - smooth(0.18, 0.28, t), L = 6 * k + 1;
        for (let d = -L; d <= L; d += 0.5) { p.px(x + d, y, C[t < 0.22 ? 4 : 3]); p.px(x, y + d, C[t < 0.22 ? 4 : 3]); }
      }
    },
  };
}
