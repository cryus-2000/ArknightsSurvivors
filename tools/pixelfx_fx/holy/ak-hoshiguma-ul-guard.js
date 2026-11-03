// 星熊终结技「般若」举盾硬挡期间的盾面光（放开版，替 fx_hoshiguma_guard_glow 循环）：原点 = 盾心，循环 1.2 s @20。
// 倒三角盾形（PRTS 黑钢盾）：外沿一道金白细线，沿边走两道不等速的亮点；盾面下方不等距地窜起青绿鬼火（原作 S3 / 般若），
// 鬼火高矮、摆幅、出现早晚各异；游戏侧按挡的进度把整张往红色调（col 插值，代码里做），这里只出金 + 青绿。
import { fit, clamp, noise, loopNoise, TAU } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma ultimate guard aura",
  desc: "Shield guard loop: a gold-white triangular outline with two glints running at uneven speeds and teal ghost flames licking up unevenly beneath it.",
  tags: ["aura", "shield", "loop"],
  size: [96, 104],
  origin: [48, 60],
  duration: 1.2,
  loop: true,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#55431b", "#91732e", "#c2993d", "#f2bf4c", "#f7d58b", "#fbecc9", "#ffffff"],
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    layer: "all",
    seed: 2,
  },
};

const V = [[-30, -26], [30, -26], [2, 30]];
const FL = [[-24, 0.13, 0.9], [-15, 0.61, 1.2], [-7, 0.37, 0.8], [1, 0.82, 1.4], [9, 0.05, 1.0], [18, 0.49, 0.7], [26, 0.71, 1.1]];   // [x, 相位, 高倍]：x 间距不等

export function draw(p, t, o) {
  const C = fit(o.palette, 7), J = fit(o.jade, 5), ph = t / meta.duration, core = o.layer !== "deco", deco = o.layer !== "core";
  if (deco) {
    for (const [x0, q, hk] of FL) {   // 鬼火：每束一个循环周期内窜起又熄灭（相位错开）
      const u = (ph + q) % 1, life = Math.sin(Math.PI * u), H = (12 + 10 * hk) * life;
      if (H < 2) continue;
      const by = 26 - Math.abs(x0) * 0.85;   // 沿盾下缘
      for (let d = 0; d < H; d += 0.5) {
        const v = d / H, sway = 3 * loopNoise(ph, 0.8 + d * 0.05, o.seed + Math.round(x0)) * v;
        for (let e = -(1.6 - 1.3 * v); e <= 1.6 - 1.3 * v; e += 0.7)
          p.blend(x0 + sway + e, by - d, J[clamp(Math.round(4 - v * 2.8 - Math.abs(e) * 0.6), 1, 4)], (0.8 - v * 0.5) * life);
      }
    }
    p.glow(0, -4, 34, C[3], 0.22 + 0.06 * Math.sin(ph * TAU));
  }
  if (core) {
    const L = V.map((v, i) => Math.hypot(V[(i + 1) % 3][0] - v[0], V[(i + 1) % 3][1] - v[1])), tot = L[0] + L[1] + L[2];
    const heads = [((ph * 1.0) % 1) * tot, ((ph * 2.0 + 0.37) % 1) * tot];   // 两道亮点不等速（循环内各走整数圈）
    let acc = 0;
    for (let i = 0; i < 3; i++) {
      const [x0, y0] = V[i], [x1, y1] = V[(i + 1) % 3];
      for (let s = 0; s <= L[i]; s += 0.5) {
        const u = s / L[i], x = x0 + (x1 - x0) * u, y = y0 + (y1 - y0) * u + 0.6 * noise(s * 0.3 + i * 7, o.seed);
        let dm = 1e9;
        for (const h of heads) dm = Math.min(dm, (h - (acc + s) + tot) % tot);
        const ci = dm < 3 ? 6 : dm < 10 ? 5 : dm < 22 ? 4 : 3;
        p.blend(x, y, C[ci], dm < 22 ? 1 : 0.75);
      }
      acc += L[i];
    }
  }
}
