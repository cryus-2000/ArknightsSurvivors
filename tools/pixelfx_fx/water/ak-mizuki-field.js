// 水月 S3「深海中的召唤」每次释放的整片触手（mizuki_s3_fx.gd，替换 fx_mizuki_s3_field）：@2x，保留画布 228 宽、锚点在 (0.5, 0.75)，帧号由代码按释放进度给（6 帧）。
// 原点 = 水月脚下；整片区域里十几根触手不按圈排、位置散落、高矮和弯向各不相同，先后错开钻出 → 梢头卷下抽打 → 从梢往根缩回，地面跟着泛起暗水。
import { Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Mizuki abyss field",
  desc: "A field-wide eruption of jellyfish tentacles scattered (not in a ring) across the area, staggered, each with its own height and lean; they lash down and sink back.",
  tags: ["water", "tentacle", "field", "one-shot"],
  size: [228, 152],
  origin: [114, 114],
  duration: 0.3,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.mizuki],
    seed: 9,
  },
};

const SY = 0.36;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ts = [];
  for (let i = 0; i < 40 && ts.length < 15; i++) {                // 区域内随机散点，彼此间隔 ≥ 16，不排成圈
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.range(0.08, 1)) * 100, x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
    if (ts.some((q) => Math.hypot(q.x - x, (q.y - y) / SY) < 16)) continue;
    ts.push({ x, y, H: Rg.range(22, 58) * (1 - 0.25 * (y + 36) / 72), lean: Rg.range(-0.35, 0.35), d: ts.length < 5 ? 0 : Rg.range(0, 0.05), curl: Rg.range(0.8, 1.8), sd: Rg.range(0, 50) });
  }
  ts.sort((p, q) => p.y - q.y);                                   // 远的先画
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      for (const s of ts) {
        const u = t - s.d;
        if (u < 0) continue;
        const grow = ease.outQuart(clamp((u + 0.04) / 0.09)), lash = smooth(0.08, 0.17, u), ret = smooth(0.15, 0.25, u);
        // 脚下暗水
        const pr = 7 * grow * (1 - ret * 0.6);
        for (let yy = -3; yy <= 3; yy++) for (let xx = -9; xx <= 9; xx++) {
          const q = Math.hypot(xx / pr, yy / (pr * 0.4));
          if (q <= 1) p.blend(Math.round(s.x + xx), Math.round(s.y + yy), C[q > 0.7 ? 3 : 1], (q > 0.7 ? 0.7 : 0.5) * (1 - ret));
        }
        const top = 1 - ret;
        if (top <= 0.03) continue;
        let x = s.x, y = s.y, a = -Math.PI / 2 + s.lean;
        const N = Math.ceil(s.H * 1.8), seen = new Set();
        for (let i = 0; i <= N * top; i++) {
          const v = i / N;
          a += (v > 0.55 ? s.curl * (1 + lash * 1.6) * 3 / N : 0) * Math.sign(s.lean || 0.1) + 0.04 * noise(v * 5, s.sd);
          x += Math.cos(a) * s.H * grow / N; y += Math.sin(a) * s.H * grow / N;
          const w = 3.4 * (1 - v * 0.85) + 0.5;
          for (let d = -w; d <= w; d += 0.5) {
            const q = Math.abs(d) / w, px = Math.round(x + d), py = Math.round(y), k = px * 1000 + py;
            if (seen.has(k)) continue;
            seen.add(k);
            const c = C[clamp(Math.round((q > 0.62 ? 6 : 4) + v * 1.2 - (d > 0 ? 1 : 0) - ret * 2 + (t < 0.03 ? 1.5 : 0)), 2, 7)];
            p.blend(px, py, c, q > 0.62 ? 0.95 : 0.6);
          }
        }
      }
    },
  };
}
