// 斯卡蒂终结技「斩浪」水柱（不加限制版，开关 fx/px_unleashed）：原点 = 水柱脚底（地面），往上喷。
// 地面一记爆亮 → 白热水柱拔起（柱身不规整、往上变细、边缘甩水）→ 顶端炸成水冠 → 水珠抛物线落回、脚下一圈不规整水花、水雾慢慢散。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Skadi geyser unleashed",
  desc: "A fan of uneven sea-water jets bursts up from the ground, white at the tips, breaks into falling droplets over a ragged splash and leaves mist.",
  tags: ["water", "geyser", "burst", "column", "one-shot"],
  size: [180, 240],
  origin: [90, 200],
  duration: 1.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#040c1c", "#08224a", "#0f4280", "#1a6cb4", "#34a8dc", "#7fe0f4", "#d4fbff", "#ffffff"],
    height: 150,
    width: 30,
    layer: "all",   // core / deco / all
    seed: 3,
  },
};

const SY = 0.5, UP = 0.16, HOLD = 0.22, FALL = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), H = o.height, W = o.width;
  const core = o.layer !== "deco", deco = o.layer !== "core";   // 分层（docs/242 §8）：core = 水刺 + 出水白闪；deco = 水面、水珠水雾、光
  const ps = new Particles({ rng: Rg, ground: () => 0, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] }), lights = new Lights();
  lights.add(0, -10, 70, C[6], 1.0, 0.3);
  const lean = Rg.range(-0.12, 0.12);
  let t = 0, crowned = false, fell = false, spray = 0;
  const top = () => H * ease.outExpo(clamp(t / UP)) * (1 - smooth(UP + HOLD, UP + HOLD + FALL, t));

  // 水刺扇：7–11 股从脚底往上扇形喷出，角度 / 长短 / 粗细 / 出手先后都不一样；尖端白、根部深，左上受光；到顶后根部先收、尖端碎成水珠
  const jets = [];
  for (let k = 0, n = Rg.int(7, 11); k < n; k++) {
    const u = (k + Rg.range(0.1, 0.9)) / n;
    const mid = Math.abs(u - 0.5) * 2;                               // 0 = 中间（最高最粗），1 = 两边
    jets.push({ a: -Math.PI / 2 + (u - 0.5) * Rg.range(1.3, 1.7), L: H * (1 - 0.55 * mid) * Rg.range(0.65, 1.05), w: W * 0.34 * (1.25 - 0.6 * mid) * Rg.range(0.7, 1.2),
      d: Rg.range(0, 0.05) + mid * 0.03, bend: Rg.range(-0.25, 0.25) });
  }
  function jetsDraw(p, far) {
    for (const j of jets) {
      const u = t - j.d;
      if (u <= 0) continue;
      const head = ease.outExpo(clamp(u / UP)) * j.L, tail = smooth(UP + HOLD * 0.5, UP + HOLD + FALL * 0.6, u) * j.L;
      if (head - tail < 1) continue;
      const left = Math.cos(j.a) < -0.05;
      if (far !== left) continue;                                  // 左半边的算远层（暗一阶）
      const hot = u < UP * 0.5 ? 2 : 0;
      for (let d = tail; d <= head; d += 0.5) {
        const v = d / j.L, a = j.a + j.bend * v * v;
        const x = Math.cos(a) * d, y = Math.sin(a) * d, half = Math.max(0.5, j.w * (1 - 0.85 * v));
        const nx = -Math.sin(a), ny = Math.cos(a);
        for (let s2 = -half; s2 <= half; s2 += 0.5) {
          const q = s2 / half;                                      // -1 左缘（受光）
          const ci = clamp(Math.round(3.4 + v * 3.2 - q * 0.9 - (far ? 1 : 0) + hot), 1, 7);
          p.px(x + nx * s2, y + ny * s2, C[ci]);
        }
      }
    }
  }
  return {
    update(dt) {
      t += dt;
      const h = top();
      // 柱身边缘一路往外甩水
      spray += dt;
      while (spray > 0.012 && t < UP + HOLD) {
        spray -= 0.012;
        const j = jets[Rg.int(0, jets.length - 1)], d = j.L * Rg.range(0.3, 1) * (h / H);
        ps.spawn(P.SPARK, Math.cos(j.a) * d, Math.sin(j.a) * d, Math.cos(j.a) * Rg.range(40, 140) + Rg.range(-40, 40), Math.sin(j.a) * Rg.range(40, 140), Rg.range(0.3, 0.7));
      }
      if (!crowned && t >= UP) {
        crowned = true;
        lights.add(0, -H * 0.5, 60, C[6], 0.8, 0.35);
        for (const j of jets) {
          const x = Math.cos(j.a) * j.L, y = Math.sin(j.a) * j.L;
          for (let i = 0; i < 5; i++) {
            const a = j.a + Rg.range(-0.6, 0.6), sp = Rg.range(60, 200);
            ps.spawn(i % 3 ? P.SPARK : P.MOTE, x, y, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.45, 0.9), C[5 + Rg.int(0, 2)], Rg.range(0.8, 1.3));
          }
          if (Rg.chance(0.5)) ps.spawn(P.VAPOUR, x, y, Math.cos(j.a) * 20, Math.sin(j.a) * 20, Rg.range(0.5, 0.9), C[5], Rg.range(4, 8));
        }
      }
      if (!fell && t >= UP + HOLD) {
        fell = true;
        // 落回：脚下一圈不规整水花（角度不等距）+ 贴地水雾
        for (let a = Rg.range(0, 0.4); a < TAU; a += Rg.range(0.2, 0.55)) {
          const r = W * Rg.range(0.7, 1.4), sp = Rg.range(50, 160);
          ps.spawn(P.SPARK, Math.cos(a) * r, Math.sin(a) * r * SY, Math.cos(a) * sp, Math.sin(a) * sp * SY - Rg.range(60, 180), Rg.range(0.3, 0.6));
          ps.spawn(P.VAPOUR, Math.cos(a) * r, Math.sin(a) * r * SY - 3, Math.cos(a) * 30, Math.sin(a) * 12, Rg.range(0.6, 1.0), C[4], Rg.range(5, 9), Rg.range(0, 0.1));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      // 脚下水面：暗色不规整的一摊，先涌起后慢慢退
      const k = smooth(0, 0.08, t) * (1 - smooth(0.7, 1.35, t));
      if (deco && k > 0) {
        p.disc(0, 0, W * 1.2, C[1], 0.3 * k);   // 水面：真半透明
      }
      if (core) jetsDraw(p, true);
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (core) jetsDraw(p, false);
      if (core && t < 0.07) p.disc(0, -4, 14 * (1 - t / 0.07) + 6, C[7], 0.95);
      if (deco) {
        ps.draw(p, "front");
        lights.draw(p);
      }
    },
  };
}
