// 拉普兰德终结技「剑气 · 有序推进 → 巨型 X」的单元帧条（docs/242 放开版，草图第三版 tools/pixelfx_fx/ref/lappland_ult*.png 已过用户）。
// 俯视，原点 = 剑气中点，沿 +x 一根笔直的长剑气（不弯、不是月牙）。游戏里（ult_moves_c._la_px_*）：
//   - 推进段：每一波把这根剑气按同一角度、轻微随机的长短和间距排成一道剑气帘，波与波左斜 / 右斜交替（镜像），由近到远一拍一波；
//   - 收尾：heavy = 1 的巨型刃两柄一长一短交成 X，横在扇形中段（原收尾横斩的位置）。
// 终结技不分精英档（docs/242 §10），按 E2 全量：出手一帧白热 → 淡蓝 → 降阶；细长菱形晶片沿刃身剥落（原作 suikuai）；淡蓝切痕余韵。
// 分层：core = 刃身、刃芯亮线；deco = 光晕、晶片、余韵切痕。
import { Rng, fit, hex, clamp, ease, noise } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Lappland ultimate sword-qi",
  desc: "One long straight sword-qi flashes white-hot, cools to pale blue and sheds thin diamond shards; heavy = a giant twin-blade for the finishing X.",
  tags: ["melee", "slash", "line", "topdown", "one-shot"],
  size: [430, 70],
  origin: [215, 35],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],
    len: 70,          // 半长（1x）
    heavy: 0,         // 1 = 收尾巨型刃
    layer: "all",
    seed: 2,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), heavy = +o.heavy > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", BLUE = hex("#cfe6f3");
  const L = +o.len, W = heavy ? 3.2 : 1.6, TG = heavy ? 0.07 : 0.05, DL = heavy ? 0.85 : 0.6;
  const shards = jitterSteps(Rg, 2 * L, heavy ? 5 : 8, heavy ? 12 : 20).map((x) => ({ x: x - L, sg: Rg.chance(0.5) ? 1 : -1, sp: Rg.range(15, heavy ? 70 : 40), r: Rg.range(-0.6, 0.6), s: Rg.range(1, heavy ? 2.6 : 1.8), life: Rg.range(0.25, 0.55) * DL }));
  const flick = jitterSteps(Rg, 2 * L, 6, 16).map((x) => ({ x: x - L, y: Rg.range(-3, 3), ph: Rg.range(0, 6) }));
  let t = 0;
  const shard = (p, x, y, r, s, c) => {
    const pts = [[s * 1.4, 0], [0, s * 0.5], [-s * 1.2, 0], [0, -s * 0.55]].map(([a, b]) => [x + a * Math.cos(r) - b * Math.sin(r), y + a * Math.sin(r) + b * Math.cos(r)]);
    p.poly(pts, c);
  };
  return {
    update(dt) { t += dt; },
    draw(p) {
      const grow = ease.outExpo(clamp((t + 0.02) / TG)), fade = clamp((t - TG - 0.06) / (0.3 + DL * 0.4));
      const hot = t < TG + 0.02, Lx = L * grow;
      // 刃身：中段宽 W、两头收尖，外缘噪声轻微起伏；白热一帧 → 淡蓝 → 降阶
      if (core && fade < 1) {
        const w0 = W * (1 - fade * 0.6);
        for (let x = -Lx; x <= Lx; x += 0.5) {
          const u = Math.abs(x) / Math.max(1, L), w = w0 * Math.pow(1 - u, 0.5) * (1 + 0.15 * noise(x * 0.3, o.seed));
          for (let y = -w; y <= w; y += 0.5) {
            const q = Math.abs(y) / Math.max(w, 0.5);
            p.dot(x, y, hot ? (q < 0.7 ? C[6] : C[5]) : q < 0.35 ? (fade < 0.4 ? C[5] : BLUE) : fade < 0.4 ? BLUE : C[clamp(Math.round(4 - fade * 3), 1, 4)]);
          }
        }
      }
      // 装饰：沿刃身的光晕（密而小，连成光带）、晶片剥落、余韵切痕闪点
      if (deco && fade < 1) for (let x = -Lx; x <= Lx; x += heavy ? 7 : 9) p.glow(x, 0, heavy ? 9 : 6, hot ? C[5] : BLUE, (heavy ? 0.5 : 0.4) * (1 - fade) * (hot ? 1.4 : 1));
      if (deco) for (const s of shards) {
        const v = t - TG * (Math.abs(s.x) / L);
        if (v < 0 || v > s.life) continue;
        const k = 1 - v / s.life;
        if (k > 0.25) shard(p, s.x + v * 8, s.sg * (W + s.sp * v), s.r + v * 3, s.s, k > 0.6 ? C[4] : BLUE);
      }
      if (deco && t > TG) for (const f of flick) {
        const v = t - TG, k = (1 - v / DL) * (0.5 + 0.5 * Math.sin(f.ph + v * 30));
        if (v < DL && k > 0.2) p.blend(f.x, f.y * 0.5, BLUE, Math.min(1, k));
      }
    },
  };
}
