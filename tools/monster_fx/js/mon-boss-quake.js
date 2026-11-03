// Boss 技能演出（怪物风格试点 11-04，「途」放刃环技能时）：原点 = Boss 脚底。
// phase 0（预警，0.6 秒）：脚下裂出不规整分叉裂网，缝里暗、缝沿危险色描边，一路慢慢爬开（读得出「要炸了」，形状不规整，不是同心圈）。
// phase 1（爆发，0.9 秒）：裂网一帧爆亮 → 冷却成暗红；沿裂缝隆起一道碎尘墙、碎块蹦起落回；尘墙慢慢塌下。
// 取 10-30 用户认可的「裂地 v3」做法（不规整分叉裂网 + 爆亮冷却 + 隆起尘墙），不画环、不放圆光。元素 ≤3 种（裂网、尘墙、碎块）。
import { Rng, fit, clamp, smooth, ease, noise, noise2, TAU } from "../../core/index.js";

export const meta = {
  name: "Boss quake cast",
  desc: "A ragged forking crack web creeps out from the boss's feet with danger-red lips, then flares, cools and throws up a crumbling dust wall with hopping chunks.",
  tags: ["monster", "boss", "quake", "crack", "one-shot"],
  size: [200, 120],
  origin: [100, 70],
  duration: 1.5,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#0d1018", "#1f2533", "#3b4458", "#6a7489", "#a4acbd"],   // 地面 / 尘
    danger: ["#3a0b18", "#8a1838", "#ff2667", "#ffd0dc"],
    seed: 6,
  },
};

const SY = 0.62, TELL = 0.6;

export function create(o) {
  const C = fit(o.palette, 5), D = fit(o.danger, 4), Rg = new Rng(o.seed);
  // 裂网：5–7 条主缝不等角、不等长，每条随机拐折，并在中段分叉
  const cracks = [];
  const grow = (x, y, a, L, depth, t0) => {
    const pts = [[x, y]];
    let cx = x, cy = y, ca = a;
    for (let d = 0; d < L; d += 3) { ca += Rg.range(-0.35, 0.35); cx += Math.cos(ca) * 3; cy += Math.sin(ca) * 3 * SY; pts.push([cx, cy]); }
    cracks.push({ pts, t0, w: depth === 0 ? 2 : 1 });
    if (depth === 0) for (let k = 0, m = Rg.int(1, 2); k < m; k++) {
      const i = Rg.int(Math.floor(pts.length * 0.3), pts.length - 2);
      grow(pts[i][0], pts[i][1], ca + Rg.range(0.5, 0.9) * (Rg.chance(0.5) ? 1 : -1), L * Rg.range(0.35, 0.55), 1, t0 + 0.12 + i * 0.01);
    }
  };
  for (let i = 0, n = Rg.int(5, 7), a0 = Rg.range(0, TAU); i < n; i++) grow(0, 0, a0 + (i + Rg.range(-0.3, 0.3)) * TAU / n, Rg.range(48, 82), 0, Rg.range(0, 0.08));
  const chunks = [];
  for (const c of cracks) if (c.w === 2) for (let i = 2; i < c.pts.length; i += Rg.int(3, 5)) {
    const [x, y] = c.pts[i];
    chunks.push({ x, y, vx: Rg.range(-30, 30), vy: -Rg.range(60, 130), s: Rg.int(2, 3), c: Rg.int(2, 4), d: Rg.range(0, 0.06) });
  }
  let t = 0;
  function crackDraw(p, prog, colEdge, colIn, wk) {
    for (const c of cracks) {
      const u = clamp((prog - c.t0) / 0.45);
      if (u <= 0) continue;
      const n = Math.max(2, Math.round(c.pts.length * u));
      for (let i = 1; i < n; i++) {
        const [x0, y0] = c.pts[i - 1], [x1, y1] = c.pts[i], v = i / c.pts.length, w = Math.max(0, Math.round((c.w - 1) * wk * (1.3 - v)));
        const L = Math.hypot(x1 - x0, y1 - y0) || 1, nx = -(y1 - y0) / L, ny = (x1 - x0) / L;   // 沿缝法线方向铺宽度（原来竖着铺，横缝被压成一条粗带）
        for (let s = 0; s <= 1; s += 0.25) {
          const x = x0 + (x1 - x0) * s, y = y0 + (y1 - y0) * s;
          for (let d = -w - 1; d <= w + 1; d++) p.px(x + nx * d, y + ny * d, Math.abs(d) > w ? colEdge : colIn);
        }
      }
    }
  }
  return {
    update(dt) { t += dt; },
    drawBack(p) {
      if (t < TELL) crackDraw(p, t, D[2 - (Math.floor(t * 12) % 2)], C[0], 1);   // 预警：缝沿危险色（两阶闪），缝里暗
      else {
        const u = t - TELL, hot = u < 0.05;   // 爆亮 1 帧 → 冷却成暗红 → 合回地面色
        const edge = hot ? D[3] : u < 0.35 ? D[2 - Math.min(1, Math.floor(u / 0.15))] : D[0];
        if (u < 0.8) crackDraw(p, 9, edge, hot ? D[3] : C[0], hot ? 1.3 : 1.2 * (1 - smooth(0.4, 0.8, u)) + 0.3);
      }
    },
    draw(p) {
      const u = t - TELL;
      if (u < 0) return;
      // 尘墙：沿主缝竖起一排不规则尘柱，先高后塌（像素格点阵，靠噪声镂空）
      const hw = ease.outCubic(clamp(u / 0.12)) * (1 - smooth(0.25, 0.85, u));
      if (hw > 0.02) for (const c of cracks) {
        if (c.w !== 2) continue;
        for (let i = 1; i < c.pts.length; i += 1) {
          const [x, y] = c.pts[i], h = hw * (22 + 12 * noise(i * 0.7, o.seed + 11)) * (1 - i / c.pts.length * 0.5);
          for (let yy = 0; yy < h; yy++) {
            const n = noise2(x * 0.4 + yy * 0.3, yy * 0.5 - u * 20, o.seed) * 0.5 + 0.5;
            if (n < 0.3 + 0.5 * (yy / h)) continue;
            p.px(x + noise(yy * 0.4, i) * 1.5, y - yy, C[clamp(Math.round(1 + (1 - yy / h) * 2.6), 1, 4)]);
          }
        }
      }
      for (const ch of chunks) {   // 碎块：蹦起落回、落地变暗消失
        const v = u - ch.d;
        if (v < 0 || v > 0.75) continue;
        const y = ch.y + ch.vy * v + 300 * v * v, land = y >= ch.y && v > 0.05, yy = land ? ch.y : y;
        const col = C[clamp(ch.c - (land ? 2 : 0), 0, 4)];
        for (let dx = 0; dx < ch.s; dx++) for (let dy = 0; dy < ch.s; dy++) p.px(ch.x + ch.vx * Math.min(v, 0.4) + dx, yy - dy, col);
      }
    },
  };
}
