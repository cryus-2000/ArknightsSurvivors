// 星熊终结技「般若」放开版：盾砸地（盾阵 110 = 游戏 _hex 内圈，ult_moves_c._ho_start），俯视地面透视 sy 0.55，原点 = 星熊脚下。
// 和 S1 拉开（§12.1）：S1 是落点往外的放射裂网；终结技是整片地面沿「盾阵」六边形断开——盾阵边上一圈锯齿六边形断口从六个角原地裂开，
// 断口上不等距地掀起石板（板顶被青绿照亮），板缝里窜起高鬼火，持续到举盾硬挡开始；中间是倒三角盾印（白热后转翠绿）。
// 终结技不分档，按 E2 全量。六边形只画一道（与游戏 _hex 两道线叠在同一位置，不另加同心圈）；断口带缺口、边缘噪声起伏。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { jitterSteps } from "../house.js";

export const meta = {
  name: "Hoshiguma ultimate shield-formation slam",
  desc: "Ultimate shield slam: the ground splits along a jagged hexagon, stone slabs heave up along the break lit teal from below, tall ghost flames rise from the seams and a triangular shield brand glows at the centre.",
  tags: ["impact", "slam", "ground", "ultimate", "one-shot"],
  size: [164, 124],
  origin: [82, 80],
  duration: 1.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // 钢色 = PRTS 黑钢盾；不用金（§12.6）
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    dust: ["#14110d", "#2c261d", "#4a4032", "#6e604b", "#958468"],
    radius: 55,
    layer: "all",
    seed: 21,
  },
};

const SY = 0.55, HIT = 0.05, TAIL = 1.0;

export function create(o) {
  const C = fit(o.palette, 7), J = fit(o.jade, 5), D = fit(o.dust, 5), Rg = new Rng(o.seed);
  const R = o.radius, core = o.layer !== "deco", deco = o.layer !== "core";
  const V = [0, 1, 2, 3, 4, 5].map((k) => [Math.cos(k * Math.PI / 3), Math.sin(k * Math.PI / 3)]);
  const hexAt = (s, r) => {   // 周长参数 s ∈ [0, 6) → 六边形上的点（未压透视）
    const k = Math.floor(s) % 6, f = s - Math.floor(s), a = V[k], b = V[(k + 1) % 6];
    return [(a[0] + (b[0] - a[0]) * f) * r, (a[1] + (b[1] - a[1]) * f) * r];
  };
  // 石板：沿断口不等距（随机步长），宽 4–8、高 4–10、往外倾
  const slabs = jitterSteps(Rg, 6, 0.28, 0.75).map((s) => {
    const [x, y] = hexAt(s, R * Rg.range(0.94, 1.03));
    return { x, y: y * SY, w: Rg.range(4, 8), h: Rg.range(4, 10), lean: Math.sign(x || 1) * Rg.range(0.1, 0.45), d: Rg.range(0.02, 0.09), shade: Rg.int(1, 3) };
  });
  const flames = slabs.filter(() => Rg.chance(0.55)).map((s) => ({ x: s.x + Rg.range(-2, 2), y: s.y + 1, h: Rg.range(14, 30), d: s.d + Rg.range(0.04, 0.2), ph: Rg.range(0, 6), lean: Rg.range(-0.35, 0.35) }));
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[6], C[5], C[4], C[3]] }), lights = new Lights();
  let t = 0, hit = false;
  return {
    update(dt) {
      t += dt;
      if (!hit && t >= HIT) {
        hit = true;
        lights.add(0, -2, 12, C[5], 0.45, 0.12);
        if (deco) {
          for (const s of slabs) {   // 板下迸出的碎石 + 火星
            for (let i = 0, n = Rg.int(1, 3); i < n; i++) {
              const a = Math.atan2(s.y / SY, s.x) + Rg.range(-0.4, 0.4), sp = Rg.range(40, 120);
              ps.spawn(i ? P.SPARK : P.GRIT, s.x, s.y, Math.cos(a) * sp * 0.12, -Rg.range(60, 150), Rg.range(0.3, 0.6), i ? 0 : D[3 + Rg.int(0, 1)], 1, s.d);
            }
            if (Rg.chance(0.5)) ps.spawn(P.DUST, s.x, s.y, Rg.range(-4, 4), -Rg.range(8, 22), Rg.range(0.5, 0.9), D[1 + Rg.int(0, 2)], Rg.range(1.6, 3.4), s.d + 0.03);
          }
          for (let i = 0; i < 14; i++) {   // 青绿碎晶往上飘
            const a = Rg.range(0, Math.PI * 2), r = R * Rg.range(0.3, 0.95);
            ps.spawn(P.MOTE, Math.cos(a) * r, Math.sin(a) * r * SY, Rg.range(-15, 15), -Rg.range(20, 60), Rg.range(0.6, 1.1), J[3 + Rg.int(0, 1)], Rg.range(0.9, 1.4), Rg.range(0.05, 0.4));
          }
        }
      }
      ps.update(dt); lights.update(dt);
    },
    draw(p) {
      const u = t - HIT;
      // —— 蓄势（第 0 帧）：盾从上方压下的一道竖向钢色残影
      if (core && u < 0) for (let y = -26; y < -6; y += 0.5) p.blend(0.4 * noise(y * 0.5, o.seed), y, C[4], 0.5 + (y + 26) / 40);
      if (u < 0) return;
      const ck = 1 - smooth(0.2, 0.2 + TAIL, u), open = ease.outExpo(clamp(u / 0.1));
      // —— 核心：六边形断口（只一道），就在盾阵边上原地裂开：从六个角沿边往两头裂，不从中间往外扩（用户 11-04：外扩环一律不做）；
      //    带缺口、法向噪声起伏；首帧白热 → 余热 → 翠绿 → 暗绿
      if (core && ck > 0) {
        const r = R, ci = u < 0.05 ? 6 : u < 0.1 ? 5 : 0;
        for (let s = 0; s < 6; s += 0.4 / r) {
          const f = s - Math.floor(s);
          if (Math.min(f, 1 - f) > 0.5 * open) continue;
          if (noise(s * 3.1, o.seed + 4) < -0.32) continue;
          const [x, y] = hexAt(s, r), k = Math.floor(s) % 6, nx = (V[k][0] + V[(k + 1) % 6][0]) / 2, ny = (V[k][1] + V[(k + 1) % 6][1]) / 2;
          const j = 1.4 * noise(s * 9, o.seed + 2);
          const c = ci ? C[ci] : J[clamp(Math.round(4 - u * 3), 1, 4)];
          p.blend(x + nx * j, (y + ny * j) * SY, c, ck);
          if (u < 0.5) p.blend(x + nx * j, (y + ny * j) * SY + 1, ci ? C[ci - 1] : J[clamp(Math.round(3 - u * 3), 1, 3)], ck * 0.7);
        }
      }
      // —— 核心：倒三角盾印（中间，压透视），白热后转翠绿，慢慢冷下去
      if (core && ck > 0) {
        const T3 = [[-16, -12], [16, -12], [1, 16]];
        for (let i = 0; i < 3; i++) {
          const [x0, y0] = T3[i], [x1, y1] = T3[(i + 1) % 3];
          p.line(x0, y0 * SY - 2, x1, y1 * SY - 2, u < 0.05 ? C[6] : u < 0.1 ? C[5] : J[clamp(Math.round(4 - u * 2.5), 1, 4)], ck);
        }
      }
      // —— 核心：石板（掀起 → 停住 → 沉回），板身钢灰、板顶一道青绿亮边
      if (core) for (const s of slabs) {
        const v0 = u - s.d;
        if (v0 < 0) continue;
        const up = ease.outBack(clamp(v0 / 0.08)) * (1 - smooth(0.3, 0.7, v0)), H0 = s.h * up;
        if (H0 < 1) continue;
        for (let e = -s.w / 2; e <= s.w / 2; e += 0.5) {   // 逐列：板顶参差（噪声），两侧收窄成碎岩，不是方块
          const ev = Math.abs(e) / (s.w / 2), H = H0 * (0.95 - 0.45 * ev * ev + 0.25 * noise(e * 0.9 + s.x, o.seed + 7));
          for (let d = 0; d <= H; d += 0.5) {
            const top = d > H - 1.2;
            p.blend(s.x + e + s.lean * d, s.y - d, top ? J[v0 < 0.06 ? 4 : v0 < 0.3 ? 3 : 2] : C[clamp(s.shade + (e > 0 ? 1 : 0) - (d < 1.5 ? 1 : 0), 0, 3)], 1);
          }
        }
      }
      if (deco) {
        const gk = 0.3 * (1 - smooth(0.05, 0.4, u));   // 光只挂在六个角上（断口最亮的地方），不画中心圆光（§12.3）
        if (gk > 0.01) for (const [x, y] of V) p.glow(x * R, y * R * SY, 7, J[3], gk);
        for (const f of flames) {   // 鬼火：从板缝窜起，比 S1 高、持续到挡的开头
          const v0 = u - f.d;
          if (v0 < 0) continue;
          const life = clamp(v0 / 0.08) * (1 - smooth(0.3, 0.3 + TAIL * 0.8, v0)), H = f.h * life;
          if (H < 1) continue;
          for (let d = 0; d < H; d += 0.5) {
            const v = d / H, sway = 2.5 * noise(f.ph + d * 0.18 + v0 * 7, o.seed + 5) * v + f.lean * d;
            for (let e = -(1.6 - 1.3 * v); e <= 1.6 - 1.3 * v; e += 0.7)
              p.blend(f.x + sway + e, f.y - d, J[clamp(Math.round(4 - v * 2.6 - Math.abs(e) * 0.6), 1, 4)], (0.85 - v * 0.5) * life);
          }
        }
        ps.draw(p); lights.draw(p);
      }
    },
  };
}
