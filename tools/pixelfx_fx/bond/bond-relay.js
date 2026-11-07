// 羁绊技「群猎 · 接力」概念（docs/314，用户 11-07「队伍里三个人的技能组合」）：一团深海的水在队里三人之间依次经手，
// 每人加一下招牌动作（乌尔比安：锚链缠上；歌蕾蒂娅：长槊挑高；归溟幽灵鲨：锯刃加转），越滚越大，最后砸进怪群炸开水冠。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, WHITE } from "../../core/index.js";
import { Foes, op } from "./_scene.js";
import { UL } from "./_anchor.js";

export const meta = {
  name: "Bond relay", desc: "A ball of deep water passes through three hunters, each adding their touch, then crashes into the crowd.",
  tags: ["bond", "concept"], size: [380, 210], origin: [190, 122], duration: 2.3, loop: false, fps: 30, bg: "dark", options: { seed: 3 },
};

const GL = ["#0d1a2e", "#1f3658", "#35598f", "#4c80c7", "#7fa6e0", "#c9d9ee", "#ffffff"].map(hex), GLA = hex("#b3a8ee");
const SP = ["#0d1832", "#1d3866", "#2c5a9a", "#3a77c2", "#78afe6", "#c4e2fa", "#ffffff"].map(hex), SPA = hex("#ffa04a");
const W = [hex("#0b2140"), hex("#14406e"), hex("#2a6aa8"), hex("#5aa2dc"), hex("#a8d8f4"), WHITE];
// 三人：乌尔比安、歌蕾蒂娅、幽灵鲨；终点在怪群中心
const PTS = [[-176, 10], [-128, -46], [-86, 30]], TGT = [70, 2];
const KEYS = [0.0, 0.35, 0.7, 1.05, 1.4];   // 起手、交给 2、交给 3、出手、落地

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 38, 60, 4, 120, 52);
  const water = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, W[4], W[3], W[2]] });
  const sparks = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, hex("#ffe0a0"), SPA, hex("#8a3a10")] });
  const lights = new Lights();
  const done = [false, false, false, false];
  let t = 0;
  const leg = () => { for (let i = 0; i < 4; i++) if (t < KEYS[i + 1]) return i; return 4; };
  const H = (q, dy = 16) => [q[0] + 8, q[1] - dy];
  const LEGS = [[H(PTS[0]), H(PTS[1]), 36], [H(PTS[1]), H(PTS[2]), 30], [H(PTS[2]), H(PTS[2], 70), 0], [H(PTS[2], 70), [TGT[0], TGT[1] - 6], 50]];
  const ball = () => {   // [x, y(含高度), 半径]
    const i = leg(); if (i >= 4) return [TGT[0], TGT[1] - 6, 14];
    const [src, dst, hh] = LEGS[i], k = (t - KEYS[i]) / (KEYS[i + 1] - KEYS[i]), e = i === 3 ? ease.inQuad(k) : ease.outQuad(k);
    return [src[0] + (dst[0] - src[0]) * e, src[1] + (dst[1] - src[1]) * e - hh * Math.sin(Math.PI * k), [5, 7, 9, 11][i] + (i === 3 ? 3 * k : 0)];
  };
  return {
    update(dt) {
      t += dt;
      const [bx, by] = ball();
      for (let i = 0; i < 4; i++) if (!done[i] && t >= KEYS[i + 1]) {
        done[i] = true;
        const col = [UL[5], GLA, SPA, W[4]][i];
        lights.add(bx, by, i === 3 ? 160 : 60, col, i === 3 ? 1.0 : 0.6, i === 3 ? 0.25 : 0.12);
        for (let j = 0; j < (i === 3 ? 70 : 12); j++) water.spawn(P.SPARK, bx + (i === 3 ? R.range(-10, 10) : 0), by + (i === 3 ? 4 : 0), R.range(-160, 160) * (i === 3 ? 1.4 : 1), R.range(-260, -20), R.range(0.25, i === 3 ? 0.9 : 0.4));
        if (i === 3) for (const f of foes.alive()) { const d = Math.hypot(f.x - TGT[0], (f.y - TGT[1]) * 1.6); if (d < 80) foes.hit(f, t + d / 900, (f.x - TGT[0]) * 3.5, (f.y - TGT[1]) * 3.5); }
      }
      if (leg() === 3) for (let j = 0; j < 3; j++) sparks.spawn(P.SPARK, bx, by, R.range(-120, 120), R.range(-120, 60), R.range(0.1, 0.25));
      water.spawn(P.SPARK, bx + R.range(-3, 3), by + R.range(-3, 3), R.range(-30, 30), R.range(-30, 20), R.range(0.1, 0.25));
      foes.update(dt, t); water.update(dt); sparks.update(dt); lights.update(dt);
    },
    draw(p) {
      const L = leg();
      op(p, PTS[0][0], PTS[0][1], UL[2], hex("#e9edf5"), L === 0 ? 1 : 0, 1);
      op(p, PTS[1][0], PTS[1][1], GL[2], hex("#e8e4f0"), L === 1 ? 1 : 0, 1);
      op(p, PTS[2][0], PTS[2][1], SP[2], hex("#dfe6f2"), L >= 2 && L < 4 ? 1 : 0, 1);
      foes.draw(p, t);
      if (t < KEYS[4] + 0.02) {
        const [bx, by, r] = ball();
        p.ellipse(bx, Math.max(by + r + 14, -2) + 6, r, r * 0.3, W[0], 0.4);
        p.circle(bx, by, r + 1, W[1]); p.circle(bx, by, r, W[2]); p.circle(bx - r * 0.25, by - r * 0.25, r * 0.6, W[3]); p.circle(bx - r * 0.4, by - r * 0.45, Math.max(1, r * 0.22), W[5]);
        p.glow(bx, by, r * 2.2, W[4], 0.4);
        if (L >= 1) for (let i = 0; i < 6; i++) { const a = t * 6 + i; p.ellipse(bx + Math.cos(a) * r, by + Math.sin(a) * r * 0.5, 2, 1.3, UL[3]); }   // 缠上的锚链环
        if (L >= 2) { p.arc(bx, by, r + 4, 1.5, t * 9, t * 9 + 1.6, GLA, 0.8); p.arc(bx, by, r + 4, 1.5, t * 9 + 3.14, t * 9 + 4.7, GLA, 0.8); }   // 长槊挑过的淡紫流光
        if (L >= 3) for (let i = 0; i < 8; i++) { const a = t * 30 + i * Math.PI / 4, rr = r + 6; p.tri(bx + Math.cos(a) * rr, by + Math.sin(a) * rr, bx + Math.cos(a + 0.3) * (rr + 4), by + Math.sin(a + 0.3) * (rr + 4), bx + Math.cos(a + 0.45) * rr, by + Math.sin(a + 0.45) * rr, SPA); }   // 锯刃加转
      }
      // 每次经手：那人手边一下动作光
      const tk = [KEYS[1], KEYS[2], KEYS[3]];
      for (let i = 0; i < 3; i++) { const a = t - tk[i]; if (a > -0.08 && a < 0.12) { const [x, y] = LEGS[i][1]; p.circle(x, y, 10 * (1 - Math.abs(a) * 5), WHITE, 0.6); } }
      water.draw(p); sparks.draw(p); lights.draw(p);
      if (t > KEYS[4] && t < KEYS[4] + 0.07) p.ellipse(TGT[0], TGT[1] - 4, 26, 10, WHITE, 0.6);
    },
  };
}
