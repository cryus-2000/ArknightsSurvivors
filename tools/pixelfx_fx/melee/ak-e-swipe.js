// 组 E 敌方近战：扇形挥击 / 咬合 / 直线突刺（docs/229 §4、docs/236）。原点 = 出手点（扇心 / 线起点），朝 +x，游戏按出手方向旋转。
// shape = "arc"：沿半径 R、半角 half 扫一道不规整的肢影弧（外缘按噪声起伏、厚薄不一），扫过处留 2–3 道长短不一的爪痕和碎屑；
// shape = "bite"：上下两道弧形颚影向中线合拢，合拢处爆一下；
// shape = "line"：沿 +x 长 R 的触须 / 枪尖突刺，前端爆亮、两侧甩出碎屑；
// shape = "spray"：扇内一束角度随机、长短不一的流束向外冲（呼号 / 喷涌 / 吐息），出口一团热。
// 主体 ≤ 0.3 秒：第 0 帧刃口最亮（白只在最前沿）→ 冷却；余韵 ≤ 0.15 秒只剩稀疏碎屑，单层 alpha ≤ 0.12 × TAIL_ALPHA。
// 体量：arc 外沿 = R（判定半径 × 0.85 以内由导出参数控制），line 长 = R（判定全长）。色：DANGER_RAMP；boss = 1 用 Boss 色阶。
import { Particles, P, Rng, clamp, ease, smooth, TAU, WHITE, hex, mix, noise } from "../../core/index.js";
import { DANGER_RAMP, FPS, TAIL_ALPHA } from "../house.js";

const BOSS_RAMP = ["#2a0e06", "#5c1d0a", "#a33814", "#ff6726", "#ffa07a", "#ffdcd0", "#ffffff"];
const GREY = hex("#6a6466");
const MAIN = 0.3;

export const meta = {
  name: "AK enemy swipe",
  desc: "Enemy melee from above: a ragged limb arc sweeps, jaws snap shut, or a tendril thrusts; the leading edge flashes then cools down the danger ramp, leaving uneven claw marks and grit.",
  tags: ["melee", "slash", "enemy", "one-shot"],
  size: [320, 320],
  origin: [160, 160],
  duration: 0.45,
  loop: false,
  fps: FPS.enemy,
  bg: "ground",
  options: { R: 40, half: 0.6, shape: "arc", boss: 0, w: 0, tail: 0.15, seed: 1 },
};

export function create(o) {
  const RAMP = (o.boss ? BOSS_RAMP : DANGER_RAMP).map(hex), R = o.R, Rn = new Rng(o.seed), D = MAIN + o.tail, S = o.shape;
  const DU = [mix(RAMP[0], GREY, 0.3), mix(RAMP[1], GREY, 0.6), mix(RAMP[2], GREY, 0.7)];
  const HOT = [RAMP[6], RAMP[5], RAMP[4], RAMP[3], RAMP[2], RAMP[1]];
  const hotCol = (h) => HOT[Math.min(5, Math.floor((1 - clamp(h)) * 5.99))];
  const ps = new Particles({ rng: Rn });
  const sd = Rn.range(0, 50), W = o.w || Math.max(3, R * 0.18);   // 刀光厚度缺省随半径
  // 爪痕：2–3 道，角度 / 长度 / 起点都随机
  const marks = Array.from({ length: Rn.int(2, 3) }, () => ({ a: Rn.range(-o.half * 0.8, o.half * 0.8), r0: R * Rn.range(0.35, 0.6), r1: R * Rn.range(0.7, 0.98), t0: Rn.range(0.04, 0.12) }));
  const grit = Array.from({ length: Rn.int(5, 8) }, () => ({ a: Rn.range(-o.half, o.half), r: R * Rn.range(0.5, 1.0), v: Rn.range(6, 16), s: Rn.int(1, 2), t0: Rn.range(0.05, 0.15) }));
  const nB = Rn.int(6, 8), blob = Array.from({ length: nB }, (_, i) => ({ a: (i / nB) * TAU + Rn.range(-0.25, 0.25), r: Rn.range(0.6, 1.3) }));
  const jets = [];
  for (let tries = 0; jets.length < Math.round(o.half * 18) && tries < 600; tries++) {
    const a = Rn.range(-o.half, o.half);
    if (jets.every((j) => Math.abs(j.a - a) >= 0.06)) jets.push({ a, l: Rn.range(0.55, 1.0), t0: Rn.range(0, 0.05) });
  }
  let t = 0;
  // 扇形刀光：在 [a0, a1] 上画厚度 th(角度)，外缘 R，内缘 R - th；颜色按「离前沿多远」降阶
  const sweep = (p, a0, a1, lead, h) => {
    const span = Math.abs(a1 - a0), steps = Math.max(6, Math.ceil(span * R / 1.2));
    for (let i = 0; i <= steps; i++) {
      const v = i / steps, a = a0 + (a1 - a0) * v, q = Math.abs(a - lead) / Math.max(0.01, span);
      const th = W * (0.55 + 0.45 * noise(a * 3 + sd)) * Math.pow(Math.sin(Math.PI * clamp(v * 0.92 + 0.04)), 0.6);   // 两头收尖、中段最厚
      const ro = R * (0.93 + 0.07 * noise(a * 7 + sd));
      p.line(Math.cos(a) * (ro - th), Math.sin(a) * (ro - th), Math.cos(a) * ro, Math.sin(a) * ro, q < 0.1 ? hotCol(h) : q < 0.4 ? hotCol(h * 0.75) : hotCol(h * 0.45));
    }
  };
  return {
    update(dt) {
      t += dt;
      ps.update(dt);
    },
    draw(p) {
      if (t >= D) return;
      const tail = t >= MAIN, H = 1 - clamp(t / 0.25), cap = TAIL_ALPHA * 0.12 * (1 - smooth(MAIN, D, t));
      if (!tail) {
        if (S === "arc") {
          const u = ease.outQuart(clamp(t / 0.1 + 0.35)), lead = -o.half + 2 * o.half * u, back = -o.half + 2 * o.half * ease.inQuad(clamp((t - 0.08) / 0.16));   // 先铺满整段月牙，再从尾部收回
          if (lead - back > 0.05) sweep(p, back, lead, lead, H);
        } else if (S === "bite") {
          const u = ease.inQuad(clamp(t / 0.1));
          for (const sg of [-1, 1]) {
            const a = sg * o.half * (1 - u * 0.92);
            if (t < 0.2) sweep(p, sg * o.half * 1.05, a, a, H);
          }
          if (t >= 0.1 && t < 0.18) p.disc(R * 0.85, 0, W * 0.9, t < 0.14 ? WHITE : RAMP[4], 1);
        } else if (S === "spray") {
          // 扇形喷涌：角度随机（两两 ≥ 0.06 弧度）、长短不一的流束，头亮尾暗，出口处一团热
          for (const j of jets) {
            const u = clamp((t - j.t0) / 0.16 + 0.25);
            if (u <= 0 || t > 0.26) continue;
            const r1 = R * j.l * ease.outCubic(u), r0 = Math.max(0, r1 - R * 0.35 * j.l);
            const h = H * (1 - u * 0.4);
            for (let r = r0; r <= r1; r += 1)
              p.dot(Math.cos(j.a) * r, Math.sin(j.a) * r, (r1 - r) < 2 ? hotCol(h) : (r1 - r) < R * 0.12 ? hotCol(h * 0.7) : hotCol(h * 0.4));
          }
          if (t < 0.1) {
            const rr = W * (t < 0.05 ? 0.8 : 0.55), pts = blob.map((b) => [W * 0.4 + Math.cos(b.a) * rr * b.r, Math.sin(b.a) * rr * b.r]);
            p.poly(pts, t < 0.05 ? RAMP[4] : RAMP[3]);
            if (t < 0.05) p.poly(pts.map(([x, y]) => [W * 0.4 + (x - W * 0.4) * 0.4, y * 0.4]), WHITE);
          }
        } else {   // line
          const u = ease.outQuart(clamp(t / 0.1 + 0.3)), x1 = R * u;
          if (t < 0.22)
            for (let x = 0; x <= x1; x += 1) {
              const q = (x1 - x) / Math.max(1, R), th = W * (0.25 + 0.75 * (x / R)) * (0.6 + 0.4 * noise(x * 0.3 + sd)) * 0.5;
              p.line(x, -th, x, th, q < 0.06 ? hotCol(H) : q < 0.3 ? hotCol(H * 0.75) : hotCol(H * 0.4));
            }
          if (t < 0.08) p.disc(x1, 0, W * 0.45, t < 0.05 ? WHITE : RAMP[4], 1);
        }
        // 爪痕：出现后由亮到暗
        for (const m of marks) {
          if (t < m.t0 || S === "line" || S === "spray") continue;
          const k = clamp((t - m.t0) / 0.15);
          p.line(Math.cos(m.a) * m.r0, Math.sin(m.a) * m.r0, Math.cos(m.a) * m.r1, Math.sin(m.a) * m.r1, k < 0.4 ? RAMP[4] : k < 0.8 ? RAMP[2] : DU[1]);
        }
      }
      // 碎屑：沿刃口外甩，余韵只留淡点
      for (const g of grit) {
        if (t < g.t0) continue;
        const k = t - g.t0, a = S === "line" ? (g.a > 0 ? 1 : -1) * (0.6 + Math.abs(g.a)) : g.a;
        const r = S === "line" ? R * (g.r / R) : g.r + g.v * k * 4;
        const x = S === "line" ? r : Math.cos(a) * r, y = S === "line" ? Math.sign(a) * g.v * k * 3 : Math.sin(a) * r;
        if (!tail) p.rect(x, y, g.s, g.s, k < 0.08 ? RAMP[3] : DU[2]);
        else p.disc(x, y, g.s, DU[2], cap);
      }
      if (t < 0.12) p.glow(S === "line" ? R * 0.8 : S === "spray" ? W * 0.4 : R * 0.7, 0, S === "spray" ? W * 1.5 : R * 0.35, RAMP[3], 0.35 * (1 - t / 0.12));
    },
  };
}
