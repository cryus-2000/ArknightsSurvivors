// 乌尔比安「放开版」锁链横扫类（claude/pixelfx-ul-ulpianus，开关 fx/px_unleashed）：俯视地面，原点 = 圆心（地面），透视 y × SY。
// move：
//   whirl  成长「锁链回旋」（以自身为心，半径 = whirl_r）：锚带着锁链贴地甩一整圈——一道水幕弧沿判定圆转过去，头白、尾巴碎成往外甩的水珠和尘，
//          任一帧只看到一段弧（不是整圈）；锚本体和锁链由原生动作画
//   pull   精一「收链」（以锚击落点为心，外圈 = reach × pull_r）：外圈的地面被往里拖——几道不等距的拖痕从外圈往判定边收拢，尘往里卷
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { jitterAngles, OP } from "../house.js";

export const meta = {
  name: "Ulpianus chain sweep unleashed",
  desc: "A water sheet whipped round on the ground by an anchor chain, or ground dragged inward toward the anchor's mark.",
  tags: ["melee", "sweep", "chain", "water", "topdown", "one-shot"],
  size: [320, 240],
  origin: [160, 130],
  duration: 0.9,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: OP.ulpianus,   // 色阶只认 house.js（§11.1 #12）
    dust: OP.ulpianus_dust,   // 色阶只认 house.js（§11.1 #12）
    radius: 65,
    inner: 45,
    move: "whirl",
    quick: 0,
    spray: 0,          // 1 = 画往外甩的水珠 / 火星 / 碎石（docs/242 §14.7 用户 11-04 取消，缺省 0；尘 / 水雾保留）
    layer: "all",
    seed: 3,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), D = fit(o.dust, 6), Rg = new Rng(o.seed), mv = o.move || "whirl", R = +o.radius, Ri = +o.inner, quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", DL = quick ? 0.55 : 1;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[4] });
  if (!(+o.spray > 0)) { const sp0 = ps.spawn.bind(ps); ps.spawn = (k, ...a) => (k === P.DUST || k === P.VAPOUR || k === P.SMOKE ? sp0(k, ...a) : null); }   // §14.7：甩出物不画
  const sp = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * SY];
  const a0 = Rg.range(-Math.PI, Math.PI), SPIN = 0.3, TAIL = 2.0;
  const head = (t) => a0 + TAU * 1.02 * ease.outCubic(clamp(t / SPIN));
  // 收链：拖痕（角度不等距、长短不一，略带旋）
  const drags = mv === "pull" ? jitterAngles(Rg, Rg.int(8, 10), -Math.PI, Math.PI, 0.48).map((a) => ({ a, tw: Rg.range(-0.25, 0.25), L: Rg.range(0.6, 1.0), d0: Rg.range(0, 0.06), w: Rg.chance(0.4) ? 2 : 1 })) : [];
  let t = 0, last = a0;
  return {
    update(dt) {
      t += dt;
      if (mv === "whirl" && t < SPIN + dt) {   // 甩出物：弧头经过的地方往外甩水珠、贴地扬尘（步长随机）
        const h = head(t);
        for (let a = last; a < h; a += Rg.range(0.2, 0.45)) {
          const [x, y] = sp(a, R * Rg.range(0.92, 1.02)), tx = -Math.sin(a), ty = Math.cos(a) * SY, nx = Math.cos(a), ny = Math.sin(a) * SY;
          for (let k = 0, n = Rg.int(0, 2); k < n; k++) {
            const v = Rg.range(90, 220);
            ps.spawn(k ? P.MOTE : P.SPARK, x, y - Rg.range(2, 8), (tx * 0.7 + nx * 0.8) * v, (ty * 0.7 + ny * 0.8) * v - Rg.range(30, 80), Rg.range(0.1, 0.22) * DL, C[6 + Rg.int(0, 1)], Rg.range(0.7, 1.2));   // 短命：甩出去就灭，不在身后留一整圈
          }
          if (deco && Rg.chance(0.5)) ps.spawn(P.DUST, x, y, nx * 20, -Rg.range(4, 12), Rg.range(0.3, 0.55) * DL, D[3 + Rg.int(0, 1)], Rg.range(1.5, 3));
        }
        last = h;
      }
      if (mv === "pull" && deco) for (const d of drags) {   // 尘往里卷
        const u = t - d.d0;
        if (u > 0 && u < 0.2 && Rg.chance(0.4)) {
          const r = R - (R - Ri) * clamp(u / 0.2), [x, y] = sp(d.a + d.tw * (1 - u / 0.2), r);
          ps.spawn(P.DUST, x, y, -Math.cos(d.a) * 60, -Math.sin(d.a) * 30 - 6, Rg.range(0.25, 0.45) * DL, D[3], Rg.range(1.5, 2.6));
        }
      }
      ps.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (core && mv === "pull") for (const d of drags) {   // 拖痕：外圈 → 判定边，前端亮，后面留一道暗沟慢慢合上
        const u = t - d.d0;
        if (u < 0) continue;
        const front = R * 1.05 - (R * 1.05 - Ri) * ease.outCubic(clamp(u / 0.18)), fade = 1 - smooth(0.25, 0.5 * DL + 0.1, u);
        if (fade <= 0.02) continue;
        for (let r = front; r < Math.min(R * 1.1, front + (R - Ri) * (0.8 + 0.5 * d.L)); r += 0.6) {
          const v = (r - front) / Math.max(1, R - Ri), a = d.a + d.tw * v + 0.03 * noise(r * 0.4, o.seed + 5);
          const [x, y] = sp(a, r);
          const hot = r - front < 2.5 && u < 0.2;
          for (let q = 0; q < d.w + 1; q++) p.blend(x, y + q * 0.7, hot ? C[7] : q === 0 ? (v < 0.4 ? C[5] : C[4]) : D[1], fade * (hot ? 1 : 0.9 - 0.4 * v));
        }
      }
    },
    draw(p) {
      if (core && mv === "whirl") {   // 水幕弧：沿判定圆的一段，弧头最高最亮，往后矮下去、碎开
        const h = head(t), k = 1 - smooth(SPIN, SPIN + 0.22 * DL, t);
        if (k > 0.02) for (let s = 0; s < TAIL; s += 0.55 / R) {
          const a = h - s, v = s / TAIL;
          if (v > 0.45 && noise(a * 7, o.seed + 9) < -0.35) continue;
          const H = (7 + 4 * noise(a * 3, o.seed + 13)) * (1 - v) * k, [x, y] = sp(a, R * (1 - 0.04 * v));
          for (let d = 0; d < H; d += 0.6) {
            const top = d > H - 1.3;
            p.px(x, y - d, top ? (v < 0.15 ? C[7] : C[6]) : C[clamp(Math.round(2 + 3.5 * d / Math.max(1, H) + (1 - v) * 1.5), 2, 6)]);
          }
        }
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
