// 推进之王砸地（docs/229 §9 D 组）：原点 = 落点（地面）。radius = 判定半径 ÷ 2（1x 像素）。
// 二技能跃空锤落地（radius 55）与三技能碎颅每一锤（radius 29）共用：替换程序冲击环 + 地裂。不画火（10-14 用户删过落地火焰）。
// 首帧落点爆亮，不规整分叉裂网向外窜开、由芯往外冷却成暗金，周围隆起一圈不连续的尘墙，碎石翻滚落地。
import { Particles, Bits, B, Lights, P, Rng, fit, clamp, ease, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Siege slam",
  desc: "A hammer lands: the floor flashes white, a ragged forking crack web shoots out and cools to dark gold, an uneven dust wall heaves up and rock chips tumble.",
  tags: ["earth", "impact", "ground", "hammer", "one-shot"],
  size: [144, 104],
  origin: [72, 62],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "ground",
  options: { palette: [...OP.siege], radius: 55, seed: 21 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R0 = o.radius, big = R0 > 40;
  const ps = new Particles({ rng: Rg, ground: (x) => 4, sparks: [C[7], C[6], C[5], C[3]] });
  const bits = new Bits({ ground: () => 5 }), lights = new Lights();
  lights.add(0, -4, R0 * 0.9, C[6], 0.55, 0.22);
  // 裂网：主裂纹不等角、不等长，沿途随机分叉；每段记下离落点的路程，用来按时间窜开、按路程冷却
  const segs = [];
  const grow = (x, y, a, len, w, d0, depth) => {
    let px = x, py = y, d = d0;
    const step = 2.2;
    for (let s = 0; s < len; s += step) {
      a += Rg.range(-0.45, 0.45);
      const nx = px + Math.cos(a) * step, ny = py + Math.sin(a) * step;
      segs.push({ x0: px, y0: py, x1: nx, y1: ny, d, w: w * (1 - s / len * 0.6) });
      px = nx; py = ny; d += step;
      if (depth < 2 && Rg.chance(0.07)) grow(px, py, a + Rg.sign() * Rg.range(0.5, 1.1), len * Rg.range(0.3, 0.5), w * 0.6, d, depth + 1);
    }
  };
  for (let a = Rg.range(0, 1); a < TAU - 0.3; a += Rg.range(0.55, 1.3)) grow(0, 0, a, R0 * Rg.range(0.55, 1.0), big ? 2 : 1.4, 0, 0);
  const RUN = big ? 0.09 : 0.06;
  // 尘浪（11-03 用户嫌圆团烟尘怪）：沿外圈一段段不连续的贴地尘墙，往外推、顶边往外卷，越往后越矮越淡
  const waves = [];
  for (let a = Rg.range(0, 0.5); a < TAU - 0.2; ) {
    const len = Rg.range(0.35, 1.0);
    waves.push({ a0: a, a1: a + len, h: R0 * Rg.range(0.24, 0.42), r: Rg.range(0.85, 1.05), seed: Rg.range(0, 99), d: Rg.range(0, 0.04) });
    a += len + Rg.range(0.15, 0.6);
  }
  const DUSTC = fit(["#4a3f30", "#6e5e46", "#937e5c", "#bba57c"], 4);   // fit 转成颜色数值（blend 不认十六进制字符串）   // 裂纹窜到最远的时间
  let t = 0, burst = false;
  return {
    update(dt) {
      t += dt;
      if (!burst) {
        burst = true;
        const nChunk = big ? 9 : 5;
        for (let i = 0; i < nChunk; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(40, 110) * (big ? 1 : 0.7);
          bits.add({ kind: B.CHUNK, ramp: [C[0], C[1], C[2], C[3], C[4]], x: Rg.range(-4, 4), y: Rg.range(-2, 2), vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * SY - Rg.range(60, 140), a: Rg.range(0, 3), va: Rg.range(-14, 14), s: Rg.range(1.2, 2.4), c: C[Rg.int(2, 4)], g: 0.6, life: Rg.range(0.3, 0.45) });
        }
        for (let i = 0; i < (big ? 10 : 6); i++) {
          const a = Rg.range(-Math.PI, 0), sp = Rg.range(90, 220);
          ps.spawn(P.SPARK, 0, -2, Math.cos(a) * sp, Math.sin(a) * sp * 0.7, Rg.range(0.08, 0.2));
        }
        }
      ps.update(dt); bits.update(dt); lights.update(dt);
    },
    drawBack(p) {
      const reach = R0 * 1.05 * ease.outQuart(clamp(t / RUN)), fade = 1 - clamp((t - 0.25) / 0.25);
      if (fade <= 0) {   // 余韵：冷掉的裂网半透明留在地上慢慢淡（alpha ≤ 0.35）
        const k = 0.35 * (1 - clamp((t - 0.5) / 0.38));
        if (k > 0) for (const s of segs) { p.blend(s.x0, s.y0 * SY, C[2], k); p.blend((s.x0 + s.x1) / 2, (s.y0 + s.y1) / 2 * SY, C[2], k); }
        return;
      }
      for (const s of segs) {
        if (s.d > reach) continue;
        const age = t - (s.d / (R0 * 1.05)) * RUN;   // 这一段裂开了多久
        const ci = clamp(Math.round(6 + (t < 0.03 ? 1 : 0) - age / 0.05 - s.d / R0 * 1.5), 1, 7);
        const al = fade * (s.d > reach - 3 ? 0.6 : 1);
        p.line(s.x0, s.y0 * SY, s.x1, s.y1 * SY, C[ci], 1);
        if (s.w > 1.6 && ci > 2) p.line(s.x0, s.y0 * SY + 1, s.x1, s.y1 * SY + 1, C[Math.max(1, ci - 3)], al);
      }
    },
    draw(p) {
      // 落点爆亮：首帧白芯，之后每 0.05 s 降一阶
      if (t < 0.15) {
        const ci = clamp(7 - Math.floor(t / 0.05) * 2, 3, 7), rr = R0 * (0.35 + t * 2);
        for (let y = -rr * SY; y <= rr * SY; y++)
          for (let x = -rr; x <= rr; x++) {
            const q = Math.hypot(x, y / SY) / (rr * (0.82 + 0.25 * noise(Math.atan2(y / SY, x) * 2.5, o.seed)));
            if (q > 1) continue;
            if (t < 0.03 && q < 0.75) p.px(x, y, C[q < 0.2 ? 7 : q < 0.45 ? 6 : 5]);   // 首帧实心爆亮，白只在芯
            else p.blend(x, y, C[q < 0.4 ? ci : Math.max(2, ci - 2)], (1 - t / 0.15) * (1 - q * 0.6));
          }
        p.glow(0, -2, R0 * 0.6, C[5], 0.3 * (1 - t / 0.15));
      }
      for (const w of waves) {
        const u = clamp((t - w.d) / 0.75);
        if (u <= 0 || u >= 1) continue;
        const rr = R0 * w.r * (0.5 + 0.6 * ease.outCubic(clamp(u * 2.2))), al = 0.75 * (1 - u) * (1 - u * 0.6);
        for (let a = w.a0; a < w.a1; a += 0.022) {
          const e = (a - w.a0) / (w.a1 - w.a0), env = Math.sin(Math.PI * e);   // 段两头矮
          const hh = w.h * env * (1 - u * 0.7) * (0.55 + 0.45 * noise(a * 6, w.seed + u * 3));
          const bx = Math.cos(a) * rr, by = Math.sin(a) * rr * SY, ox = Math.cos(a), oy = Math.sin(a) * SY;
          for (let k = 0; k < hh; k++) {
            const q = k / Math.max(1, hh), curl = q * q * hh * 0.5;   // 顶边往外卷
            p.blend(bx + ox * curl, by + oy * curl - k, DUSTC[q < 0.35 ? 1 : q < 0.8 ? 2 : 3], al * (q < 0.85 ? 1 : 0.6));
          }
        }
      }
      bits.draw(p); ps.draw(p); lights.draw(p);
    },
  };
}
