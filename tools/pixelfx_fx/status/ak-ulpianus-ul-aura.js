// 乌尔比安「放开版」身上的标识（claude/pixelfx-ul-ulpianus，开关 fx/px_unleashed）：原点 = 脚底，往上 -y，地面透视 y × SY。
// move：
//   vein   精二常亮「血纹」（循环）：脚边几缕暗酒红的血雾贴地游走、往上飘散，偶尔一点亮——代替脚下那道红色细圆环（孤立圆形，docs/242 §12.3）
//   haste  S3 之后的「开辟」加速（循环）：脚下往后甩的几缕深海水流 + 小水泡（不画圈）
//   blood  天赋「血脉的哺养」叠一层（一次性）：一缕暗酒红从脚下沿身体往上卷、到胸口一闪散开（代替胸口那团圆光）
import { Rng, fit, clamp, smooth, noise, TAU } from "../../core/index.js";

export const meta = {
  name: "Ulpianus status marks unleashed",
  desc: "Wine-dark blood mist curling round the feet, a deep-sea current trailing behind, or a crimson thread rising up the body.",
  tags: ["status", "buff", "aura", "loop"],
  size: [96, 96],
  origin: [48, 76],
  duration: 1.0,
  loop: true,
  fps: 12,
  bg: "dark",
  options: {
    palette: ["#070a1f", "#121a45", "#1e2d73", "#2f47a3", "#4a68cf", "#7f97ea", "#c3cef7", "#ffffff"],
    blood: ["#1c0710", "#33101c", "#4d1626", "#6b1e33", "#8a2a40"],
    move: "vein",
    layer: "all",
    seed: 3,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), BL = fit(o.blood, 5), Rg = new Rng(o.seed), mv = o.move || "vein";
  const core = o.layer !== "deco", deco = o.layer !== "core";
  let t = 0;
  const N = 12;   // 帧数（1 秒 × 12 fps），循环靠相位回绕
  const wisps = [];
  for (let i = 0, n = mv === "blood" ? 1 : mv === "vein" ? 3 : 5; i < n; i++) wisps.push({ a: Rg.range(-Math.PI, Math.PI), ph: Rg.range(0, 1), r: Rg.range(9, 15), s: Rg.int(0, 999), sp: Rg.chance(0.5) ? 1 : -1 });
  const motes = [];
  for (let i = 0; i < 7; i++) motes.push({ x: Rg.range(-12, 12), ph: Rg.range(0, 1), h: Rg.range(10, 30) });
  return {
    update(dt) { t += dt; },
    draw(p) {
      const ph = (Math.round(t * 12) % N) / N;   // 0..1 循环
      if (mv === "vein") {
        if (core) for (const w of wisps) {   // 贴地游走的血缕：一段弧，沿脚边慢慢转，尾部变淡
          const a0 = w.a + w.sp * ph * TAU;
          for (let s = 0; s < 0.75; s += 0.08) {
            const a = a0 - w.sp * s, rr = w.r * (1 + 0.2 * noise(a * 2 + w.s, o.seed));
            const x = Math.cos(a) * rr, y = Math.sin(a) * rr * SY - s * 3;
            p.blend(x, y, BL[clamp(3 - Math.floor(s * 4), 1, 3)], 0.85 * (1 - s / 0.75));
          }
        }
        if (deco) for (const m of motes) {   // 往上飘的血雾点
          const k = (m.ph + ph) % 1;
          p.blend(m.x + noise(k * 3 + m.x, o.seed + 5) * 2, -k * m.h, k < 0.15 ? BL[4] : BL[2], 0.8 * (1 - k));
        }
      } else if (mv === "haste") {
        if (core) for (const w of wisps) {   // 往身后（-x）甩的水流
          const k = (w.ph + ph) % 1, y0 = Math.sin(w.a) * 6;
          for (let d = 0; d < 16; d += 0.6) {
            const x = 4 - k * 10 - d, y = y0 + noise(d * 0.3 + w.s, o.seed + 9) * 1.4;
            p.blend(x, y, d < 2 ? C[6] : C[clamp(Math.round(5 - d / 6), 3, 5)], 0.9 * (1 - d / 16) * (1 - smooth(0.6, 1, k)));
          }
        }
        if (deco) for (const m of motes) {
          const k = (m.ph + ph) % 1;
          p.blend(m.x * 0.8 - k * 14, -2 - k * 6, C[6], 0.7 * (1 - k));
        }
      } else {   // blood：一次性，按 t（不回绕）
        const u = clamp(t / 0.6);
        if (core) for (let d = 0; d < 36 * Math.min(1, u * 2); d += 0.6) {   // 从脚下沿身体往上卷的一缕
          const v = d / 36, x = Math.sin(v * 5 + o.seed) * (8 - 5 * v), y = -d;
          const fade = 1 - smooth(0.5, 1, u) * (1 - v);
          p.blend(x, y, v > 0.85 ? BL[4] : BL[clamp(Math.round(1 + 2.5 * v), 1, 3)], 0.9 * fade * (1 - smooth(0.75, 1, u)));
        }
        if (core && u > 0.45 && u < 0.62) for (let k = 0; k < 7; k++) {   // 胸口一闪散开（不等距的几点）
          const a = k * 0.9 + noise(k, o.seed) * 0.6, r = 2 + (u - 0.45) * 30 * (0.6 + 0.4 * noise(k * 3, o.seed + 1));
          p.blend(Math.cos(a) * r, -34 + Math.sin(a) * r * 0.7, BL[4], 0.9);
        }
      }
    },
  };
}
