// 斯卡蒂终结技「斩浪」水柱（不加限制版，开关 fx/px_unleashed）：原点 = 水柱脚底（地面），往上喷。
// v2（11-04 总组长：原来是一大团同心白柔光 = 大圆盘）：一根有体量、往上涌的水柱，柱身不规则、往上变细；柱根往两侧溅开几片水舌，柱顶碎成水沫；
// 地面亮斑压扁贴着柱根、边缘不规则；光沿柱身走（glowLine），不再有点光源圆盘和圆形水雾。落回时柱身从上往下碎成水滴散掉。
import { Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP } from "../house.js";

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
    palette: ["#0b1529", ...OP.skadi],   // 11-03 §12.6：改用 house.js OP.skadi 7 阶（原水青 #34a8dc / #7fe0f4 和敌方青弹 #33ceff 色差仅 15–18），最暗一阶为压暗底色
    height: 150,
    width: 30,
    layer: "all",   // core / deco / all
    seed: 3,
    spray: 0,       // 往外甩的水珠（1 = 甩；11-04 用户取消「洒水出去」）
  },
};

const UP = 0.16, HOLD = 0.24, FALL = 0.6, GSY = 0.28;   // GSY：地面亮斑压扁比

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), H = o.height, W = o.width, sd = o.seed;
  const core = o.layer !== "deco", deco = o.layer !== "core";   // 分层（docs/242 §8）：core = 柱身 + 柱根水舌 + 柱顶水沫；deco = 地面亮斑、沿柱身的光
  const lean = Rg.range(-0.1, 0.1);
  // 柱根水舌：两侧各 1–2 片，低角度往外上方溅开（不往外甩水珠，11-04 用户取消「洒水出去」）
  const tongues = [];
  for (const side of [-1, 1]) for (let k = 0, n = Rg.int(1, 2); k < n; k++)
    tongues.push({ a: side > 0 ? -Rg.range(0.55, 1.05) : -Math.PI + Rg.range(0.55, 1.05), L: W * Rg.range(1.0, 1.6), w: W * Rg.range(0.16, 0.24), d: Rg.range(0.02, 0.07), bend: side * Rg.range(0.2, 0.45) });
  let t = 0;
  const top = () => H * ease.outExpo(clamp(t / UP)) * (1 - 0.35 * smooth(UP + HOLD, UP + HOLD + FALL, t));
  const brk = () => smooth(UP + HOLD * 0.6, UP + HOLD + FALL, t);   // 0 = 整柱，1 = 碎完
  const cx = (y) => -y * lean + 2.5 * noise(y * 0.045 + t * 2.5, sd);   // y < 0 往上
  const hw = (v, y) => W * 0.5 * (1.05 - 0.5 * v + 0.55 * (1 - smooth(0, 0.16, v))) * (1 + 0.3 * noise(y * 0.09 - t * 7, sd + 3));   // 柱根张开、柱身起伏

  function column(p) {
    const h = top(), b = brk(), hot = t < 0.09 ? 2.2 : t < 0.13 ? 0.8 : 0;
    if (h < 2) return;
    for (let yy = 0; yy <= h; yy += 1) {
      const y = -yy, v = yy / H, c0 = cx(y), w = hw(v, y);
      const jl = 1.6 * noise(yy * 0.37 + t * 11, sd + 7), jr = 1.6 * noise(yy * 0.41 - t * 13, sd + 9);
      const crest = smooth(h - W * 0.9, h, yy);                     // 近柱顶：碎成水沫
      for (let x = -w - jl; x <= w + jr; x += 1) {
        const q = x / w, X = c0 + x;
        const dn = noise(X * 0.5 + 40, y * 0.5 - t * 22 + sd);   // 碎裂 / 水沫的噪声场
        if (b > 0 && dn * 0.5 + 0.5 < b * 1.25 - 0.1 + 0.3 * (1 - v)) continue;   // 落回：从上往下碎成水滴（柱根最后碎）
        if (crest > 0 && dn * 0.5 + 0.5 < crest * 0.75) continue;                    // 柱顶镂空成碎沫
        const st = noise(X * 0.55 + sd, yy * 0.04 - t * 4);                          // 竖向水纹：亮细条往上走
        let ci = Math.round(3.1 + v * 2.2 - q * 0.9 + st * 0.9 + crest * 1.6 + hot);
        ci = clamp(ci, 1, hot > 1 ? 7 : 6);
        p.px(X, y, C[ci]);
      }
    }
    // 柱顶水沫：柱顶上方再冒出一层碎沫（像素簇，不画圆）
    const cr = smooth(UP * 0.6, UP, t) * (1 - smooth(UP + HOLD * 0.8, UP + HOLD + FALL * 0.45, t));
    if (cr > 0) for (let yy = 0; yy < W * 0.9; yy++) for (let x = -W * 0.8; x <= W * 0.8; x++) {
      const y = -h - yy + 4 + 60 * Math.max(0, t - UP - HOLD) ** 2, X = cx(-h) + x, r = Math.abs(x) / (W * 0.8) + yy / (W * 0.9);
      const n = noise(X * 0.45 + 11, y * 0.45 - t * 16 + sd) * 0.5 + 0.5;
      if (n > 0.95 - 0.55 * cr * (1 - r)) p.px(X, y, C[n > 0.98 - 0.3 * cr ? 7 : 6]);
    }
  }
  function tongue(p) {
    for (const j of tongues) {
      const u = t - j.d;
      if (u <= 0) continue;
      const head = ease.outExpo(clamp(u / 0.12)) * j.L, tail = smooth(0.18, 0.5, u) * j.L;
      if (head - tail < 1) continue;
      for (let d = tail; d <= head; d += 0.5) {
        const v = d / j.L, a = j.a + j.bend * v * v, half = Math.max(0.5, j.w * (1 - 0.8 * v));
        const x = Math.cos(a) * d * 1.1 + Math.sign(Math.cos(a)) * W * 0.35, y = Math.sin(a) * d * 0.8, nx = -Math.sin(a), ny = Math.cos(a);
        for (let s2 = -half; s2 <= half; s2 += 0.5) {
          if (v > 0.7 && noise(d * 0.9, s2 + sd) > 0.3) continue;   // 舌尖碎开
          p.px(x + nx * s2, y + ny * s2 * 0.6, C[clamp(Math.round(3 + v * 2.6 - s2 / half * 0.7), 1, 6)]);
        }
      }
    }
  }
  function ground(p) {   // 地面亮斑：压扁、贴柱根、边缘不规则（不是正圆）
    const k = smooth(0, 0.06, t) * (1 - smooth(0.6, 1.3, t));
    if (k <= 0) return;
    const RX = W * 1.35, RY = RX * GSY;
    p.shade(-RX * 1.5, -RY * 2, RX * 1.5, RY * 2, (x, y, out) => {
      const a = Math.atan2(y / GSY, x), r = Math.hypot(x, y / GSY);
      const Rr = RX * (1 + 0.32 * noise(a * 2.1 + 3, sd + 21) + 0.14 * noise(a * 6.3, sd + 23));
      if (r >= Rr) return;
      const f = 1 - r / Rr;
      out.c = f > 0.55 ? C[4] : C[2];
      out.a = Math.min(0.6, f * 1.4) * 0.55 * k;
    });
  }
  return {
    update(dt) { t += dt; },
    drawBack(p) {
      if (deco) ground(p);
      if (core) tongue(p);
    },
    draw(p) {
      if (core) column(p);
      if (deco) {   // 光沿柱身走：一条贴着柱子的光带，不是一盏圆灯
        const h = top(), k = (t < 0.1 ? 0.55 : 0.3) * (1 - brk());
        if (h > 4) p.glowLine(cx(-4), -4, cx(-h * 0.85), -h * 0.85, W * 0.9, C[5], k);
      }
    },
  };
}
