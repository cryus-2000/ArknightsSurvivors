// 塞雷娅三技能「钙质化」开场（docs/229 §9 D 组）：原点 = 队长脚底。替换旧 fx_holy_pillar_amber（1x 放大 3 倍）+ fx_circle_amber（放大 6 倍）。
// 地面一圈不规整的钙晶裂口（透视椭圆 sy 0.55），晶刺长短、间距都随机，首帧一道暖白光柱爆亮后冷却成琥珀，碎晶屑落地。
import { Particles, Bits, B, Lights, P, Rng, fit, clamp, ease, TAU, noise, crystal } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Saria calcify",
  desc: "A ragged ring of amber calcite bursts from the floor round the caster: a warm white column flashes, uneven shards jut up at random spacing, cool to amber, crack and drop grit.",
  tags: ["earth", "crystal", "ground", "buff", "one-shot"],
  size: [128, 112],
  origin: [64, 72],
  duration: 0.6,
  loop: false,
  fps: 20,
  bg: "ground",
  options: { palette: ["#06142a", ...OP.saria], radius: 44, seed: 11 },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), R0 = o.radius;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5], C[3]] });
  const bits = new Bits({ ground: () => 6 }), lights = new Lights();
  lights.add(0, -16, 44, C[5], 0.5, 0.3);
  // 晶刺：沿椭圆不等距
  const shards = [];
  for (let a = Rg.range(0, 0.5); a < TAU - 0.15; a += Rg.range(0.32, 0.75)) {
    const rr = R0 * Rg.range(0.78, 1.0);
    shards.push({ a, x: Math.cos(a) * rr, y: Math.sin(a) * rr * SY, h: Rg.range(10, 22) * (Math.sin(a) > 0 ? 1 : 0.75), w: Rg.range(4, 7), lean: Rg.range(-0.35, 0.35) + Math.cos(a) * 0.3, d: Rg.range(0, 0.06) });
  }
  shards.sort((p, q) => p.y - q.y);
  let t = 0, cracked = false;
  const crack = (p, k) => {
    // 不规整裂口：半径按噪声起伏，近半圈亮、远半圈暗
    for (let a = 0; a < TAU; a += 0.02) {
      const r = R0 * (0.92 + 0.12 * noise(a * 3, o.seed)) + 1.5 * noise(a * 17, o.seed + 3);
      const x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
      const ci = clamp(Math.round(6 - k * 4 - (Math.sin(a) < 0 ? 1 : 0)), 1, 7);
      const al = clamp(1.15 - k * 1.25, 0, 1);
      if (al > 0) { p.blend(x, y, C[ci], al); p.blend(x * 0.95, y * 0.95, C[Math.max(1, ci - 2)], al * 0.7); }
    }
  };
  return {
    update(dt) {
      t += dt;
      if (!cracked && t > 0.12) {
        cracked = true;
        for (const s of shards) if (Rg.chance(0.6))
          for (let i = 0; i < 2; i++) bits.add({ kind: B.SHARD, x: s.x, y: s.y - s.h * 0.6, vx: Rg.range(-40, 40) + s.x, vy: Rg.range(-90, -40), a: Rg.range(0, 3), va: Rg.range(-12, 12), s: Rg.range(1, 2), c: C[Rg.int(4, 6)], g: 520, life: Rg.range(0.25, 0.4) });
        for (let i = 0; i < 10; i++) {
          const a = Rg.range(0, TAU), r = R0 * Rg.range(0.5, 1);
          ps.spawn(P.DUST, Math.cos(a) * r, Math.sin(a) * r * SY, Math.cos(a) * 20, Math.sin(a) * 8 - 6, Rg.range(0.25, 0.4), C[2], Rg.range(2, 4));
        }
      }
      for (const s of shards) if (!s.broke && t - s.d > 0.32) {
        s.broke = true;
        for (let i = 0; i < 2; i++) bits.add({ kind: B.SHARD, x: s.x + Rg.range(-2, 2), y: s.y - s.h * Rg.range(0.3, 0.7), vx: Rg.range(-30, 30), vy: Rg.range(-60, -20), a: Rg.range(0, 3), va: Rg.range(-10, 10), s: Rg.range(1, 1.8), c: C[Rg.int(3, 5)], g: 480, life: Rg.range(0.12, 0.2) });
      }
      ps.update(dt); bits.update(dt); lights.update(dt);
    },
    drawBack(p) {
      const k = clamp(t / 0.5);
      crack(p, k);
      for (const s of shards) if (s.y < 0) drawShard(p, s);
    },
    draw(p) {
      // 首帧光柱：暖白，0.05 s 后降阶、0.2 s 收完；宽度按噪声起伏不规整
      const u = t / 0.2;
      if (u < 1) {
        const ci = clamp(7 - Math.floor(t / 0.05), 3, 7), H = 70 * (1 - u * 0.4);
        for (let y = -H; y <= 0; y++) {
          const w = (5 + 3 * noise(y * 0.15, o.seed + 9)) * (1 - u) * (0.5 + 0.5 * (y + H) / H);
          if (w > 0.4) for (let x = -w; x <= w; x++) p.blend(x, y, C[Math.abs(x) < w * 0.4 ? ci : Math.max(2, ci - 2)], (1 - u) * (0.35 + 0.65 * (y + H) / H));
        }
        p.glow(0, -10, 30, C[6], 0.35 * (1 - u));
      }
      for (const s of shards) if (s.y >= 0) drawShard(p, s);
      bits.draw(p); ps.draw(p); lights.draw(p);
    },
  };
  function drawShard(p, s) {
    const u = t - s.d;
    if (u <= 0) return;
    const grow = ease.outBack(clamp(u / 0.08)), fade = 1 - clamp((u - 0.32) / 0.2);
    if (fade <= 0) return;
    const hot = clamp(1 - u / 0.25);
    const ramp = hot > 0.4 ? C.slice(1, 8) : C.slice(0, 7);
    crystal(p, s.x, s.y, s.h * grow * Math.pow(fade, 0.8), s.w * (0.5 + 0.5 * fade), s.lean, ramp, { a: 1, white: hot > 0.9, glint: hot > 0.4 ? 1 - hot : -1 });
  }
}
