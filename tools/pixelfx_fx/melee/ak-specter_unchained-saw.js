// 归溟幽灵鲨「环斩」普攻（docs/229 §3 普攻档）：@2x 帧条，原点 = 本人（seg_specter 在 o.pos 上方 6 px 放），地面透视 sy 0.55。
// 判定半径 102 时游戏按每 1x 像素 2 世界像素画（seg_specter：sc = PX × r ÷ 102），刃圈半径 = 102 × 0.85。
// 一道刃口在 0.1 秒里绕身一整圈：刃头白、身后拖着锯齿刃带，齿的间距和大小都不等；转完刃带从外缘崩成几片碎刃甩出去。只有一圈，不画同心圈。
// 重击（S2 期间）用同一特效换血红色阶（targets_c.json opts.palette，色相 0.99–0.01，避开敌方危险色 0.92–0.98）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS, REACH, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Specter spinning saw",
  desc: "A single blade edge whips a full circle around her on the floor plane, dragging an uneven saw-toothed band that breaks into flung shards.",
  tags: ["melee", "spin", "saw", "topdown", "one-shot"],
  size: [200, 120],
  origin: [100, 60],
  duration: 0.32,   // 主体 + 余韵
  loop: false,
  fps: FPS.basic,
  bg: "dark",
  options: {
    palette: [...OP.specter_unchained],
    radius: 102 * REACH.sweep,
    seed: 8,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[4]] });
  const SPIN = 0.1, BAND = 5.2, W = 9;              // 一圈用时、刃带拖尾长度（弧度）、刃带厚
  // 齿：不等距、不等大
  const teeth = [];
  for (let a = Rg.range(0, 0.3); a < TAU - 0.15; a += Rg.range(0.22, 0.5)) teeth.push({ a, h: Rg.range(2.5, 6.5), w: Rg.range(0.06, 0.13) });
  const a0 = Rg.range(-0.4, 0.4);
  let t = 0.01, broke = false;

  const toothAt = (a) => {
    for (const k of teeth) {
      let d = a - k.a;
      d -= Math.round(d / TAU) * TAU;
      if (d > -k.w && d < 0.02) return k.h * (1 - (d + k.w) / (k.w + 0.02) * 0.2) * clamp((d + k.w) / k.w * 3);   // 齿尖朝转动方向
    }
    return 0;
  };

  function band(p) {
    const head = a0 + TAU * (ease.outQuad(clamp(t / SPIN)) + 0.35 * clamp((t - SPIN) / 0.08)), fade = 1 - smooth(SPIN, 0.17, t);   // 转完一圈后余势再走一小段
    if (fade <= 0) return;
    const B = R + 9;
    p.shade(-B, -B * SY - 1, B, B * SY + 1, (x, y, out) => {
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY);
      let behind = head - a;
      behind -= Math.floor(behind / TAU) * TAU;          // 刃头身后的弧长
      const tail = Math.min(BAND, head - a0);
      if (behind > tail) return;
      const v = behind / BAND, wob = 1.2 * noise(a * 6, o.seed);
      const outer = R + wob + toothAt(a) * (1 - v * 0.5);
      if (r > outer || r < R - W * (1 - v * 0.6) + wob) return;
      const q = (outer - r) / (outer - R + W);
      const hot = t < 0.045 ? 0.8 : 0;   // 白只在刃头芯（近白 ≤ 12%）
      const c = C[7 - clamp(Math.round(v * 4.5 + q * 2.2 + (1 - fade) * 3 - hot + (y < 0 ? 0.6 : 0)), 0, 6)];   // 远半圈暗一点
      if (v > 0.55) p.blend(x, y, c, 0.75 * fade + 0.15);
      else out.c = c;
    });
  }

  // 余韵（≤ 0.15 s）：刃带崩散后沿圈留几粒稀疏碎光，alpha ≤ TAIL_ALPHA；光晕跟着刃头
  const Rt = new Rng(o.seed + 99), res = [];
  for (let a = Rt.range(0, 0.4); a < TAU; a += Rt.range(0.35, 0.9)) res.push({ a, d: Rt.range(0, 0.04), out: Rt.range(2, 8) });
  function tail(p) {
    for (const r of res) {
      const u = (t - SPIN - 0.03 - r.d) / DUR.basicTail;
      if (u < 0 || u >= 1) continue;
      const rr = R + r.out * u;
      p.blend(Math.round(Math.cos(r.a) * rr), Math.round(Math.sin(r.a) * rr * SY), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  function halo(p) {
    const k = 1 - clamp(t / 0.14);
    if (k <= 0) return;
    const a = a0 + TAU * ease.outQuad(clamp(t / SPIN));
    p.glow(Math.cos(a) * R, Math.sin(a) * R * SY, 16, C[5], 0.9 * k);
  }

  return {
    update(dt) {
      t += dt;
      if (!broke && t >= SPIN) {
        broke = true;
        const n = Rg.int(5, 7);
        for (let i = 0; i < n; i++) {
          const a = Rg.range(0, TAU), x = Math.cos(a) * R, y = Math.sin(a) * R * SY, sp = Rg.range(90, 200), da = a + Rg.range(0.6, 1.3);   // 沿切线甩出
          ps.spawn(P.SPARK, x, y, Math.cos(da) * sp, Math.sin(da) * sp * SY, Rg.range(0.05, 0.1));
        }
      }
      ps.update(dt);
    },
    draw(p) {
      band(p);
      halo(p);
      tail(p);
      ps.draw(p);
    },
  };
}
