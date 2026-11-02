// 组 E 敌方命中 / 小型溅射（docs/229 §4、docs/236）：原点 = 命中点，俯视；opts.dir = 1 时朝 +x（游戏按飞行方向旋转），0 时不分方向。
// 主体 ≤ 0.3 秒：第 0 帧不规则小热团（白只在核心）→ 冷却；按 kind 出不同材质的碎片，角度随机且两两 ≥ 0.45 弧度、长短不一（不等距放射）：
//   shard 硬碎片拖线（弹体迸散）；goo 液滴抛起落地成小渍（酸 / 侵蚀 / 溅水）；nerve 2–3 条短分叉电弧闪两帧；grit 碎石块 + 小尘团。
// 余韵 ≤ 0.15 秒：只剩落地小渍 / 尘，单层 alpha ≤ 0.12 × TAIL_ALPHA。R = 碎片飞出的最远距离（纹素）。
// 色：DANGER_RAMP；opts.boss = 1 用 Boss 色阶（同 ak-e-slam）。
import { Particles, P, Rng, clamp, ease, smooth, TAU, WHITE, hex, mix, bolt, forks } from "../../core/index.js";
import { DANGER_RAMP, FPS, TAIL_ALPHA } from "../house.js";

const BOSS_RAMP = ["#2a0e06", "#5c1d0a", "#a33814", "#ff6726", "#ffa07a", "#ffdcd0", "#ffffff"];
const GREY = hex("#6a6466");
const GREY_RAMP = ["#262626", "#4a4a4a", "#737373", "#9e9e9e", "#c8c8c8", "#ececec", "#ffffff"];   // ramp: "grey"：中性灰阶，给代码按弹色着色的件（Boss 弹迸散 / 拖尾）

const MAIN = 0.3;

export const meta = {
  name: "AK enemy hit",
  desc: "Enemy hit / small splash from above: a ragged hot pop cooling down the danger ramp, then shards, goo drops, nerve arcs or grit thrown at uneven angles, leaving a faint stain.",
  tags: ["impact", "hit", "enemy", "one-shot"],
  size: [72, 64],
  origin: [36, 32],
  duration: 0.45,
  loop: false,
  fps: FPS.enemy,
  bg: "ground",
  options: { R: 10, kind: "shard", dir: 0, boss: 0, ramp: "", half: 0, n: 7, tail: 0.15, seed: 1 },   // half：1 只画近半（y ≥ 0，前层）、-1 只画远半（后层），0 全画
};

const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

export function create(o) {
  const RAMP = (o.ramp === "grey" ? GREY_RAMP : o.boss ? BOSS_RAMP : DANGER_RAMP).map(hex), R = o.R, Rn = new Rng(o.seed), D = MAIN + o.tail, K = o.kind;
  const DU = [mix(RAMP[0], GREY, 0.3), mix(RAMP[1], GREY, 0.6), mix(RAMP[2], GREY, 0.7), mix(RAMP[4], GREY, 0.55)];
  const HOT = [RAMP[6], RAMP[5], RAMP[4], RAMP[3], RAMP[2], RAMP[1]];
  const hotCol = (h) => HOT[Math.min(5, Math.floor((1 - clamp(h)) * 5.99))];
  const heat = (t) => 1 - clamp(t / 0.28);
  const ps = new Particles({ rng: Rn });
  // 碎片角度：不分方向时整圈随机、分方向时集中在 +x ±1.0 弧度；两两 ≥ 0.45 弧度
  const angs = [];
  for (let tries = 0; angs.length < o.n && tries < 400; tries++) {
    const a = o.dir ? Rn.range(-1.0, 1.0) : Rn.range(0, TAU);
    if (angs.every((b) => Math.abs(wrap(a - b)) >= (o.dir ? 0.25 : 0.45))) angs.push(a);
  }
  const bits = angs.map((a) => ({ a, d: R * Rn.range(0.3, 1.0), sp: Rn.range(0.7, 1.3), w: Rn.range(1, 2) * Math.max(1, R / 18), h0: Rn.range(2, 6), t0: Rn.range(0, 0.04) }));   // w：大半径（囊海破膜）液滴跟着放大
  const nB = Rn.int(6, 8), blob = Array.from({ length: nB }, (_, i) => ({ a: (i / nB) * TAU + Rn.range(-0.25, 0.25), r: Rn.range(0.55, 1.35) }));
  const arcs = K === "nerve" ? angs.slice(0, Rn.int(2, 3)).map((a) => {
    const L = R * Rn.range(0.6, 1.0), path = bolt(Rn, 0, 0, Math.cos(a) * L, Math.sin(a) * L * 0.8, { jag: 0.35, depth: 3 });
    return [path, ...forks(Rn, path, { count: 1, len: L * 0.4, jag: 0.4, spread: 0.9 })];
  }) : [];
  let t = 0;
  return {
    update(dt) {
      t += dt;
      if (K === "grit" && t < 0.1 && Rn.chance(0.6)) {
        const a = Rn.pick(angs) ?? 0;
        ps.spawn(P.DUST, Math.cos(a) * R * 0.3, Math.sin(a) * R * 0.25, Math.cos(a) * 18, Math.sin(a) * 12 - 8, Rn.range(0.15, 0.22), Rn.chance(0.5) ? DU[2] : DU[3], Rn.range(1.2, 2));
      }
      ps.update(dt);
    },
    draw(p) {
      if (t >= D) return;
      const H = heat(t), tail = t >= MAIN, cap = tail ? TAIL_ALPHA * 0.12 * (1 - smooth(MAIN, D, t)) : 1;
      // 1) 爆亮：第 0 帧热团（白芯），第 1 帧缩小降一阶
      if (t < 0.1 && o.half >= 0) {   // 热团只在前层（或不分层时）
        const hero = t < 0.05, rr = R * (hero ? 0.42 : 0.28);
        const pts = blob.map((b) => [Math.cos(b.a) * rr * b.r + (o.dir ? rr * 0.3 : 0), Math.sin(b.a) * rr * b.r * 0.8]);
        p.poly(pts, hero ? RAMP[3] : RAMP[2]);
        p.poly(pts.map(([x, y]) => [x * 0.6, y * 0.6]), hero ? RAMP[4] : RAMP[3]);
        if (hero) p.poly(pts.map(([x, y]) => [x * 0.22, y * 0.22]), WHITE);   // 白只在核心（近白 ≤ 12%，小 R 时尤其要收）
      }
      // 2) 电弧：前 2 帧亮、第 3 帧暗阶
      if (K === "nerve" && t < 0.16)
        for (const path of arcs.flat()) {
          const c = t < 0.1 ? (t < 0.05 ? RAMP[5] : RAMP[4]) : RAMP[2];
          for (let i = 1; i < path.length; i++) p.line(path[i - 1][0], path[i - 1][1], path[i][0], path[i][1], c);
        }
      // 3) 碎片 / 液滴 / 碎石：飞出（outCubic）、抬高按抛物线、主体内冷却；液滴落地留小渍
      for (const b of bits) {
        if (o.half && Math.sign(Math.sin(b.a) || 1) !== o.half) continue;   // 前后分层
        const u = clamp((t - b.t0) / (0.22 * b.sp));
        if (u <= 0) continue;
        const e = ease.outCubic(u), x = Math.cos(b.a) * b.d * e, y = Math.sin(b.a) * b.d * e * 0.8, hgt = b.h0 * 4 * u * (1 - u);
        if (K === "goo") {
          if (u < 1 && !tail) {
            p.disc(x, y - hgt, b.w * 0.9, hotCol(H * 0.8), 0.95);
            p.dot(x - 0.5, y - hgt - 0.5, RAMP[5]);
          } else p.disc(x, y, b.w * 1.3, u < 1 ? RAMP[2] : DU[1], tail ? cap : 0.5);
        } else if (K === "grit") {
          if (!tail) {
            p.rect(x - b.w / 2, y - hgt - b.w / 2, b.w + 0.5, b.w + 0.5, u < 0.3 ? RAMP[3] : DU[b.w > 1.5 ? 1 : 3]);
            if (hgt > 1) p.blend(x, y, DU[0], 0.5);
          } else p.disc(x, y, b.w, DU[2], cap);
        } else if (!tail && u < 1) {   // shard / nerve：短拖线，头亮尾暗；后三成逐级变暗变细，飞到头就消失（末帧不突然断）
          const L = 2 + 4 * (1 - u), tx = x - Math.cos(b.a) * L, ty = y - Math.sin(b.a) * L * 0.8;
          if (u < 0.7) p.beam(tx, ty, x, y, Math.max(1, b.w * 0.8), u < 0.4 ? hotCol(H * 0.8) : hotCol(H * 0.55));   // 碎片最亮到浅色阶，白留给核心
          else p.line(x - Math.cos(b.a) * 2, y - Math.sin(b.a) * 1.6, x, y, u < 0.85 ? RAMP[2] : RAMP[1]);
        }
      }
      ps.draw(p);
      if (t < 0.12) p.glow(o.dir ? R * 0.12 : 0, 0, R * 0.9, RAMP[3], 0.4 * (1 - t / 0.12));
    },
  };
}
