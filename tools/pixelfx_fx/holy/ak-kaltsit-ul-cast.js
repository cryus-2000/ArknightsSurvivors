// 凯尔希技能起手（pixelfx 放开版，docs/242 §12.1 起手信号；开关 fx/px_unleashed）：原点 = 凯尔希脚底，侧视；注册表 cast 在 character.spend_sp 里播。
// 原作参照（build/ark_ref/kaltsit + mon3tr）：S1 kalts_skill_01_buff 身周护盾骨架（原作蓝色，本作改骨白 + 黄绿，避开敌弹青）；
//   S2 monstr_skill_02_start（黄绿流光往里收）；S3 kalts_skill_03_buff + monstr_skill_03_begin_01（红芯、红刺往里聚，再爆开；原作的红烟不要）。
// 11-04 用户：往外发散的光环一律不要 → 三个起手都是「往里收」：碎片 / 光线从四周聚到举手处，聚满后闪一下。
// move：s1（结构加固：骨白外壳片聚到手边合成一枚十字）/ s2（战术协同：几道黄绿折线从地面往上收成「指令」标）/ s3（熔毁：红晶刺从四周聚到手边，红芯爆亮、红火星往下落）
//   ult（终结技蓄力：红晶刺分几拨从大范围收向 Mon3tr 身上，tin 秒内收完，不闪）/ m3（终结技 8 秒后 Mon3tr 重构：骨白外壳片从四周聚回它身上，结尾黄绿十字一闪）
// 精英档只影响装饰量（起手是信号，主形不分档）。
import { Particles, Rng, fit, clamp, smooth, ease, noise, hex, TAU, P } from "../../core/index.js";
import { OP } from "../house.js";   // 色阶唯一来源（§11.1 #12）：OP.kaltsit 黄绿、OP.kaltsit_melt 熔毁红

// 实色：painter.put 在 a < 1 时按 Bayer 点阵抖动（棋盘格脏点）；本作 a ≥ 0.5 画实、< 0.5 不画，淡出靠色阶
function solid(p) {
  if (p._solid) return;
  const f = p.put.bind(p);
  p.put = (sx, sy, c, a = 1) => { if (a < 0.999) { if (a < 0.5) return; a = 1; } f(sx, sy, c, a); };
  p._solid = 1;
}

export const meta = {
  name: "Kal'tsit command cast unleashed",
  desc: "Kal'tsit issues a command: fragments or lines of light gather from all around into her raised hand and flash — bone plates for Structural Reinforcement, lime chevrons for Tactical Coordination, red crystal spikes for Meltdown.",
  tags: ["holy", "cast", "buff", "charge", "one-shot"],
  size: [120, 120],
  origin: [60, 104],
  duration: 0.8,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: OP.kaltsit,
    red: OP.kaltsit_melt,
    bone: "#f3efd8",
    move: "s1",
    elite: 2,
    quick: 0,
    layer: "all",
    tin: 0.26,   // 聚拢用时（ult 传蓄力时长）
    seed: 2,
  },
};


export function create(o) {
  const mv = o.move, ult = mv === "ult", m3 = mv === "m3", s3 = mv === "s3" || ult, T_IN = ult ? +o.tin : m3 ? 0.4 : 0.26, C = fit(s3 ? o.red : o.palette, 8), G = fit(o.palette, 8), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2);
  const core = o.layer !== "deco", deco = o.layer !== "core", DL = (+o.quick > 0 ? 0.5 : 1) * [0.7, 0.85, 1][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const HX = ult || m3 ? 0 : 6, HY = ult ? -38 : m3 ? -30 : -40;   // 举手处（ult / m3 = Mon3tr 身体中段）
  const parts = [];   // 聚拢的碎片 / 刺 / 折线：起点在四周（不等角、不等距），沿弯路收向手
  const n = ult ? 11 : m3 ? 10 : s3 ? 7 : mv === "s2" ? 5 : 6, SP = ult ? 2.2 : m3 ? 1.5 : 1;
  let a = Rg.range(0, TAU);
  for (let i = 0; i < n; i++) {
    a += TAU / n * Rg.range(0.6, 1.4);
    const d = Rg.range(26, 40) * SP;
    parts.push({ x0: HX + Math.cos(a) * d, y0: HY + Math.sin(a) * d * 0.8 + (mv === "s2" ? 18 : 0), a, t0: ult ? Rg.range(0, T_IN * 0.7) : Rg.range(0, 0.07), bend: ult ? (Rg.chance(0.5) ? 1 : -1) * Rg.range(0.6, 1.2) : Rg.range(-0.5, 0.5), s: Rg.range(3, 5), rot: Rg.range(0, TAU) });
  }
  if (deco) {
    const nd = s3 ? 14 : 8;
    for (let i = 0; i < nd; i++) {   // 聚满后的火星：熔毁往下落（重），其余往上飘
      const aa = Rg.range(-Math.PI, 0) + (s3 ? Math.PI : 0), sp = Rg.range(30, s3 ? 110 : 60);
      ps.spawn(s3 ? P.SPARK : P.MOTE, HX, HY, Math.cos(aa) * sp * 0.6, Math.sin(aa) * sp, Rg.range(0.25, 0.5) * DL, s3 ? 0 : G[Rg.int(5, 7)], 1, T_IN + Rg.range(0, 0.05));
    }
  }
  // 0 = 起点、1 = 手：二次曲线收拢（终结技蓄力 bend 更大：直线收会成放射纹，§9.3）
  const pathAt = (q, u) => {
    const k = ease.inCubic(clamp(u)), mx = (q.x0 + HX) / 2 + (q.y0 - HY) * q.bend * 0.5, my = (q.y0 + HY) / 2 - (q.x0 - HX) * q.bend * 0.5;
    const x = (1 - k) * (1 - k) * q.x0 + 2 * (1 - k) * k * mx + k * k * HX, y = (1 - k) * (1 - k) * q.y0 + 2 * (1 - k) * k * my + k * k * HY;
    return [x, y];
  };
  let t = 0;
  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) {},
    draw(p) {
      solid(p);
      if (core) for (const q of parts) {
        const u = (t - q.t0) / Math.min(ult ? 0.3 : 9, T_IN - q.t0);
        if (u < 0 || u >= 1) continue;
        const [x, y] = pathAt(q, u), [x2, y2] = pathAt(q, Math.max(0, u - 0.14)), col = C[clamp(Math.round(4 + u * 3), 4, 7)];
        if (mv === "s2") {   // 折线：头 + 一段拖尾
          p.line(x2, y2, x, y, col, 1);
          p.line(x, y, x - Math.cos(q.a + 0.6) * 3, y - Math.sin(q.a + 0.6) * 3, C[7], 1);
        } else if (s3) {   // 红晶刺：沿运动方向的细长菱形
          const dx = x - x2, dy = y - y2, L = Math.hypot(dx, dy) || 1, ux = dx / L, uy = dy / L, w = 1.6;
          p.poly([[x + ux * 5, y + uy * 5], [x - uy * w, y + ux * w], [x - ux * 6, y - uy * 6], [x + uy * w, y - ux * w]], col, 1);
        } else {   // 骨白外壳片：小四边形、边上一格黄绿
          const s = q.s * (1 - u * 0.5), r = q.rot + u * 3, cs = Math.cos(r), sn = Math.sin(r);
          const pts = [[-s, -s * 0.5], [s, -s * 0.6], [s * 0.8, s * 0.6], [-s * 0.9, s * 0.5]].map(([aa, bb]) => [x + aa * cs - bb * sn, y + aa * sn + bb * cs]);
          p.poly(pts, u > 0.8 ? C[7] : hex(o.bone), 1);
          p.line(pts[0][0], pts[0][1], pts[1][0], pts[1][1], G[5], 1);
        }
      }
      if (deco) for (const q of parts) {
        const u = (t - q.t0) / (T_IN - q.t0);
        if (!ult && u > 0.2 && u < 1) { const [x, y] = pathAt(q, u), [x2, y2] = pathAt(q, u - 0.2); p.glowLine(x2, y2, x, y, 3, C[5], 0.18); }
      }
      // 聚满：手边一枚标记闪亮（S1 十字 / S2 指令折角 / S3 红芯十字星），0.15 s 后压暗消失
      const v = t - T_IN;
      if (core && !ult && v >= 0 && v < 0.22) {
        const c = v < 0.05 ? C[7] : C[clamp(Math.round(7 - v * 14), 4, 7)], m = v < 0.06 ? 6 : 4;
        if (s3) {
          p.poly([[HX, HY - m * 2.2], [HX + 1.5, HY], [HX, HY + m * 2.2], [HX - 1.5, HY]], c, 1);
          p.poly([[HX - m * 1.6, HY], [HX, HY + 1.2], [HX + m * 1.6, HY], [HX, HY - 1.2]], c, 1);
        } else if (mv === "s2") {
          p.line(HX - m, HY + m, HX, HY, c, 1); p.line(HX, HY, HX + m, HY + m, c, 1);
          p.line(HX - m, HY + m - 3, HX, HY - 3, c, 1); p.line(HX, HY - 3, HX + m, HY + m - 3, c, 1);
        } else {
          p.rect(HX - m, HY, m * 2 + 1, 1, c, 1); p.rect(HX, HY - m, 1, m * 2 + 1, c, 1);
        }
      }
      if (deco) {
        if (ult && t < T_IN) p.glowLine(HX, HY - 3, HX, HY + 3, 4 + 10 * t / T_IN, C[5], 0.12 + 0.25 * t / T_IN);   // 蓄力时身上的红光越收越亮
        if (!ult && v >= 0 && v < 0.2) p.glowLine(HX, HY - 4, HX, HY + 4, 7, C[5], 0.35 * (1 - v / 0.2));
        ps.draw(p, "front");
      }
    },
  };
}
