// 组 E 敌方 / Boss 砸地落点（docs/229 §4、docs/236）：俯视 3/4 地面，判定圈 = R × R·GY 的地面椭圆（R 纹素，1x 帧条 1 纹素 = 2 世界像素）。
// 每招按自己的判定半径 r 单独导出（R = r / 2）、游戏里固定 Game.PX 画：地面帧条在低分辨率层会按 2 的倍数取整缩放，按 r 连续缩放对不上判定。
// 主体 0.4 秒：首帧白热爆亮（白只在核心）→ 冷却；不规则分叉热裂（角度随机、两两 ≥ 0.6 弧度、不等长）；
// 隆起尘墙 0.2 秒推到判定半径（叠压尘团、近厚远薄、顶亮底暗、2–3 个断口，不是同心圈）；碎石抛起落地；0.2 / 0.3 秒两次余震。
// 余韵 0.4–0.72 秒：只剩尘墙沉降，alpha ≤ TAIL_ALPHA，末帧空。
// 色：普通敌方用 DANGER_RAMP；opts.boss = 1 用 Boss 色 #ff6726 的同构色阶。尘土 = 危险色暗阶混中性灰（不用深海青、不用我方色阶）。
import { Particles, Lights, P, Rng, clamp, ease, smooth, TAU, WHITE, hex, mix, bolt, forks } from "../../core/index.js";
import { DANGER_RAMP, FPS, TAIL_ALPHA, DUR, heat } from "../house.js";

// Boss 色阶：与 DANGER_RAMP 同构（暗 35/60 → 设定色 #ff6726 → 浅 → 白），house.js 只给了 BOSS 单色
const BOSS_RAMP = ["#2a0e06", "#5c1d0a", "#a33814", "#ff6726", "#ffa07a", "#ffdcd0", "#ffffff"];
const GREY = hex("#6a6466");

export const meta = {
  name: "AK enemy slam",
  desc: "Enemy / boss ground slam from above: white-hot core flash cooling down the danger ramp, branching fissures, a lumpy dust wall pushed to the hit radius, rocks, aftershocks.",
  tags: ["impact", "ground", "slam", "enemy", "one-shot"],
  size: [150, 112],
  origin: [75, 62],
  duration: 0.72,
  loop: false,
  fps: FPS.enemy,
  bg: "ground",
  options: { R: 35, boss: 0, tail: 0.32, inner: 1, seed: 3 },
};

const GY = 0.55;            // 地面纵向压缩，和游戏 ground_y 一致
const MAIN = DUR.enemyBurst; // 主体 0.4 秒，之后是余韵
const WALL_T = 0.2;         // 尘墙推到判定半径用时
const SHOCKS = [0.2, 0.3];
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

export function create(o) {
  const RAMP = (o.boss ? BOSS_RAMP : DANGER_RAMP).map(hex), R = o.R, Rn = new Rng(o.seed), D = MAIN + Math.min(o.tail, meta.duration - MAIN);   // 余韵长度可按条目收短（大半径省体积）
  const DU = [mix(RAMP[0], GREY, 0.25), mix(RAMP[1], GREY, 0.55), mix(RAMP[1], GREY, 0.8), mix(RAMP[2], GREY, 0.75), mix(RAMP[4], GREY, 0.6)];
  const ps = new Particles({ rng: Rn }), lights = new Lights();
  const HOT = [RAMP[6], RAMP[5], RAMP[4], RAMP[3], RAMP[2], RAMP[1]];   // 热度 1 → 0
  const hotCol = (h) => HOT[Math.min(5, Math.floor((1 - clamp(h)) * 5.99))];
  const onFloor = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * GY];
  const shockK = (t) => SHOCKS.reduce((m, ts) => Math.max(m, t >= ts ? clamp(1 - (t - ts) / 0.08) : 0), 0);

  const cracks = [];
  const nC = Rn.int(4, 6), angs = [];
  while (angs.length < nC) {
    const a = Rn.range(0, TAU);
    if (angs.every((b) => Math.abs(wrap(a - b)) > 0.6)) angs.push(a);
  }
  for (const a of angs) {
    const L = R * Rn.range(0.45, 0.95), [x1, y1] = onFloor(a, L);
    const path = bolt(Rn, 0, 0, x1, y1, { jag: 0.3, depth: 4 });
    cracks.push({ pts: path, w: Rn.range(1.6, 2.4), t0: 0 });
    for (const f of forks(Rn, path, { count: Rn.int(0, 2), len: L * 0.4, jag: 0.35, spread: 0.8 })) cracks.push({ pts: f, w: 1, t0: Rn.range(0.03, 0.06) });
  }
  const nB = Rn.int(9, 12), blob = Array.from({ length: nB }, (_, i) => ({ a: (i / nB) * TAU + Rn.range(-0.2, 0.2), r: Rn.range(0.55, 1.3) }));
  const gaps = Array.from({ length: Rn.int(2, 3) }, () => Rn.range(0, TAU));
  // 尘团沿圈随机步进（步长 0.45–1.7 倍均值，大小按随机游走起伏、偶有大团），避免等距同大小的「拼接感」（docs/229 §2.6，vreview 11-03 报过）
  const nL = Math.round(40 * Math.max(0.8, R / 35)), lumps = [], step = TAU / nL;
  let a = Rn.range(0, TAU), sz = Rn.range(3, 5);
  for (let i = 0; i < nL; i++) {
    a += step * Rn.range(0.45, 1.7);
    sz = clamp(sz + Rn.range(-1.6, 1.6), 2.2, 6.2);
    const big = Rn.chance(0.15) ? Rn.range(1.3, 1.6) : 1;
    const gap = gaps.some((g) => Math.abs(wrap(a - g)) < 0.17);
    const near = 0.95 + 0.3 * Math.max(0, Math.sin(a));
    lumps.push({ a, rj: Rn.range(0.78, 1.0), s: (gap ? 0.4 : 1) * sz * big * near, h: (gap ? 0.3 : 1) * Rn.range(2, 10) * big * near,
      lag: Rn.range(0, 0.05), drift: Rn.range(0.0, 0.04) });
  }
  const rocks = Array.from({ length: 12 }, () => ({ a: Rn.range(0, TAU), d: R * Rn.range(0.2, 0.7), h: 0, vh: Rn.range(80, 130), s: Rn.int(1, 2),
    t0: Rn.range(0, 0.03), dark: Rn.chance(0.5), bounced: false }));
  const after = SHOCKS.map(() => Array.from({ length: 3 }, () => onFloor(Rn.range(0, TAU), R * Rn.range(0.15, 0.6))));

  lights.add(0, -2, R * 0.8, RAMP[3], 0.45, 0.2);
  lights.add(0, -2, R * 0.45, WHITE, 0.7, 0.1);   // 首帧爆亮的光（加色层 _glow）：游戏尺寸下要读得出来（vreview 11-03 报首帧偏弱）

  let t = 0;
  const done = SHOCKS.map(() => false);
  return {
    update(dt) {
      t += dt;
      const u = clamp(t / WALL_T);
      if (u > 0 && u < 1)
        for (let k = 0; k < 2; k++) {
          const a = Rn.range(0, TAU), [x, y] = onFloor(a, R * ease.outQuart(u) * Rn.range(0.75, 0.88));
          ps.spawn(P.DUST, x, y - 1, Math.cos(a) * Rn.range(4, 12), -Rn.range(8, 22), Rn.range(0.12, 0.18), Rn.chance(0.4) ? DU[3] : DU[2], Rn.range(1.4, 2.4));
        }
      SHOCKS.forEach((ts, i) => {
        if (done[i] || t < ts) return;
        done[i] = true;
        for (const [x, y] of after[i])
          for (let k = 0; k < 3; k++) ps.spawn(P.DUST, x + Rn.range(-2, 2), y, Rn.range(-12, 12), -Rn.range(10, 26), Rn.range(0.08, 0.1), Rn.chance(0.5) ? DU[3] : DU[2], Rn.range(1.2, 2));
      });
      for (const r of rocks) {
        if (t < r.t0) continue;
        r.vh -= 640 * dt;
        r.h += r.vh * dt;
        r.d += dt * R * 0.6 * (r.bounced ? 0.3 : 1);
        if (r.h <= 0 && r.vh < 0) {
          r.h = 0;
          r.vh = r.bounced ? 0 : -r.vh * 0.3;
          r.bounced = true;
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    draw(p) {
      if (t >= D) return;
      const H = heat(t), SK = shockK(t), tail = t >= MAIN;
      // 1) 热裂：主体内画（0.04 秒长满、冷却、余震回红），余韵不画（beam 的半透明是抖动的，余韵只留真半透明的尘）
      if (!tail)
        for (const c of cracks) {
          const g = ease.outCubic(clamp((t - c.t0) / 0.04 + (c.t0 === 0 ? 0.6 : 0)));
          if (g <= 0) continue;
          const n = Math.max(2, Math.ceil(c.pts.length * g));
          for (let i = 1; i < n; i++) {
            const [x0, y0] = c.pts[i - 1], [x1, y1] = c.pts[i], q = i / c.pts.length;
            const hq = Math.max(H * (1 - q * 0.6), SK * 0.55 * (1 - q));
            p.beam(x0, y0, x1, y1, Math.max(1, c.w * (1 - q * 0.55)), hq > 0.1 ? hotCol(hq * 0.92) : DU[0]);
          }
        }
      // 2) 爆亮：第 0 帧核心白（只占核心 0.36 × 0.4），第 1 帧降一阶；之后坑心按热度降阶
      if (t < 0.1) {
        const hero = t < 0.05, rr = R * (hero ? 0.46 : 0.34);
        const pts = blob.map((b) => [Math.cos(b.a) * rr * b.r, Math.sin(b.a) * rr * b.r * GY]);
        p.poly(pts, hero ? RAMP[3] : RAMP[2]);
        p.poly(pts.map(([x, y]) => [x * 0.66, y * 0.66]), hero ? RAMP[4] : RAMP[3]);
        p.poly(pts.map(([x, y]) => [x * 0.4, y * 0.4 - 1]), hero ? WHITE : RAMP[4]);
        if (!hero) p.poly(pts.map(([x, y]) => [x * 0.18, y * 0.18 - 1]), WHITE);   // 第 1 帧仍留一小点白芯，冷却分两步
      } else if (!tail && (H > 0.15 || SK > 0.3)) {
        const h = Math.max(H, SK * 0.5);
        p.ellipse(0, 0, R * 0.2, R * 0.2 * GY, hotCol(h * 0.75));
        if (h > 0.45) p.ellipse(0, -0.5, R * 0.1, R * 0.1 * GY, hotCol(h * 0.9));
      }
      // 3) 尘墙：远侧 → 碎石 → 近侧；余震时抖 1 纹素；余韵段 alpha ≤ TAIL_ALPHA 并沉降
      const cap = tail ? TAIL_ALPHA * Math.pow(1 - smooth(MAIN, D, t), 1.5) : 1, jolt = SK > 0.5 ? -1 : 0, sink = smooth(WALL_T, D, t);
      const drawLump = (l) => {
        const lu = clamp((t - l.lag) / WALL_T);
        if (lu <= 0) return;
        const sz = l.s * (0.7 + 0.3 * lu) * (1 + sink * 0.5);
        const rr = Math.min(R * (ease.outQuart(lu) * l.rj + l.drift * sink), R - sz * 1.1);   // 尘团外沿钳在判定半径以内（docs/229 §2.8：落点 = 判定半径，不许更大）
        const [x, y0] = onFloor(l.a, rr), y = y0 + jolt;
        const rise = l.h * Math.sin(Math.min(1, lu * 1.2) * Math.PI * 0.5) * (1 - sink * 0.8);
        const a = cap * (tail ? 1 : 1 - 0.9 * smooth(WALL_T, MAIN, t));   // 主体后半段缓入淡到约一成（4 层叠压后 ≈ 余韵起点），交界不跳暗
        if (a <= 0.03) return;
        const [ix, iy] = onFloor(l.a, rr * 0.72);
        if (tail) {
          // 余韵：每团只画一层，单层 ≤ 0.12 × TAIL_ALPHA；随机步进会扎堆，最多叠约 8 层，合成后仍 ≤ TAIL_ALPHA（docs/229 §2.5）
          p.disc(x, y - rise * 0.5, sz * 1.05, DU[2], 0.12 * a);
          return;
        }
        if (o.inner) p.disc(ix, iy + jolt, sz * 0.8, DU[1], 0.35 * a);   // 墙后内尘（大半径可关，省体积）
        p.disc(x, y, sz * 1.1, DU[1], 0.8 * a);
        p.disc(x, y - rise * 0.5, sz, DU[2], 0.85 * a);
        p.disc(x - sz * 0.25, y - rise - sz * 0.2, sz * 0.7, t < 0.15 ? DU[4] : DU[3], 0.75 * a);
      };
      lumps.filter((l) => Math.sin(l.a) < 0).forEach(drawLump);
      if (!tail)
        for (const r of rocks) {
          if (t < r.t0) continue;
          const [x, y] = onFloor(r.a, Math.min(r.d, R * 0.95));
          if (r.h > 1) p.dot(x, y, DU[0], 0.6);
          p.rect(x - r.s / 2, y - r.h - r.s / 2, r.s + 0.5, r.s + 0.5, r.dark ? DU[1] : DU[3]);
          if (t < 0.08) p.dot(x, y - r.h - r.s / 2, RAMP[4]);
        }
      lumps.filter((l) => Math.sin(l.a) >= 0).forEach(drawLump);
      ps.draw(p);
      lights.draw(p);
    },
  };
}
