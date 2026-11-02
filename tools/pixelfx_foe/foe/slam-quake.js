// 敌方 / Boss 砸地（docs/236）：俯视 3/4 地面，判定圈是 R × R·GY 的地面椭圆（R 纹素，1 纹素 = 2 世界像素，游戏里按 w.r / R 缩放）。
// 首帧白热爆亮后冷却（白 → 危险粉红 → 暗红 → 焦黑）；不规则分叉热裂（角度随机、不等长、带分叉，不是规整放射）；
// 隆起尘墙：一圈互相叠压的疙瘩状尘团由中心推到判定半径（outQuart），近侧厚远侧薄、顶亮底暗、高低错落、2–3 个断口，
// 墙后拖一层更淡的内尘；碎石抛起落地弹一下；0.30 / 0.46 秒两次余震（热裂回红 + 尘墙一抖 + 坑内小尘团）。0.72 秒后全空。
// 危险色取 balance.json render/optical_col_danger（h .95 s .85 v 1 ≈ #ff2667）；尘土中性冷灰，不用我方灯火金 / UI 青。
import { Particles, Lights, P, Rng, fit, clamp, ease, smooth, TAU, WHITE, hex, bolt, forks } from "../../core/index.js";

export const meta = {
  name: "Foe slam quake",
  desc: "Enemy ground slam from above: white-hot jagged flash cooling to danger red, branching hot fissures, a lumpy dust wall pushed to the hit radius, rocks, aftershocks.",
  tags: ["impact", "ground", "slam", "enemy", "one-shot"],
  size: [150, 112],
  origin: [75, 62],
  duration: 0.72,
  loop: false,
  fps: 15,
  bg: "ground",
  options: {
    palette: ["#3a0818", "#7a1030", "#c8184e", "#ff2667", "#ff9cb8", "#ffffff"],
    dust: ["#1e1b24", "#3a343f", "#5e5560", "#8a7f86", "#b4a8aa"],
    R: 44,
    seed: 3,
  },
};

const GY = 0.55;          // 地面纵向压缩，和游戏 ground_y 一致
const WALL_T = 0.26;      // 尘墙推到判定半径用时
const SHOCKS = [0.30, 0.46];
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

export function create(o) {
  const C = fit(o.palette, 6), DU = (o.dust ?? meta.options.dust).map(hex), R = o.R, Rn = new Rng(o.seed), D = meta.duration;
  const ps = new Particles({ rng: Rn }), lights = new Lights();
  const HOT = [C[5], C[4], C[3], C[2], C[1], C[0]];
  const heat = (t) => Math.pow(clamp(1 - t / 0.5), 1.3);
  const hotCol = (h) => HOT[Math.min(5, Math.floor((1 - clamp(h)) * 5.99))];
  const onFloor = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * GY];
  const shockK = (t) => SHOCKS.reduce((m, ts) => Math.max(m, t >= ts ? clamp(1 - (t - ts) / 0.1) : 0), 0);

  // 热裂：4–6 条主裂，角度随机（两两相隔 ≥ 0.6 弧度，避免规整放射），长 0.45–0.95 R，各自 0–2 个分叉
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
    for (const f of forks(Rn, path, { count: Rn.int(0, 2), len: L * 0.4, jag: 0.35, spread: 0.8 })) cracks.push({ pts: f, w: 1, t0: Rn.range(0.03, 0.07) });
  }
  // 白热爆闪的不规则轮廓
  const nB = Rn.int(9, 12), blob = Array.from({ length: nB }, (_, i) => ({ a: (i / nB) * TAU + Rn.range(-0.2, 0.2), r: Rn.range(0.55, 1.3) }));
  // 尘墙：40 个尘团互相叠压，半径 0.84–1.0 R 抖动；近侧大、远侧小；2–3 个断口
  const gaps = Array.from({ length: Rn.int(2, 3) }, () => Rn.range(0, TAU));
  const lumps = [];
  for (let i = 0; i < 44; i++) {
    const a = (i / 44) * TAU + Rn.range(-0.07, 0.07);
    const gap = gaps.some((g) => Math.abs(wrap(a - g)) < 0.17);
    const wav = 0.7 + 0.3 * Math.sin(a * 3 + o.seed) * Math.sin(a * 5 + 1.7);
    const near = 0.95 + 0.3 * Math.max(0, Math.sin(a));
    lumps.push({ a, rj: Rn.range(0.84, 1.0), s: (gap ? 0.4 : 1) * Rn.range(3.2, 5.4) * wav * near, h: (gap ? 0.3 : 1) * Rn.range(3, 9) * wav * near,
      lag: Rn.range(0, 0.05), drift: Rn.range(0.02, 0.09) });
  }
  // 碎石：俯视下的地面位置 + 高度，落地弹一次
  const rocks = Array.from({ length: 12 }, () => ({ a: Rn.range(0, TAU), d: R * Rn.range(0.2, 0.7), h: 0, vh: Rn.range(70, 140), s: Rn.int(1, 2),
    t0: Rn.range(0, 0.04), dark: Rn.chance(0.5), bounced: false }));
  const after = SHOCKS.map(() => Array.from({ length: 3 }, () => onFloor(Rn.range(0, TAU), R * Rn.range(0.15, 0.6))));

  lights.add(0, -2, R * 0.7, C[3], 0.35, 0.18);
  lights.add(0, -2, R * 0.3, WHITE, 0.5, 0.07);

  let t = 0;
  const done = SHOCKS.map(() => false);
  return {
    update(dt) {
      t += dt;
      const u = clamp(t / WALL_T);
      if (u > 0 && u < 1)
        for (let k = 0; k < 2; k++) {
          const a = Rn.range(0, TAU), [x, y] = onFloor(a, R * ease.outQuart(u) * Rn.range(0.85, 1.0));
          ps.spawn(P.DUST, x, y - 1, Math.cos(a) * Rn.range(10, 26), -Rn.range(8, 22), Rn.range(0.25, 0.4), Rn.chance(0.4) ? DU[3] : DU[2], Rn.range(1.4, 2.4));
        }
      SHOCKS.forEach((ts, i) => {
        if (done[i] || t < ts) return;
        done[i] = true;
        for (const [x, y] of after[i])
          for (let k = 0; k < 3; k++) ps.spawn(P.DUST, x + Rn.range(-2, 2), y, Rn.range(-12, 12), -Rn.range(10, 26), Rn.range(0.18, 0.26), Rn.chance(0.5) ? DU[3] : DU[2], Rn.range(1.2, 2));
      });
      for (const r of rocks) {
        if (t < r.t0) continue;
        r.vh -= 520 * dt;
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
      const H = heat(t), SK = shockK(t), fade = 1 - smooth(D - 0.26, D - 0.03, t);
      // 1) 热裂：0.04 秒长满；白热 → 暗红 → 焦黑；余震时根部回红
      for (const c of cracks) {
        const g = ease.outCubic(clamp((t - c.t0) / 0.04 + (c.t0 === 0 ? 0.6 : 0)));
        if (g <= 0) continue;
        const n = Math.max(2, Math.ceil(c.pts.length * g));
        for (let i = 1; i < n; i++) {
          const [x0, y0] = c.pts[i - 1], [x1, y1] = c.pts[i], q = i / c.pts.length;
          const hq = Math.max(H * (1 - q * 0.6), SK * 0.55 * (1 - q));
          if (fade > 0.5) p.beam(x0, y0, x1, y1, Math.max(1, c.w * (1 - q * 0.55)), hq > 0.1 ? hotCol(hq) : DU[0]);
        }
      }
      // 2) 白热爆闪（前 2 帧），之后坑心按热度逐级变暗（实色，不抖动）
      if (t < 0.14) {
        const hero = t < 0.067, rr = R * (hero ? 0.36 : 0.24);
        const pts = blob.map((b) => [Math.cos(b.a) * rr * b.r, Math.sin(b.a) * rr * b.r * GY]);
        p.poly(pts, hero ? C[3] : C[2]);
        p.poly(pts.map(([x, y]) => [x * 0.66, y * 0.66]), hero ? C[4] : C[3]);
        p.poly(pts.map(([x, y]) => [x * 0.4, y * 0.4 - 1]), hero ? WHITE : C[4]);
      } else if (H > 0.15 || SK > 0.3) {
        const h = Math.max(H, SK * 0.5);
        p.ellipse(0, 0, R * 0.2, R * 0.2 * GY, hotCol(h * 0.75));
        if (h > 0.45) p.ellipse(0, -0.5, R * 0.1, R * 0.1 * GY, hotCol(h * 0.95));
      }
      // 3) 尘墙：远侧先画、碎石、近侧后画；余震时整圈抖 1 纹素
      const sink = smooth(WALL_T, D - 0.04, t), jolt = SK > 0.5 ? -1 : 0;
      const drawLump = (l) => {
        const lu = clamp((t - l.lag) / WALL_T);
        if (lu <= 0) return;
        const rr = R * (ease.outQuart(lu) * l.rj + l.drift * sink), [x, y0] = onFloor(l.a, rr), y = y0 + jolt;
        const rise = l.h * Math.sin(Math.min(1, lu * 1.2) * Math.PI * 0.5) * (1 - sink * 0.8);
        const sz = l.s * (0.7 + 0.3 * lu) * (1 + sink * 0.5), a = (1 - sink * 0.9) * fade;
        if (a <= 0.03) return;
        const [ix, iy] = onFloor(l.a, rr * 0.72);
        p.disc(ix, iy + jolt, sz * 0.8, DU[1], 0.35 * a);              // 墙后内尘
        p.disc(x, y, sz * 1.1, DU[1], 0.8 * a);                         // 墙脚暗部
        p.disc(x, y - rise * 0.5, sz, DU[2], 0.85 * a);                 // 墙身
        p.disc(x - sz * 0.25, y - rise - sz * 0.2, sz * 0.7, t < 0.18 ? DU[4] : DU[3], 0.75 * a);   // 受光顶
      };
      lumps.filter((l) => Math.sin(l.a) < 0).forEach(drawLump);
      for (const r of rocks) {
        if (t < r.t0) continue;
        const [x, y] = onFloor(r.a, Math.min(r.d, R));
        if (r.h > 1) p.dot(x, y, DU[0], 0.6 * fade);
        p.rect(x - r.s / 2, y - r.h - r.s / 2, r.s + 0.5, r.s + 0.5, r.dark ? DU[1] : DU[3], fade);
        if (t < 0.1) p.dot(x, y - r.h - r.s / 2, C[4], fade);
      }
      lumps.filter((l) => Math.sin(l.a) >= 0).forEach(drawLump);
      ps.draw(p);
      lights.draw(p);
    },
  };
}
