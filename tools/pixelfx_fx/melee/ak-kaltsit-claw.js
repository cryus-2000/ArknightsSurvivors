// 凯尔希 · Mon3tr「撕咬」普攻爪痕（docs/229 §3 普攻档）：@2x 帧条，游戏里不随方向转（同旧 fx_mon3tr_claw：斜向撕裂，朝左时水平翻转）。
// 原点 = 爪痕中心（attack.fx along 0.55）。fit [93, 0.85, 1.1]：判定半径 93 时每个 1x 像素 2 世界像素。
// 三道长短、间距、弯度都不一样的爪痕自左下撕向右上，白热芯冷却成 Mon3tr 荧绿，末端崩出几粒碎片。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP, FPS, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Mon3tr rending claw",
  desc: "Three uneven claw rakes tear diagonally up-right: white-hot cores cooling to Mon3tr lime, a few chips flicking off the ends.",
  tags: ["melee", "claw", "slash", "topdown", "one-shot"],
  size: [150, 130],
  origin: [75, 65],
  duration: 0.32,   // 主体 + 余韵
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: [...OP.kaltsit],
    len: 92,
    seed: 3,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const dir = -0.62, ux = Math.cos(dir), uy = Math.sin(dir), nx = -uy, ny = ux;
  // 三道爪痕：横向间距、长度、起始延迟、弯度都随机
  const rakes = [];
  let off = -Rg.range(13, 17);
  for (let i = 0; i < 3; i++) {
    rakes.push({ off, L: o.len * Rg.range(0.62, 1), sh: Rg.range(-8, 8), d: i * Rg.range(0.006, 0.014), bend: Rg.range(-9, 9), w: Rg.range(3.2, 5), sd: Rg.range(0, 40) });
    off += Rg.range(10, 18);
  }
  const RIP = 0.045, LIVE = 0.14;
  let t = 0.012, chipped = false;

  function rake(p, k) {
    const u = t - k.d;
    if (u < 0) return;
    const head = ease.outExpo(clamp(u / RIP)), tail = smooth(RIP * 0.6, LIVE, u), age = clamp(u / LIVE);
    if (tail >= 1) return;
    const n = Math.ceil(k.L);
    for (let i = 0; i <= n; i++) {
      const s = i / n;
      if (s > head || s < tail) continue;
      const along = (s - 0.5) * k.L + k.sh, curve = k.bend * (s - 0.5) * (s - 0.5) * 4 - k.bend;
      const cx = ux * along + nx * (k.off + curve), cy = uy * along + ny * (k.off + curve);
      const taper = Math.pow(Math.sin(Math.PI * (s - tail) / Math.max(0.05, head - tail)), 0.6);
      const w = k.w * taper * (1 - age * 0.5) * (0.85 + 0.3 * noise(s * 9, k.sd));
      for (let d = -w; d <= w; d += 0.5) {
        const q = Math.abs(d) / Math.max(w, 0.5);
        const hot = t < 0.045 ? 0.8 : 0;   // 白只在爪痕芯
        const c = C[7 - clamp(Math.round(q * 3.5 + age * 4.5 + (1 - s) * 0.8 - hot), 0, 6)];
        const x = Math.round(cx + nx * d), y = Math.round(cy + ny * d);
        if (q > 0.7) p.blend(x, y, c, 0.7); else p.px(x, y, c);
      }
    }
  }

  // 余韵（≤ 0.15 s）：爪痕崩完后沿痕留几粒荧绿残光，alpha ≤ TAIL_ALPHA；光晕在每道爪痕中段
  const Rt = new Rng(o.seed + 99), res = [];
  for (const k of rakes) for (let v = Rt.range(0, 0.2); v < 1; v += Rt.range(0.18, 0.35)) res.push({ k, v, d: Rt.range(0, 0.04) });
  function tail(p) {
    for (const r of res) {
      const u = (t - LIVE - r.d) / DUR.basicTail;
      if (u < 0 || u >= 1) continue;
      const along = (r.v - 0.5) * r.k.L + r.k.sh;
      p.blend(Math.round(ux * along + nx * r.k.off), Math.round(uy * along + ny * r.k.off - u * 4), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  function halo(p) {
    const k = 1 - clamp(t / 0.12);
    if (k <= 0) return;
    for (const r of rakes) p.glow(ux * r.sh + nx * r.off, uy * r.sh + ny * r.off, 14, C[5], 0.6 * k);
  }

  return {
    update(dt) {
      t += dt;
      if (!chipped && t >= RIP) {
        chipped = true;
        for (const k of rakes) {
          const along = k.L * 0.5 + k.sh, x = ux * along + nx * k.off, y = uy * along + ny * k.off;
          const m = Rg.int(1, 2);
          for (let i = 0; i < m; i++) {
            const a = dir + Rg.range(-0.6, 0.6), sp = Rg.range(90, 200);
            ps.spawn(P.SPARK, x, y, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.05, 0.1));
          }
        }
      }
      ps.update(dt);
    },
    draw(p) {
      for (const k of rakes) rake(p, k);
      halo(p);
      tail(p);
      ps.draw(p);
    },
  };
}
