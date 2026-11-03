// 星熊技能起手提示（docs/242 §12.1；px_ul.json cast，技能开启那一刻在脚下播）：原点 = 星熊脚底，俯视 sy 0.55，0.5 s。
// kind：1 = S1 战意（实心钢色盾印从上压下、白热后冷却）；2 = S2 荆棘（照原作 hsguma_skill_02_buff：脚下长出一圈转 45° 的暗红荆棘菱环、倒刺朝外，
//       E1 只长两条边、E2 四边合拢带断口；外加一圈高矮不一的钢刺扎出又缩回）；
//       3 = S3 力之锯（脚下一圈青绿鬼火窜起，实心盾形印由白转翠绿）。精英档：E1 起印边带暗红细线（反击架势），E2 起印 / 刺尖转翠绿（般若）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Hoshiguma skill cast cue",
  desc: "Skill cast cue at her feet: a steel shield sigil with gathering glints (S1), a ring of uneven steel thorns (S2), or teal ghost flames igniting round a shield sigil (S3).",
  tags: ["holy", "cast", "one-shot"],
  size: [112, 96],
  origin: [56, 66],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#121418", "#262a31", "#434a55", "#6d7684", "#a3acb8", "#d9dee6", "#ffffff"],   // 钢色（PRTS 黑钢盾），不用金（§12.6）
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    kind: 1,
    elite: 2,
    layer: "all",
    seed: 5,
  },
};

const SY = 0.55, V = [[-15, -11], [15, -11], [1, 14]];

export function create(o) {
  const C = fit(o.palette, 7), J = fit(o.jade, 5), E = fit(o.ember, 5), Rg = new Rng(o.seed);
  const kind = +o.kind, el = +o.elite, core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[5], C[4], C[3], C[2]] });
  const thorns = jitterAngles(Rg, Rg.int(8, 11), 0, Math.PI * 2, 0.45).map((a) => ({ a, r: Rg.range(22, 34), h: Rg.range(7, 16), w: Rg.range(1.2, 2.4), d: Rg.range(0, 0.08), lean: Rg.range(0.15, 0.5) }));
  const flames = jitterAngles(Rg, Rg.int(7, 10), 0, Math.PI * 2, 0.45).map((a) => ({ a, r: Rg.range(14, 30), h: Rg.range(8, 20), d: Rg.range(0, 0.12), ph: Rg.range(0, 6) }));
  const DR = 34, DV = [[DR, 0], [0, DR * SY], [-DR, 0], [0, -DR * SY]], e1 = Rg.int(0, 3);
  const vines = kind === 2 ? [0, 1, 2, 3].filter((k) => el >= 2 || k === e1 || k === (e1 + 1) % 4).map((k) => {
    const [x0, y0] = DV[k], [x1, y1] = DV[(k + 1) % 4], L = Math.hypot(x1 - x0, y1 - y0);
    const barbs = []; for (let v = Rg.range(0.05, 0.15); v < 0.95; v += Rg.range(0.09, 0.2)) barbs.push([v, Rg.chance(0.75) ? 1 : -1, Rg.range(2, 4.5)]);
    return { x0, y0, x1, y1, nx: (y1 - y0) / L, ny: -(x1 - x0) / L, bend: Rg.range(-0.06, 0.1) * L, d: k * 0.04 + Rg.range(0, 0.03), barbs, gap: Rg.range(0.2, 0.8), gw: Rg.range(0.05, 0.1) };
  }) : [];
  let t = 0, fired = false;
  const sigil = (p, k, y0) => {   // 般若倒三角盾印（11-04 §0：实心主形）：落下压实 → 白热 → 冷成钢色（E2 / S3 转翠绿），E1 起印沿暗红
    const s = (0.75 + 0.25 * ease.outBack(clamp(t / 0.1))) * [1, 1.25, 1.5][el], dy = -6 * (1 - clamp(t / 0.08));   // §8：E1 ×1.25、E2 ×1.5   // 盾印从上方压下、略放大到位
    const pts = V.map(([x, y]) => [x * s, y * s * SY + y0 + dy]);
    const hot = t < 0.06 || (el >= 1 && t >= 0.15 && t < 0.2), jade = kind === 3 || el >= 2;   // E1 起多一拍：盾印再压一下二次白热
    if (k < 0.2) return;   // 不用半透明淡出（低透明度会抖成网点）：按 k 逐阶压暗、最后一帧收掉
    const dk = k > 0.7 ? 0 : k > 0.45 ? 1 : 2;
    const fill = hot ? C[5] : jade ? J[clamp(2 - dk, 1, 2)] : C[clamp(3 - dk, 1, 3)];
    p.poly(pts, fill, 1);
    const edge = hot ? C[6] : el >= 1 ? E[clamp(4 - dk, 2, 4)] : jade ? J[4 - dk] : C[5 - dk];
    for (let i = 0; i < 3; i++) p.line(pts[i][0], pts[i][1], pts[(i + 1) % 3][0], pts[(i + 1) % 3][1], edge, 1);
    if (!hot && dk < 2 && el < 2) p.line(pts[0][0] * 0.5, pts[0][1] + 2, pts[1][0] * 0.5, pts[1][1] + 2, jade ? J[4 - dk] : C[5 - dk], 1);   // 盾面一道受光横棱
    if (el >= 2 && !hot) {   // E2 质变（§8）：盾印里再嵌一枚实心小盾（双层般若盾），亮青绿
      const cx = (pts[0][0] + pts[1][0] + pts[2][0]) / 3, cy = (pts[0][1] + pts[1][1] + pts[2][1]) / 3, inn = pts.map(([x, y]) => [cx + (x - cx) * 0.45, cy + (y - cy) * 0.45]);
      p.poly(inn, J[4 - dk], 1);
    }
  };
  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        // （起手火星 11-04 删：§0 同屏元素 ≤ 3）
      }
      ps.update(dt);
    },
    draw(p) {
      const fade = 1 - smooth(0.3, 0.6, t);
      if (kind === 2 && core) for (const s of thorns) {   // 一圈钢刺：扎出 → 停 → 缩回
        const u = t + 0.03 - s.d, up = ease.outBack(clamp(u / 0.07)) * (1 - smooth(0.2, 0.4, u)), H = s.h * up;
        if (u < 0 || H < 1) continue;
        const bx = Math.cos(s.a) * s.r, by = Math.sin(s.a) * s.r * SY;
        for (let d = 0; d <= H; d += 0.5) {
          const v = d / H, hw = s.w * (1 - v);
          for (let e = -hw; e <= hw; e += 0.6) {
            const c = el >= 2 && v > 0.65 ? J[clamp(Math.round(2 + v * 2.5), 1, 4)] : C[clamp(Math.round(2 + v * 3 + (u < 0.05 && v > 0.7 ? 1 : 0)), 1, 5)];
            p.blend(bx + Math.cos(s.a) * d * s.lean + e, by - d, c, 1);
          }
        }
      }
      if (kind === 2 && core) for (const vn of vines) {   // 暗红荆棘菱环：沿边长出 → 停 → 淡出（比钢刺留得久，0.8 s）
        const u = t - vn.d, g = clamp(u / 0.12), k = 1 - smooth(0.45, 0.8, u);
        if (u < 0 || k <= 0) continue;
        const Pt = (v) => { const w = 1 - v, b = 4 * v * w * vn.bend; return [vn.x0 + (vn.x1 - vn.x0) * v + vn.nx * b, vn.y0 + (vn.y1 - vn.y0) * v + vn.ny * b * SY]; };
        const hot = u < 0.06 ? 4 : 3;
        for (let v = 0; v <= g; v += 0.01) {
          if (Math.abs(v - vn.gap) < vn.gw) continue;
          const [x, y] = Pt(v), wob = 0.7 * noise(v * 9 + vn.gap * 7, o.seed + 13);
          // 组长 11-04：3 像素暗红实线（离危险色 #ff2667 远：只用 E[1]–E[2] 深红，亮头一帧 E[3]），不再 1–2 像素细线
          p.blend(x, y + wob - 1, E[clamp(hot - 1, 1, 3)], k);
          p.blend(x, y + wob, E[clamp(hot - 1, 1, 3)], k);
          p.blend(x, y + wob + 1, E[1], k);
        }
        for (const [bv, sd, bl] of vn.barbs) {
          if (bv > g || Math.abs(bv - vn.gap) < vn.gw) continue;
          const [x0, y0] = Pt(bv), [x1, y1] = Pt(Math.min(1, bv + 0.02)), tx = x1 - x0, ty = y1 - y0, tl = Math.hypot(tx, ty) || 1;
          { const bx = x0 + (ty / tl * sd + tx / tl * 0.5) * bl, by = y0 + (-tx / tl * sd + ty / tl * 0.5) * bl * 0.8 - 0.5; p.line(x0, y0, bx, by, el >= 2 && bv > 0.6 ? J[3] : E[2], k); p.line(x0 + 1, y0, bx + 0.5, by, E[1], k); }   // 倒刺两像素
        }
      }
      if (kind === 2 && deco && el >= 2) for (const vn of vines) { const u = t - vn.d; if (u > 0) p.glow((vn.x0 + vn.x1) / 2, (vn.y0 + vn.y1) / 2, 7, E[3], 0.14 * (1 - smooth(0.3, 0.7, u))); }   // 光沿藤走
      if (kind === 3 && deco) for (const f of flames) {   // 脚下一圈青绿鬼火窜起
        const u = t - f.d, life = clamp(u / 0.06) * (1 - smooth(0.15, 0.45, u)), H = f.h * life;
        if (u < 0 || H < 1) continue;
        const bx = Math.cos(f.a) * f.r, by = Math.sin(f.a) * f.r * SY;
        for (let d = 0; d < H; d += 0.5) {
          const v = d / H, sway = 2 * noise(f.ph + d * 0.2 + u * 9, o.seed) * v;
          for (let e = -(1.4 - 1.1 * v); e <= 1.4 - 1.1 * v; e += 0.7) p.blend(bx + sway + e, by - d, J[clamp(Math.round(4 - v * 2.6 - Math.abs(e) * 0.6), 1, 4)], (0.85 - v * 0.5) * life);
        }
      }
      if (core && fade > 0 && (kind === 1 || kind === 3)) sigil(p, fade, kind === 1 ? -10 : 0);
      if (deco) ps.draw(p);   // 不画脚下大光盘（游戏里读成圆形气泡，§12.3）
    },
  };
}
