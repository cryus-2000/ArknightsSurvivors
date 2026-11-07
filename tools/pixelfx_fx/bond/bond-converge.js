// 羁绊技「群猎 · 三面合围」概念（docs/314，用户 11-07「队伍里三个人的技能组合」）：队里三名猎人从同一侧各自出手，
// 武器绕成三条不同的路——锚直线砸过去、长槊从上方弧线绕过、锯刃从下方弧线绕过——同一拍从三面钉进圈心，三色一齐炸开。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, WHITE } from "../../core/index.js";
import { Foes, op } from "./_scene.js";
import { anchor, UL } from "./_anchor.js";

export const meta = {
  name: "Bond converge", desc: "Three hunters throw their weapons along three different paths that meet in the middle of the crowd on the same beat.",
  tags: ["bond", "concept"], size: [380, 230], origin: [190, 122], duration: 2.0, loop: false, fps: 30, bg: "dark", options: { seed: 21 },
};

const GL = ["#0d1a2e", "#1f3658", "#35598f", "#4c80c7", "#7fa6e0", "#c9d9ee", "#ffffff"].map(hex);
const SP = ["#0d1832", "#1d3866", "#2c5a9a", "#3a77c2", "#78afe6", "#c4e2fa", "#ffffff"].map(hex), SPA = hex("#ffa04a");
const STEEL = [hex("#3a4250"), hex("#7a8494"), hex("#c8d0dc")], W = [hex("#14406e"), hex("#2a6aa8"), hex("#a8d8f4")];
const C = [60, 2], HIT = 0.95;
// 三人：[脚下, 出手时刻, 贝塞尔控制点, 颜色]
const H = [
  { p: [-172, 4], t0: 0.25, ctl: [-50, -10], col: UL[5], body: UL[2], hair: "#e9edf5" },      // 乌尔比安：锚，近直线
  { p: [-150, -48], t0: 0.35, ctl: [-10, -150], col: GL[5], body: GL[2], hair: "#e8e4f0" },   // 歌蕾蒂娅：长槊，从上方绕
  { p: [-146, 46], t0: 0.45, ctl: [0, 140], col: SPA, body: SP[2], hair: "#dfe6f2" },         // 幽灵鲨：锯刃，从下方绕
];

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 40, 50, 4, 130, 56);
  const water = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, W[2], W[1], W[0]] });
  const trail = [0, 1, 2].map((i) => new Particles({ rng: R, ground: () => 10, sparks: [WHITE, H[i].col, H[i].col, W[0]] }));
  const lights = new Lights();
  let t = 0, boom = false;
  const pos = (i, tt = t) => {   // 第 i 件武器的位置（二次贝塞尔，出手到 HIT）
    const h = H[i], a = [h.p[0] + 8, h.p[1] - 16], k = clamp((tt - h.t0) / (HIT - h.t0)), e = ease.inQuad(k), u = 1 - e;
    return [u * u * a[0] + 2 * u * e * h.ctl[0] + e * e * C[0], u * u * a[1] + 2 * u * e * h.ctl[1] + e * e * (C[1] - 8)];
  };
  return {
    update(dt) {
      t += dt;
      for (let i = 0; i < 3; i++) if (t > H[i].t0 && t < HIT) {
        const [x, y] = pos(i);
        trail[i].spawn(P.SPARK, x, y, R.range(-40, 40), R.range(-40, 20), R.range(0.15, 0.35));
        for (const f of foes.alive()) if (Math.hypot(f.x - x, (f.y - y - 8) * 1.3) < 12) foes.hit(f, t, R.range(-60, 60), Math.sign(f.y - y || 1) * R.range(80, 150));
      }
      if (t >= HIT && !boom) {
        boom = true; lights.add(C[0], C[1] - 6, 160, WHITE, 1.0, 0.22);
        for (let i = 0; i < 3; i++) for (let j = 0; j < 24; j++) trail[i].spawn(P.SPARK, C[0], C[1] - 4, R.range(-220, 220), R.range(-300, -20), R.range(0.3, 0.8));
        for (let j = 0; j < 30; j++) water.spawn(P.SPARK, C[0] + R.range(-12, 12), C[1], R.range(-160, 160), R.range(-240, -40), R.range(0.3, 0.8));
        for (const f of foes.alive()) { const d = Math.hypot(f.x - C[0], (f.y - C[1]) * 1.6); if (d < 85) foes.hit(f, t + d / 1000, (f.x - C[0]) * 3.5, (f.y - C[1]) * 3.5); }
      }
      foes.update(dt, t); water.update(dt); trail.forEach((q) => q.update(dt)); lights.update(dt);
    },
    draw(p) {
      for (let i = 0; i < 3; i++) op(p, H[i].p[0], H[i].p[1], H[i].body, H[i].hair, t > H[i].t0 - 0.08 && t < H[i].t0 + 0.25 ? 1 : 0, 1);
      foes.draw(p, t);
      const fade = 1 - smooth(HIT + 0.3, HIT + 0.7, t);
      // 锚
      { const [x, y] = t < H[0].t0 ? [H[0].p[0] + 9, H[0].p[1] - 2] : pos(0); anchor(p, x, y, t < H[0].t0 ? 0 : t < HIT ? -Math.PI / 2 : 0, 1, fade); }
      // 长槊（朝运动方向）
      if (t > H[1].t0 - 0.1) {
        const [x, y] = pos(1), [x0, y0] = pos(1, t - 0.03), a = t < HIT ? Math.atan2(y - y0, x - x0) : 1.4, c = Math.cos(a), s = Math.sin(a);
        p.beam(x - c * 40, y - s * 40, x - c * 4, y - s * 4, 2.2, GL[3], fade); p.line(x - c * 40, y - s * 40 - 1, x - c * 4, y - s * 4 - 1, GL[5], fade);
        p.tri(x - c * 6 - s * 4, y - s * 6 + c * 4, x + c * 4, y + s * 4, x - c * 6 + s * 4, y - s * 6 - c * 4, GL[5], fade);
        p.glow(x, y, 9, GL[5], 0.35 * fade);
      }
      // 锯刃
      if (t > H[2].t0 - 0.1) {
        const [x, y] = pos(2), r = 8, sp = t * 50;
        p.circle(x, y, r, STEEL[1], fade); p.circle(x, y, r - 3, STEEL[0], fade);
        for (let i = 0; i < 10; i++) { const a = sp + i * Math.PI / 5; p.tri(x + Math.cos(a) * r, y + Math.sin(a) * r, x + Math.cos(a + 0.35) * (r + 4), y + Math.sin(a + 0.35) * (r + 4), x + Math.cos(a + 0.5) * r, y + Math.sin(a + 0.5) * r, i % 2 ? STEEL[2] : SPA, fade); }
        p.glow(x, y, 12, SPA, 0.35 * fade);
      }
      water.draw(p); trail.forEach((q) => q.draw(p)); lights.draw(p);
      if (t > HIT && t < HIT + 0.07) p.ellipse(C[0], C[1] - 4, 28, 11, WHITE, 0.7);
    },
  };
}
