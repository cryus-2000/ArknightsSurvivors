// 乌尔比安「放开版」锁链与锚的水尾（claude/pixelfx-ul-ulpianus，开关 fx/px_unleashed）。原点 = 锚 / 链节中心，+x = 锚飞行方向（链节沿 +x 铺）。
// 原作参照（ulpia.ab skill_01_trail_01，只作参照）：锚身后拖一条带纤维纹的深蓝水流 + 小水泡 + 一点黄白星光；锁链是钢灰粗链。
// move：
//   chain  链节一段（两节：一节正面椭圆环、一节侧面扁环），frame 0 = 平常 / 1 = 绷直时高光走一格；游戏里沿锁链逐段铺（keep 等宽帧）
//   trail  锚飞行水尾（循环）：锚身后 2–3 股起伏的水带（noise，不是正弦），近锚处白、往后变深变碎，散出水泡
//   zip    S3 冲锋水尾（循环）：本体身后贴地的一片水体，比 trail 宽、两侧分水
import { Rng, fit, clamp, smooth, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Ulpianus chain and anchor wake unleashed",
  desc: "Steel chain links that glint when taut, and an uneven deep-sea water wake streaming behind a thrown anchor or a charging hunter.",
  tags: ["projectile", "chain", "trail", "water", "loop"],
  size: [120, 48],
  origin: [96, 24],
  duration: 0.5,
  loop: true,
  fps: 12,
  bg: "dark",
  options: {
    palette: OP.ulpianus,   // 色阶只认 house.js（§11.1 #12）
    steel: OP.ulpianus_dust,   // 色阶只认 house.js（§11.1 #12）
    move: "trail",
    elite: 2,
    layer: "all",
    seed: 5,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), S = fit(o.steel, 6), Rg = new Rng(o.seed), mv = o.move || "trail";
  const core = o.layer !== "deco", deco = o.layer !== "core", el = clamp(Math.round(+o.elite), 0, 2);
  let t = 0, fi = 0;
  const N = mv === "chain" ? 2 : 6;
  const bubbles = [];
  for (let i = 0; i < 9; i++) bubbles.push({ x: -Rg.range(8, 70), y: Rg.range(-7, 7), ph: Rg.range(0, 1), s: Rg.chance(0.3) ? 2 : 1 });

  function link(p, cx, face, glint) {   // 一节链环：正面 = 5×4 空心椭圆环，侧面 = 5×2 扁条；1 格暗描边
    if (face) {
      for (let x = -3; x <= 3; x++) for (let y = -2; y <= 2; y++) {
        const r = (x * x) / 9 + (y * y) / 4.4;
        if (r > 1.05) continue;
        const hole = (x * x) / 2.2 + (y * y) / 1.1 < 1;
        if (hole) continue;
        const rim = r > 0.62;
        p.px(cx + x, y, rim ? S[1] : (y < 0 ? (glint && x === -1 ? S[5] : S[4]) : S[3]));
      }
    } else {
      for (let x = -3; x <= 3; x++) for (let y = -1; y <= 1; y++) {
        if (Math.abs(x) === 3 && y !== 0) continue;
        p.px(cx + x, y, y === -1 ? (glint && x === 1 ? S[5] : S[3]) : y === 1 ? S[1] : S[2]);
      }
    }
  }

  return {
    update(dt) { t += dt; fi = Math.floor(t * 12) % N; },
    draw(p) {
      if (mv === "chain") {
        if (!core) return;
        link(p, -3, true, fi === 1);
        link(p, 3, false, fi === 1);
        return;
      }
      const zip = mv === "zip", L = zip ? 88 : 72, Wd = zip ? 9 : 5.5, ph = fi / N;
      // 水带：2–3 股，沿 -x 往后拖；每股的横向起伏用 noise（随帧平移，循环处接得上：noise 输入按帧周期回绕）
      const strands = zip ? 3 : 2 + (el >= 2 ? 1 : 0);
      if (core) for (let s = 0; s < strands; s++) {
        const off = (s - (strands - 1) / 2) * Wd * 0.8;
        for (let d = 2; d < L; d += 0.6) {
          const v = d / L, u = d * 0.09 + ph * 6;
          const wob = noise(u, o.seed + s * 17) * 2.4 * v + noise(u * 2.3, o.seed + s * 17 + 3) * 1.1 * v;
          const y = off * (0.35 + 1.1 * v) + wob, thick = (zip ? 1.0 : 0.5) * (1 - v * 0.5);   // 细水带：越往后越散开、越细
          if (v > 0.5 && noise(d * 0.4 + ph * 9, o.seed + s * 7 + 11) < -0.3) continue;   // 后段碎开
          const a = 1 - smooth(0.45, 1, v);
          for (let q = -thick; q <= thick; q += 0.6) {
            const c = d < 5 && Math.abs(q) < 0.4 && s === Math.floor(strands / 2) ? C[7] : C[clamp(Math.round(6 - v * 4 - Math.abs(q) / Math.max(0.6, thick)), 2, 6)];
            if (a > 0.95) p.px(-d, y + q, c); else p.blend(-d, y + q, c, a);
          }
        }
      }
      if (deco) {
        for (const b of bubbles) {   // 水泡：往后漂、略往上浮，走一圈回到锚边
          const k = (b.ph + ph) % 1, x = b.x * (zip ? 1.2 : 1) - k * 18, y = b.y * (zip ? 1.4 : 1) - k * 3;
          if (b.s === 2) { p.px(x, y, C[6]); p.px(x + 1, y, C[5]); p.px(x, y - 1, C[5]); }
          else p.px(x, y, C[5 + (k < 0.4 ? 1 : 0)]);
        }
        p.glowLine(-4, 0, -L * 0.55, 0, zip ? 9 : 6, C[4], 0.22);
        if (zip) for (const sgn of [-1, 1]) for (let d = 4; d < 34; d += 0.7) {   // 冲锋两侧分水：前沿往外翻的两道浪
          const v = d / 34, y = sgn * (Wd * 1.1 + v * 10 + noise(d * 0.3 + ph * 7, o.seed + 41 + sgn) * 1.6);
          if (noise(d * 0.5 + ph * 5, o.seed + 47 + sgn) < -0.3) continue;
          p.blend(-d + 6, y, C[clamp(Math.round(6 - v * 3), 3, 6)], 0.8 * (1 - v));
        }
      }
    },
  };
}
