// 水月终结技「水母群一起炸开」（设计已定稿 10-31，只改画风；claude/pixelfx-ul-mizuki-claude，开关 fx/px_unleashed）：原点 = 伞心。
// float：大水母浮游（伞盖一张一缩、两条褶边口腕 + 细丝须飘、伞内淡紫荧光斑，循环 1 秒）；
// burst：一起炸开那一下（伞盖先鼓胀白热一帧 → 碎成伞片和水珠顺着各自方向迸开、丝须断开下坠、淡紫光点慢慢上飘散去，约 1.4 秒）。
// 不画往外扩散的冲击环（用户 11-04）；终结技不分档，按 E2 全量。颜色 = 立绘宝蓝 → 淡紫。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise, hex } from "../../core/index.js";
import { MZ } from "./mizuki-lib.js";

export const meta = {
  name: "Mizuki ult jellyfish",
  desc: "A large glowing jellyfish drifting with frilled arms, and the burst where its bell swells white and shatters into shards, droplets and rising motes.",
  tags: ["ult", "jellyfish", "water", "topdown"],
  size: [180, 200],
  origin: [90, 80],
  duration: 1.4,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: MZ.blue, move: "burst", layer: "all", seed: 6 },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), mv = o.move || "float", core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]], haze: C[4] }), lights = new Lights();
  const LAV = hex(MZ.lav), INK = hex(MZ.ink), RIM = hex("#e8e2ff"), WHITE = hex("#ffffff");
  const BELL = [hex("#1e2470"), hex("#2f40a8"), hex("#4f66d8"), hex("#7f8cf2"), hex("#b9a8ff")];
  const LOOP = 1.0, RX = 20, RY = 15;
  const spots = [];   // 伞内荧光斑：不等距
  for (let i = 0; i < 7; i++) spots.push([Rg.range(-0.7, 0.7) * RX, -Rg.range(0.25, 0.8) * RY, Rg.range(0, TAU)]);
  const shards = [];  // burst：伞片
  let t = 0.02, popped = false;

  function bell(p, cx, cy, rx, ry, hot) {
    p.shade(cx - rx - 2, cy - ry - 2, cx + rx + 2, cy + 5, (x, y, out) => {
      const dx = (x - cx) / rx, dy = (y - cy) / ry, a = Math.atan2(dy, dx), d = Math.hypot(dx, dy);
      const rr = 1 + 0.08 * noise(a * 4, o.seed + 3);
      if (dy > 0.12 + 0.18 * Math.abs(noise(dx * 9, o.seed + 9)) || d > rr) return;   // 下缘一圈不规整的褶
      if (d > rr - 0.07) { out.c = INK; return; }
      if (d > rr - 0.16 || dy > 0.05) { out.c = hot > 0.5 ? WHITE : RIM; return; }
      out.c = hot > 0.9 ? WHITE : BELL[clamp(Math.round((1 - d) * 2.4 + (dy < -0.5 ? 1 : 0) + 0.5 * noise(x * 0.4, o.seed + Math.floor(y)) + hot * 2), 0, 4)];
    });
    if (hot < 0.9) for (const [sx, sy, ph] of spots) {   // 荧光斑
      const k = 0.6 + 0.4 * Math.sin(TAU * t / LOOP + ph);
      p.px(cx + sx, cy + sy, k > 0.75 ? WHITE : LAV);
      if (k > 0.6) p.px(cx + sx + 1, cy + sy, LAV);
      if (deco) p.glow(cx + sx, cy + sy, 5, LAV, 0.12 * k);
    }
  }
  function arms(p, cx, cy, ph, len, k) {   // 两条褶边口腕（2 格宽、带淡紫褶边）+ 五根细丝须
    for (let i = 0; i < 2; i++) {
      const ox = (i ? 4 : -4);
      for (let d = 0; d < len * 0.75; d += 0.5) {
        const w = Math.sin(d * 0.22 + ph + i * 2.2) * (1.5 + d * 0.12);
        const x = cx + ox + w, y = cy + 2 + d;
        p.px(x, y, C[4]); p.px(x + 1, y, d % 3 < 1 ? LAV : C[3]);
      }
    }
    for (let i = 0; i < 5; i++) {
      const ox = (i - 2) * (RX * 0.38) + noise(i * 3.3, o.seed + 13) * 2, ph2 = i * 1.3;
      for (let d = 0; d < len * k * (0.8 + 0.25 * noise(i * 1.9, o.seed + 17)); d += 0.6) {
        const w = Math.sin(d * 0.3 + ph + ph2) * d / len * 4;
        p.dot(cx + ox + w, cy + 3 + d, d > len * 0.65 ? C[3] : C[5], 1 - d / len * 0.5);
      }
    }
  }
  return {
    update(dt) {
      t += dt;
      if (mv === "float" && deco && Rg.chance(0.2)) ps.spawn(P.STAR, Rg.range(-RX, RX) * 0.6, Rg.range(-RY, 0), 0, -Rg.range(8, 18), 0.6, Rg.chance(0.5) ? MZ.lav : C[6], 0.9);
      if (mv === "burst" && !popped && t >= 0.07) {
        popped = true;
        for (let i = 0; i < 16; i++) {   // 伞片：伞盖上各处碎下来，顺着自己所在方向飞（方向抖动、速度不一，不成放射纹）
          const a = -Math.PI + Rg.range(0, Math.PI) + Rg.range(-0.25, 0.25), r = Rg.range(0.3, 1) * RX, v = Rg.range(60, 170);
          shards.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * RY / RX, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.8 - Rg.range(0, 40), s: Rg.range(1.5, 3.2), c: Rg.int(1, 4), rot: Rg.range(0, TAU) });
        }
        for (let k = 0; k < 40; k++) {   // 水珠
          const a = Rg.range(0, TAU), v = Rg.range(50, 220);
          ps.spawn(k % 4 ? P.MOTE : P.SPARK, Math.cos(a) * 6, Math.sin(a) * 4 - 6, Math.cos(a) * v, Math.sin(a) * v * 0.8 - 30, Rg.range(0.35, 0.8), k % 3 === 0 ? MZ.lav : C[5 + Rg.int(0, 2)], Rg.range(0.7, 1.3));
        }
        for (let k = 0; k < 22; k++) ps.spawn(P.STAR, Rg.range(-RX, RX), Rg.range(-RY, RY * 0.5), Rg.range(-12, 12), -Rg.range(12, 34), Rg.range(0.7, 1.3), Rg.chance(0.6) ? MZ.lav : C[6], Rg.range(0.8, 1.4), Rg.range(0.05, 0.4));   // 淡紫光点慢慢上飘
        if (deco) { lights.add(0, -4, 70, MZ.lav, 0.9, 0.18); lights.add(0, -4, 40, C[6], 0.6, 0.35); }
      }
      for (const s of shards) { s.x += s.vx * dt; s.y += s.vy * dt; s.vy += 160 * dt; s.vx *= 1 - 2.2 * dt; s.rot += 6 * dt; }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) { if (deco) ps.draw(p, "back"); },
    draw(p) {
      if (mv === "float") {
        const ph = TAU * t / LOOP, pulse = Math.sin(ph);
        if (deco) p.glow(0, -6, 30, LAV, 0.16 + 0.05 * pulse);
        if (core) { arms(p, 0, 0, ph, 46 + 3 * pulse, 1); bell(p, 0, -pulse * 1.2, RX + 1.5 * pulse, RY - 1.2 * pulse, 0); }
      } else {
        const sw = ease.outCubic(clamp(t / 0.07));
        if (core && t < 0.08) { arms(p, 0, 0, 0, 46, 1); bell(p, 0, -1, RX * (1 + 0.25 * sw), RY * (1 + 0.3 * sw), t > 0.04 ? 1 : 0.6); }   // 鼓胀 → 白热一帧
        if (core && t >= 0.07) {
          const k = 1 - smooth(0.35, 0.8, t);
          for (const s of shards) if (k > 0) {   // 伞片：小三角碎块，描边 + 色块
            const c = Math.cos(s.rot), sn = Math.sin(s.rot), L = s.s * (0.5 + 0.5 * k);
            for (let u = -L; u <= L; u += 0.5) for (let v = 0; v <= L - Math.abs(u); v += 0.5) {
              const x = s.x + u * c - v * sn, y = s.y + u * sn + v * c;
              p.px(x, y, v > L - Math.abs(u) - 0.6 ? (t < 0.14 ? WHITE : RIM) : BELL[s.c]);
            }
          }
          const fall = smooth(0.07, 1.1, t), kk = 1 - smooth(0.5, 1.1, t);
          if (kk > 0) for (let i = 0; i < 5; i++) {   // 断开的丝须往下坠、越来越短
            const ox = (i - 2) * (RX * 0.38) + noise(i * 2.1, o.seed + 19) * 4, len = 30 * kk;
            for (let d = 0; d < len; d += 0.6) p.dot(ox + Math.sin(d * 0.3 + i + t * 4) * 2, 14 + fall * 30 + d, C[4 + (i % 2)], kk);
          }
        }
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
