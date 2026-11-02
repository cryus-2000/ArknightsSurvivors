// 凯尔希 · Mon3tr 落地砸击（精一扑击 lunge_r 40 / 精二护主跃击 leap_r 100，替换 fx_mon3tr_slam_ring）：@2x 帧条，地面透视 sy 0.55，原点 = 落点。
// 游戏里 fit = 判定半径 ÷ 2（每个 1x 像素 2 世界像素），帧里裂网外沿 = 判定半径（radius 选项，两档各导一张）。
// 落点首帧白闪；几道不规整、带分叉的荧绿裂口向外撕开（角度、长度、折点都随机），外沿掀起一圈高矮不一的半透明尘墙，碎块向外抛；不画同心圈。
import { Particles, Bits, B, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Mon3tr landing slam",
  desc: "A white flash where Mon3tr lands, ragged forking lime cracks tear outward, an uneven translucent dust wall heaves at the rim and chips fly.",
  tags: ["impact", "slam", "crack", "floor", "topdown", "one-shot"],
  size: [220, 130],
  origin: [110, 66],
  duration: 0.5,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.kaltsit],
    dust: ["#06142a", "#1a2b33", "#33494d", "#5b7372"],
    radius: 100,
    seed: 4,
  },
};

const SY = 0.55, TEAR = 0.1;

export function create(o) {
  const C = fit(o.palette, 8), D = fit(o.dust, 4), Rg = new Rng(o.seed), R = o.radius, s = R / 100;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const bits = new Bits({ ground: () => 1e9 });
  // 裂口：折线路径（不等角、不等长），部分带分叉
  const cracks = [];
  for (let a = Rg.range(0, 0.6); a < TAU - 0.3; a += Rg.range(0.9, 1.7)) {
    const pts = [[0, 0]];
    let x = 0, y = 0, d = a, L = R * Rg.range(0.55, 0.95);
    for (let k = 0, n = Math.ceil(L / (9 * s)); k < n; k++) {
      d += Rg.range(-0.45, 0.45);
      const st = L / n * Rg.range(0.7, 1.3);
      x += Math.cos(d) * st; y += Math.sin(d) * st * SY;
      pts.push([x, y]);
    }
    const die = pts.map(() => Rg.range(0.28, 0.46));   // 每段各自碎掉的时刻（收尾按段崩落，不用透明度抖动淡出）
    const fork = Rg.chance(0.65) ? Rg.int(1, pts.length - 2) : -1;
    const fp = [];
    if (fork > 0) {
      let [fx, fy] = pts[fork], fd = a + Rg.sign() * Rg.range(0.5, 0.9);
      for (let k = 0, n = Rg.int(2, 4); k < n; k++) { fd += Rg.range(-0.4, 0.4); fx += Math.cos(fd) * 8 * s; fy += Math.sin(fd) * 8 * s * SY; fp.push([fx, fy]); }
    }
    cracks.push({ pts, die, fork, fp, w: Rg.range(1.5, 2.6) * Math.max(0.7, s) });
  }
  const wallH = (a) => Math.max(0, -2 + 14 * (0.5 + 0.5 * noise(a * 3.7, o.seed + 3))) * (0.6 + 0.4 * s) * (0.75 + 0.5 * (0.5 + 0.5 * noise(a * 11, o.seed + 8)));
  let t = 0, burst = false;

  function crackDraw(p) {
    const grow = ease.outQuart(clamp((t + 0.03) / TEAR)), cool = clamp((t - 0.03) / 0.3);
    for (const c of cracks) {
      const N = c.pts.length - 1, upto = grow * N;
      const seg = (pts, lim, w0, die) => {
        for (let i = 0; i < Math.min(lim, pts.length - 1); i++) {
          if (t > die[Math.min(i, die.length - 1)]) continue;
          const [x0, y0] = pts[i], [x1, y1] = pts[i + 1], f = Math.min(1, lim - i);
          const ex = x0 + (x1 - x0) * f, ey = y0 + (y1 - y0) * f, w = w0 * (1 - i / (pts.length + 1));
          const heat = clamp(Math.round(7 - cool * 4 - i / N * 2.5 + (t < 0.05 ? 2 : 0)), 1, 7);   // 首帧整条裂口爆亮
          p.beam(x0, y0, ex, ey, Math.max(0.6, w), C[heat]);
          if (w > 1.2) p.beam(x0, y0, ex, ey, 0.6, C[Math.min(7, heat + 1)]);   // 裂口里更亮的芯
        }
      };
      seg(c.pts, upto, c.w, c.die);
      if (c.fork > 0 && upto > c.fork) seg([c.pts[c.fork], ...c.fp], (upto - c.fork) * 1.5, c.w * 0.6, c.die.slice(c.fork));
    }
  }

  function wall(p, far) {
    const u = t - 0.04, rise = ease.outQuart(clamp(u / 0.1)) * (1 - smooth(0.18, 0.42, u));
    if (u < 0 || rise <= 0.02) return;
    const rr = R * (0.88 + 0.12 * clamp(u / 0.3)), step = 0.9 / rr;
    for (let a = 0; a < TAU; a += step) {
      const sn = Math.sin(a);
      if ((sn < 0) !== far) continue;
      const rj = rr * (1 + 0.1 * noise(a * 4.1, o.seed + 6)), x = Math.cos(a) * rj, y = sn * rj * SY, h = wallH(a) * rise;   // 尘墙半径和高度都按噪声起伏，有缺口
      for (let d = 0; d <= h; d += 1) {
        const v = d / Math.max(h, 1);
        p.blend(Math.round(x), Math.round(y - d), v > 0.8 ? D[3] : D[2], (0.55 - v * 0.35) * (far ? 0.8 : 1));
      }
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!burst) {
        burst = true;
        for (let i = 0; i < Math.round(6 * Math.max(0.6, s)); i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(60, 160) * Math.max(0.6, s);
          bits.add({ kind: B.CHUNK, x: 0, y: 0, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * SY - Rg.range(40, 90), a: Rg.range(0, 6), va: Rg.range(-14, 14),
            s: Rg.range(1.5, 3), ramp: [D[1], D[2], D[3]], g: 2.2, drag: 1.5, life: Rg.range(0.25, 0.4) });
        }
        for (let i = 0; i < 6; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(100, 220) * Math.max(0.6, s);
          ps.spawn(P.SPARK, 0, 0, Math.cos(a) * sp, Math.sin(a) * sp * SY - 30, Rg.range(0.08, 0.16));
        }
      }
      ps.update(dt);
      bits.update(dt);
    },
    drawBack(p) {
      wall(p, true);
    },
    draw(p) {
      crackDraw(p);
      if (t < 0.1) {
        const k = t < 0.05 ? 1 : 0.45, rx = (14 + 12 * s) * k;
        p.shade(-rx - 2, -rx * SY - 2, rx + 2, rx * SY + 2, (x, y, out) => {
          const r = Math.hypot(x, y / SY) / rx / (1 + 0.3 * noise(Math.atan2(y, x) * 3, o.seed));
          if (r > 1) return;
          const c = C[clamp(Math.round(7 - r * 2.5 - (1 - k) * 3), 2, 7)];
          if (r > 0.75) p.blend(x, y, c, 0.7); else out.c = c;
        });
      }
      wall(p, false);
      bits.draw(p);
      ps.draw(p);
    },
  };
}
