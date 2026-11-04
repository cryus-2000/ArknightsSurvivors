// 流明 S3「灯火不灭」结束光爆（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 光圈中心。
// 判定：半径 r = s3_r（1x = s3_r / 2），范围伤害 + 击退 + 眩晕。照原作 lumen_skill_03_hit_02（大四芒爆光 star_06 / 十字火星 shizi / 光柱 trail_15）。
// 灯塔最后一闪：灯高处一颗大四芒爆光（横芒最长）+ 中心一道竖直白光柱冲上去再收；判定半径上 5 段弧同时亮一下再熄（原地闪，不外扩）；
// 中心水冠溅起，成组的水珠往外甩到圈边附近；3 颗十字星浮起。不画外扩光环（用户 11-04）、不画实心圆。只有 E2。
// 分层：core = 爆光、光柱、边弧、水冠、十字星；deco = 中心淡光、水珠。只用钢蓝 7 阶。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, jitterAngles } from "../house.js";

// 用户 11-04 否「绕身 / 脚下的匀称圆环」：不沿同一圆周均匀摆弧——身前 nF 段长短、半径都不等（最远一段贴判定半径），身后 nB 段短小的；
// 正右 = 朝向，朝左时游戏里翻转
const dirArcs = (Rg, R, nF, nB) => {
  const out = [];
  for (let i = 0; i < nF; i++) out.push({ c: Rg.range(-0.25, 0.25) + (i - (nF - 1) / 2) * Rg.range(0.5, 0.7), half: Rg.range(0.22, 0.5), r: R * (i === 0 ? 1 : Rg.range(0.62, 0.86)), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) });
  for (let i = 0; i < nB; i++) out.push({ c: Math.PI + Rg.range(-0.8, 0.8), half: Rg.range(0.12, 0.24), r: R * Rg.range(0.35, 0.55), s: Rg.next() * 9, g: Rg.range(-0.5, 0.5) });
  return out;
};

export const meta = {
  name: "Lumen lantern burst unleashed",
  desc: "The lighthouse's last flash: a huge four-pointed flare and a white shaft at the centre while broken arcs flash once on the zone's edge.",
  tags: ["water", "light", "impact", "one-shot"],
  size: [240, 210],
  origin: [120, 140],
  duration: 0.85,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: OP.lumen, layer: "all", r: 110, seed: 8 },
};

const SY = 0.5;
// §0（组长 B 11-04）：弧是有厚度的水幕 / 光片——4 美术像素厚，外缘亮、往里一层层变暗
const SHEET = [6, 5, 4, 3];


export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), R = o.r, Rg = new Rng(o.seed), LY = -46;
  const segs = dirArcs(Rg, R, 1, 1);   // 每招 1–2 道（组长 B 11-04）
  const crown = jitterAngles(Rg, 9, -2.0, 2.0, 0.4)   // 水冠偏向身前（用户 11-04 否脚下匀称一圈）
    .map((a, i) => ({ a, h: 8 + 12 * noise(i * 1.3, o.seed), r: 8 + 5 * noise(i * 2.1, o.seed + 2) }));
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  // 往外甩到圈边的水珠去掉（用户 11-04，§14.7）
  const glints = [0, 1, 2].map((i) => ({ x: Rg.range(-30, 30), y: Rg.range(-8, 8), d: 0.15 + i * 0.1, v: Rg.range(25, 40) }));
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); ps.list.forEach((q) => (q.vy += 200 * dt)); },
    drawBack(p) {
      // 十字中心不加软圆光晕（组长 B 11-04：只留硬十字）
    },
    draw(p) {
      if (core) {
        // 大四芒爆光：0.45 s 收，首帧白、第 2 帧降一档
        const u = clamp(t / 0.45);
        if (u < 1) {
          const k = 1 - ease.inQuad(u), rays = [[1, 0, 40], [-1, 0, 40], [0, -1, 30], [0, 1, 20], [0.7, 0.7, 20], [-0.7, 0.7, 20], [0.7, -0.7, 22], [-0.7, -0.7, 22]];   // 十字双层（组长 B 11-04）：正十字 + 斜十字第二层   // 组长 B 11-04：短而粗（≤ 0.4R）
          for (const [dx, dy, L] of rays) {
            const len = L * k;
            for (let s = 0; s <= len; s += 0.5) {
              const v = s / Math.max(len, 1), w = dy === 0 && v < 0.4 ? 1 : 0;
              const c = t < 0.05 ? (v < 0.7 ? C[6] : C[5]) : t < 0.1 ? (v < 0.15 ? C[6] : C[5]) : v < 0.1 ? C[6] : v < 0.6 ? C[5] : C[4];
              const th = Math.max(0, 3.2 * (1 - v)) * (Math.abs(dx) + Math.abs(dy) > 1.2 ? 0.75 : 1);   // 芒根部 3 像素粗、往尖收
              for (let q = -th; q <= th; q += 0.5) p.px(dx * s - dy * q, LY + dy * s + dx * q, Math.abs(q) < th * 0.4 ? c : C[Math.max(3, (c === C[6] ? 5 : 4))]);
            }
          }
        }
        if (t < 0.3) for (let y = -3; y <= 3; y++) for (let x = -3; x <= 3; x++) if (Math.abs(x) + Math.abs(y) <= 3) p.px(x, LY + y, Math.abs(x) + Math.abs(y) <= 1 || t < 0.06 ? C[6] : C[5]);   // 星芒亮芯
        // 竖直白光柱：冲上去 0.08 s，0.35 s 往中线收
        if (t < 0.35) {
          const up = ease.outCubic(clamp(t / 0.08)), W = 3 * (1 - smooth(0.08, 0.35, t)), H = 60 * up;
          for (let y = 0; y <= H; y += 1) for (let x = -W; x <= W; x += 0.5) p.blend(x, -y, Math.abs(x) < W * 0.45 && t < 0.06 ? C[6] : C[5], clamp(1.2 - y / H) * 0.95);
        }
        // 边弧：判定半径上原地闪一下（0.04 亮 → 0.4 熄），不外扩
        const ea = t < 0.04 ? t / 0.04 : 1 - smooth(0.12, 0.45, t);
        if (ea > 0)
          for (const sg of segs)
            for (let an = sg.c - sg.half; an <= sg.c + sg.half; an += 0.4 / sg.r) {
              const e = 1 - Math.abs(an - sg.c) / sg.half, n = noise(an * 2.8 + sg.s, o.seed + 1);
              if (ea * smooth(0, 0.3, e) > 0.35) for (let k = 0; k < 4; k++) p.px(Math.cos(an) * (sg.r - k * 1.6), Math.sin(an) * (sg.r - k * 1.6) * SY, t < 0.05 && k < 2 ? C[6] : C[Math.max(2, SHEET[k] - (n > 0.6 ? 0 : 1))]);   // §0：4 像素厚的光片
            }
        // 水冠
        const cu = (t - 0.03) / 0.4;
        if (cu > 0 && cu < 1)
          for (const c of crown) {
            const bx = Math.cos(c.a) * c.r * (0.6 + 0.4 * cu), by = Math.sin(c.a) * c.r * SY, hh = c.h * Math.sin(Math.min(1, cu * 1.6) * Math.PI * 0.5) * (1 - cu * cu);
            for (let s = 0; s <= hh; s += 0.5) p.dot(bx + Math.cos(c.a) * s * 0.4, by - s, s > hh * 0.75 && cu < 0.4 ? C[6] : C[5], 1 - cu * 0.5);
          }
        // §0 不碎：十字星去掉（爆光 + 光柱、边弧、水冠三样）
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
