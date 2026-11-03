// 凯尔希治疗（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：画在受治疗者脚下（原点 = 脚底），侧视略俯（竖直方向 = 屏幕上下）。
// 原作参照（build/ark_ref/kaltsit，kalts_attack_01_hit）：落点绿色爆闪 + 十字（shizi_03）往上飘 + 黄绿星点；颜色取本人黄绿色阶的高亮段（§11.2 #4：不用红 / 品红，不定格）。
// 11-04 用户：往外发散的光环一律不要 → 不画地面扩散圈。
// 构成：核心 = 「到达」那一下：几道细竖光从脚下往上缝合（不等高、不等距）+ 胸口一枚医疗十字闪亮；装饰 = 十字小标 / 星点往上飘。
// move：heal（普攻治疗）/ s1（结构加固：治疗 + 骨白外壳片在身周合拢）/ regen（结构加固·再生：同 heal，多一层往上收的光点）。
// 精英档：E0 两道竖光；E1 三道 + 十字小标飘升（精一治疗量提升）；E2 四道、竖光顶端带骨白芯、十字更大（精二治疗总倍率）。
import { Particles, Rng, fit, clamp, smooth, ease, noise, hex, TAU, P } from "../../core/index.js";

// 实色：painter.put 在 a < 1 时按 Bayer 点阵抖动（棋盘格脏点，§12 画面不能脏）；本作一律 a ≥ 0.5 画实、< 0.5 不画，淡出靠色阶变暗
function solid(p) {
  if (p._solid) return;
  const f = p.put.bind(p);
  p.put = (sx, sy, c, a = 1) => { if (a < 0.999) { if (a < 0.5) return; a = 1; } f(sx, sy, c, a); };
  p._solid = 1;
}

export const meta = {
  name: "Kal'tsit heal unleashed",
  desc: "A clinical heal at the target's feet: thin lime stitches of light rise unevenly through the body and a medical cross flashes at the chest while small crosses drift up; Structural Reinforcement also closes bone-white plates around the target.",
  tags: ["holy", "heal", "buff", "lime", "one-shot"],
  size: [96, 120],
  origin: [48, 100],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#0d1708", "#1f3510", "#365c1a", "#548a22", "#7fb92e", "#b5e25a", "#e6f9a8", "#ffffff"],
    bone: "#f3efd8",
    move: "heal",
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 3,
  },
};

function cross(p, x, y, m, c, a = 1) {
  p.rect(x - m, y, m * 2 + 1, 1, c, a);
  p.rect(x, y - m, 1, m * 2 + 1, c, a);
}

export function create(o) {
  const G = fit(o.palette, 8), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), mv = o.move;
  const core = o.layer !== "deco", deco = o.layer !== "core", DL = (+o.quick > 0 ? 0.5 : 1) * [0.6, 0.8, 1][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [G[7], G[6], G[5], G[4]] });
  const BODY = 44;   // 受治疗者身高（1x 像素，脚底 → 胸口约 0.6）
  // 竖光：不等距的横向位置、不等高，从脚下往上「缝」过身体
  const ns = [2, 3, 4][el] + (mv === "s1" ? 1 : 0), stitches = [];
  const xs = [];
  while (xs.length < ns) { const v = Math.round(Rg.range(-9, 9)); if (xs.every((q) => Math.abs(q - v) >= 3)) xs.push(v); }   // 不等距、最少隔 3 格
  for (const v of xs) stitches.push({ x: v, h: BODY * Rg.range(0.5, 0.95), t0: Rg.range(0, 0.07), w: Rg.chance(0.3) ? 2 : 1 });
  const CHY = -BODY * 0.58, CM = [2, 2, 3][el];   // 胸口十字
  // 结构加固：外壳片（骨白、不等大的四边形）从外往里合拢到身周，0.25 s 合上、闪一下、留到结束淡出
  const plates = [];
  if (mv === "s1") {
    let a = Rg.range(0, TAU);
    for (let i = 0; i < 6; i++) {
      a += TAU / 6 * Rg.range(0.7, 1.3);
      plates.push({ a, r: Rg.range(11, 14), s: Rg.range(3.2, 4.6), t0: Rg.range(0.02, 0.1), rot: Rg.range(-0.5, 0.5) });
    }
  }
  // 十字小标（E1 起）/ 星点（装饰）：往上飘、不等距
  const crs = [];
  if (deco) {
    const nc = [0, 3, 4][el] + (mv === "regen" ? 2 : 0);
    for (let i = 0; i < nc; i++) crs.push({ x: Rg.range(-12, 12), y: -Rg.range(8, BODY * 0.8), vy: -Rg.range(16, 34), t0: Rg.range(0.06, 0.2), life: Rg.range(0.35, 0.6) * DL + 0.1, m: Rg.chance(0.35) ? 2 : 1 });
    for (let i = 0; i < [4, 7, 10][el]; i++) ps.spawn(P.MOTE, Rg.range(-12, 12), -Rg.range(0, BODY * 0.7), Rg.range(-4, 4), -Rg.range(12, 30), Rg.range(0.35, 0.7) * DL, G[Rg.int(5, 7)], 1, Rg.range(0.03, 0.2));
  }
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {},
    draw(p) {
      solid(p);
      if (core) for (const s of stitches) {   // 竖光：头部往上走、尾部跟着收，0.3 s 内完成
        const u = t - s.t0;
        if (u < 0 || u > 0.34) continue;
        const head = s.h * ease.outCubic(clamp(u / 0.16)), tail = s.h * smooth(0.12, 0.34, u);
        if (head - tail < 1) continue;
        for (let y = tail; y < head; y++) {
          const q = (head - y) / Math.max(1, head - tail);   // 0 = 顶端
          const c = u < 0.05 ? G[7] : el >= 2 && q < 0.2 ? hex(o.bone) : G[clamp(Math.round(7 - q * 3 - u * 4), 3, 7)];
          p.rect(s.x, -y, s.w, 1, c, q > 0.85 ? 0.6 : 1);
        }
      }
      if (deco) for (const s of stitches) {
        const u = t - s.t0, k = 0.16 * (1 - smooth(0.05, 0.35 * DL + 0.1, u));
        if (u > 0 && k > 0.01) p.glowLine(s.x, 0, s.x, -s.h * ease.outCubic(clamp(u / 0.16)), 3, G[5], k);
      }
      if (core && t > 0.1 && t < 0.42) {   // 胸口十字：竖光缝到胸口后亮起
        const u = t - 0.1, c = u < 0.05 ? G[7] : el >= 2 ? hex(o.bone) : G[clamp(Math.round(7 - u * 8), 5, 7)];
        cross(p, 0, CHY, CM + (u < 0.08 ? 1 : 0), c, 1 - smooth(0.2, 0.32, u));
      }
      if (core) for (const pl of plates) {   // 外壳片
        const u = t - pl.t0;
        if (u < 0) continue;
        const k = ease.outBack(clamp(u / 0.22)), r = pl.r + (1 - k) * 14, fade = 1 - smooth(0.55, 0.85, t);
        if (fade <= 0) continue;
        const cx = Math.cos(pl.a) * r * 0.8, cy = CHY * 0.7 + Math.sin(pl.a) * r * 1.15, rr = pl.a + Math.PI / 2 + pl.rot, s = pl.s;
        const cs = Math.cos(rr), sn = Math.sin(rr);
        const pts = [[-s, -s * 0.5], [s, -s * 0.6], [s * 0.8, s * 0.6], [-s * 0.9, s * 0.5]].map(([a, b]) => [cx + a * cs - b * sn, cy + a * sn + b * cs]);
        const flash = u > 0.2 && u < 0.27;
        const dk = t > 0.62 ? G[5] : hex(o.bone);   // 淡出 = 先压暗一档再消失
        p.poly(pts, flash ? G[7] : u < 0.05 ? G[6] : dk, fade > 0.35 ? 1 : 0);
        if (fade > 0.35) p.line(pts[0][0], pts[0][1], pts[1][0], pts[1][1], G[t > 0.62 ? 4 : 5], 1);
      }
      if (deco) {
        ps.draw(p, "front");
        for (const c of crs) {
          const u = t - c.t0;
          if (u < 0 || u > c.life) continue;
          cross(p, c.x, c.y + c.vy * u, c.m, u < 0.05 ? G[7] : G[clamp(Math.round(7 - u * 5), 5, 7)], 1 - u / c.life);
        }
      }
    },
  };
}
