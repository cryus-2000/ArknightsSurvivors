// 星熊 S1「战意」放开版：举盾重砸（圆形判定 s1_r，圆心 = 星熊），俯视地面透视 sy 0.55，原点 = 星熊脚下。
// 半径 = fit（1x，= s1_r / 2），运行时按判定半径缩放。
// 11-04 §0 重做：一招一个实心主形 = 砸坑（不规整的实心坑面 + 4–6 道两像素粗的主缝伸到判定边，不分叉），
// 节奏 蓄势（盾沿压低的一道横亮条）→ 第 1 帧整坑白热 → 冷成钢灰 / 档位色；同屏只 2 种元素：坑 + 主缝、几块会落会弹的石块。
// 不画圆心光盘、不画外扩环、不往外甩（用户 11-04）。
// 精英档（docs/242 §10，docs/91 §4）：E0 坑 + 石块，余韵 0.35 s；E1 坑沿冷成暗红余热（精一「反击架势」），余韵 0.5 s；
//   E2 主缝冷成青绿并透光、坑底透出青绿缝根（精二「般若」），余韵 0.7 s。
import { Bits, B, Rng, fit, clamp, smooth, noise } from "../../core/index.js";
import { jitterAngles } from "../house.js";

export const meta = {
  name: "Hoshiguma battle-will shield slam unleashed",
  desc: "Shield slam: the shield rim presses down, the ground caves into one white-hot crater with a few thick cracks, stone chunks hop and settle; tiers cool the rim to red heat, then let teal light seep from the cracks.",
  tags: ["impact", "slam", "ground", "one-shot"],
  size: [232, 150],
  origin: [116, 78],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#0b0d10", "#1b1f25", "#323840", "#59626e", "#98a2ae", "#dce2e8", "#ffffff"],   // 钢 / 石（PRTS 黑钢盾提亮）；§12.6 不用金
    ember: ["#2a0a08", "#5e1410", "#9c2418", "#d8452a", "#ff7050"],
    jade: ["#081814", "#18584c", "#258a77", "#58c4ab", "#b4f0e2"],
    radius: 75,
    elite: 2,
    quick: 0,
    layer: "all",
    seed: 4,
  },
};

const SY = 0.55, HIT = 0.05;

export function create(o) {
  const C = fit(o.palette, 7), E = fit(o.ember, 5), J = fit(o.jade, 5), Rg = new Rng(o.seed);
  const R = o.radius, el = +o.elite, LQ = +o.quick > 0 ? 0.5 : 1;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const TAIL = [0.35, 0.5, 0.7][el] * LQ;
  const CR = R * 0.34;   // 坑半径（判定的三分之一，范围靠主缝交代）
  // 坑沿：极坐标不规整半径
  const rim = (a) => CR * (0.82 + 0.22 * noise(Math.cos(a) * 1.3 + 3, Math.sin(a) * 1.3 + o.seed));
  // 主缝：4–6 条，从坑沿出发，2–3 段折线，宽 2 像素，长短不一，不分叉
  const cracks = jitterAngles(Rg, Rg.int(4, 6), 0, Math.PI * 2, 0.35).map((a0) => {
    const pts = [[Math.cos(a0) * rim(a0) * 0.9, Math.sin(a0) * rim(a0) * 0.9 * SY]];
    let a = a0, r = rim(a0) * 0.9;
    const end = R * Rg.range(0.75, 1.0);
    for (let k = 0, n = Rg.int(2, 3); k < n; k++) {
      r += (end - rim(a0)) / n;
      a += Rg.range(-0.22, 0.22);
      pts.push([Math.cos(a) * r, Math.sin(a) * r * SY]);
    }
    return pts;
  });
  const STONE = ["#0b0d10", "#262b32", "#4a525c", "#7c8692", "#b8c0ca"];
  const chunks = [];   // 石块：各自有落地线（俯视：落回起跳的那一行）
  if (deco) for (const a of jitterAngles(Rg, [4, 5, 5][el], 0, Math.PI * 2, 0.4)) {
    const r = CR * Rg.range(0.5, 1.1), x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
    const bits = new Bits({ ground: () => y });
    bits.add({ kind: B.CHUNK, x, y: y - 0.1, vx: Math.cos(a) * Rg.range(4, 12), vy: -Rg.range(90, 150), a: Rg.range(0, 6), va: Rg.range(-9, 9), s: Rg.range(2.6, 3.6), ramp: STONE, bounce: 0.35, life: 0.2 + TAIL * 0.6 + Rg.range(0, 0.1) });
    chunks.push(bits);
  }
  let t = 0;
  return {
    update(dt) {
      t += dt;
      if (t >= HIT) for (const b of chunks) b.update(dt);
    },
    draw(p) {
      const u = t - HIT;
      // —— 蓄势（第 0 帧）：盾下沿压低，一道横向的钢白亮条
      if (u < 0) {
        if (core) for (let x = -10; x <= 10; x += 0.5) p.blend(x, -5, C[5], 0.9 - Math.abs(x) / 14);
        return;
      }
      const ck = 1 - smooth(0.12, 0.12 + TAIL, u);
      // 温度：0 → 1 冷却；坑与主缝同一套颜色（一个主形）
      const heat = (k) => {
        if (u < 0.05) return C[6];
        if (u < 0.1) return C[5];
        if (el >= 2 && k === "crack") return J[clamp(Math.round(4 - u * 3), 2, 4)];
        if (el >= 1 && k === "rim") return E[clamp(Math.round(4 - u * 5), 1, 3)];
        return C[clamp(Math.round(4 - u * 8), 2, 4)];
      };
      if (core && ck > 0) {
        // 主缝：先于坑铺开（0.08 s 长满），两像素宽
        const grow = clamp(u / 0.08) * (1 - smooth(0.12, 0.12 + TAIL * 0.9, u));   // 长满 → 从缝尖往坑里收（不靠半透明淡出，免得读成虚线）
        for (const pts of cracks) for (let i = 0; i + 1 < pts.length; i++) {
          const g = clamp(grow * (pts.length - 1) - i);
          if (g <= 0) continue;
          const [x0, y0] = pts[i], x1 = x0 + (pts[i + 1][0] - x0) * g, y1 = y0 + (pts[i + 1][1] - y0) * g;
          const c = heat("crack");
          p.line(x0, y0, x1, y1, c, 1);
          if (i === 0) p.line(x0, y0 - 1, x1, y1 - 1, c, 1);   // 近坑一段两像素宽（远端一像素）
          p.line(x0, y0 + 1, x1, y1 + 1, C[1], 0.9);   // 缝的暗面
        }
        // 坑：实心不规整椭圆，坑底暗、近沿（下半）受光；第 1 帧整坑白热
        const sink = Math.min(1, u / 0.04);
        for (let y = -CR * SY - 1; y <= CR * SY + 1; y += 0.5) for (let x = -CR - 1; x <= CR + 1; x += 0.5) {
          const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / rim(a);
          if (d > 1) continue;
          let c, al = ck;
          if (u < 0.05) c = d > 0.75 ? C[5] : C[6];
          else if (d > 0.82) c = y > 0 ? heat("rim") : C[2];   // 坑沿：近沿亮、远沿暗
          else { c = C[d < 0.5 ? 0 : 1]; al = ck * (0.75 + 0.25 * sink); }
          p.blend(x, y, c, al);
        }
        // E2：坑底透出一线青绿（缝的根）
        if (el >= 2 && u >= 0.05) for (const pts of cracks) {
          const [x1, y1] = pts[0];
          p.line(x1 * 0.4, y1 * 0.4, x1, y1, J[clamp(Math.round(4 - u * 3), 2, 4)], ck * 0.8);
        }
      }
      if (deco) {
        // 照地：只沿主缝贴一层淡光（不画圆心光盘 §12.3）
        const gk = 0.22 * (1 - smooth(0.02, 0.1 + TAIL * 0.4, u));
        if (gk > 0.01) for (const pts of cracks) p.glowLine(pts[0][0], pts[0][1], pts[1][0], pts[1][1], 4, el >= 2 ? J[3] : C[4], gk);
        for (const b of chunks) b.draw(p);
      }
    },
  };
}
