// 星熊终结技「般若」反震放开版：盾阵边上一小段地面掀起（游戏里沿 R 处的六边形原地摆一圈，ult_moves_c._ho_step 反震那一下），原点 = 这一段的中点，俯视 sy 0.55。
// 一段 = 一道沿切向（水平）的锯齿断口 + 断口上 2–3 块石板掀起（板顶青绿亮边，同盾砸地 ultslam）+ 板缝窜起一两束鬼火 + 几粒碎石原地往上蹦。
// 不外扩、不往外甩（用户 11-04）；一圈十几段由游戏按六边形摆，seed 变体错开形状；终结技不分档。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma ultimate counter-shock slab burst",
  desc: "One segment of the counter-shock: a jagged break opens along the ground, two or three stone slabs heave up with teal-lit tops, ghost flames lick from the seams and grit pops straight up.",
  tags: ["impact", "ground", "ultimate", "one-shot"],
  size: [72, 64],
  origin: [36, 46],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // 钢色 = PRTS 黑钢盾；不用金（§12.6）
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    dust: ["#14110d", "#2c261d", "#4a4032", "#6e604b", "#958468"],
    half: 24,   // 这一段沿切向的半长（游戏按 R 与段数摆，段间留缝）
    layer: "all",
    seed: 31,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), J = fit(o.jade, 5), D = fit(o.dust, 5), Rg = new Rng(o.seed);
  const H = +o.half, core = o.layer !== "deco", deco = o.layer !== "core";
  const slabs = [];
  for (let x = -H + Rg.range(2, 8); x < H - 4; x += Rg.range(10, 18))
    slabs.push({ x, w: Rg.range(5, 9), h: Rg.range(5, 12), lean: Rg.range(-0.3, 0.3), d: Rg.range(0, 0.06), shade: Rg.int(1, 3) });
  const flames = slabs.filter(() => Rg.chance(0.6)).map((s) => ({ x: s.x + Rg.range(-2, 2), h: Rg.range(14, 26), d: s.d + Rg.range(0.03, 0.12), ph: Rg.range(0, 6), lean: Rg.range(-0.3, 0.3) }));
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] });
  let t = 0, fired = false;
  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        if (deco) for (const s of slabs) for (let i = 0, n = Rg.int(1, 3); i < n; i++)   // 碎石 / 火星：原地往上蹦（不往外甩）
          ps.spawn(i ? P.SPARK : P.GRIT, s.x + Rg.range(-3, 3), 0, Rg.range(-12, 12), -Rg.range(60, 140), Rg.range(0.3, 0.55), i ? 0 : D[3 + Rg.int(0, 1)], 1, s.d);
      }
      ps.update(dt);
    },
    draw(p) {
      const ck = 1 - smooth(0.25, 0.6, t);
      // —— 核心：锯齿断口（水平一道，带缺口），首帧白热 → 翠绿 → 暗
      if (core && ck > 0) for (let x = -H; x <= H; x += 0.5) {
        if (noise(x * 0.35, o.seed + 4) < -0.35) continue;
        const y = 1.6 * noise(x * 0.5, o.seed + 2), c = t < 0.05 ? C[6] : t < 0.1 ? C[5] : J[clamp(Math.round(4 - t * 5), 1, 4)];
        p.blend(x, y, c, ck);
      }
      // —— 核心：石板（掀起 → 停住 → 沉回），板顶青绿亮边、板身钢灰
      if (core) for (const s of slabs) {
        const v0 = t - s.d;
        if (v0 < 0) continue;
        const up = ease.outBack(clamp(v0 / 0.08)) * (1 - smooth(0.3, 0.65, v0)), H0 = s.h * up;
        if (H0 < 1) continue;
        for (let e = -s.w / 2; e <= s.w / 2; e += 0.5) {
          const ev = Math.abs(e) / (s.w / 2), Hh = H0 * (0.95 - 0.45 * ev * ev + 0.25 * noise(e * 0.9 + s.x, o.seed + 7));
          for (let d = 0; d <= Hh; d += 0.5) {
            const top = d > Hh - 1.2;
            p.blend(s.x + e + s.lean * d, -d, top ? J[v0 < 0.06 ? 4 : v0 < 0.3 ? 3 : 2] : C[clamp(s.shade + (e > 0 ? 1 : 0) - (d < 1.5 ? 1 : 0), 0, 3)], 1);
          }
        }
      }
      if (deco) {
        for (const f of flames) {   // 鬼火：板缝窜起
          const v0 = t - f.d;
          if (v0 < 0) continue;
          const life = clamp(v0 / 0.08) * (1 - smooth(0.25, 0.6, v0)), Hf = f.h * life;
          if (Hf < 1) continue;
          for (let d = 0; d < Hf; d += 0.5) {
            const v = d / Hf, sway = 2.5 * noise(f.ph + d * 0.18 + v0 * 7, o.seed + 5) * v + f.lean * d;
            for (let e = -(1.6 - 1.3 * v); e <= 1.6 - 1.3 * v; e += 0.7)
              p.blend(f.x + sway + e, -d, J[clamp(Math.round(4 - v * 2.6 - Math.abs(e) * 0.6), 1, 4)], (0.85 - v * 0.5) * life);
          }
        }
        ps.draw(p);
      }
    },
  };
}
