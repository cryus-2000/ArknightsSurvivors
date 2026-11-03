// 水月精二「深蓝之籽」小水母（claude/pixelfx-ul-mizuki-claude，开关 fx/px_unleashed；召唤物特效归召唤者，§11.2 #5）：原点 = 水母伞心。
// 原作没有这只水母（本作精二机制）；造型取她帽子上的水母纹样和原作 buff_01 的暗芯淡蓝。颜色 = 立绘宝蓝 → 淡紫。
// move：idle（身后常驻：伞盖一张一缩、三根丝须飘，循环 0.8 秒）/ dart（飞向敌人：伞盖压扁前冲、丝须拖成直线，循环 0.4 秒，原点朝 +x）/
//       sting（蜇到：丝须往前一甩缠上去、淡紫小水花，一次性 0.45 秒）。
// 只在精二出现，不分档；队友版余韵短。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise, hex } from "../../core/index.js";
import { MZ } from "./mizuki-lib.js";

export const meta = {
  name: "Mizuki blue seed jellyfish",
  desc: "A small bell jellyfish: idle pulse with drifting threads, a streamlined dart, and a sting that lashes its threads forward.",
  tags: ["summon", "jellyfish", "water", "topdown"],
  size: [64, 64],
  origin: [32, 30],
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: MZ.blue, quick: 0, move: "sting", spray: 0, layer: "all", seed: 4 },   // spray：蜇到时外甩的小水花（§14.7 缺省 0）
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), mv = o.move || "idle", core = o.layer !== "deco", deco = o.layer !== "core", quick = +o.quick > 0;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]], haze: C[4] }), lights = new Lights();
  const LAV = hex(MZ.lav), INK = hex(MZ.ink), RIM = hex("#e8e2ff"), BELL = [hex("#2a2f8a"), hex("#4458c8"), hex("#7a84f0"), hex("#b9a8ff")];
  const LOOP = mv === "idle" ? 0.8 : mv === "dart" ? 0.4 : 0;
  let t = 0.02, hit = false;

  // 伞盖：上半椭圆，外缘噪声小褶；sx / sy 拉伸（dart 压扁前冲），k 透明度
  function bell(p, cx, cy, rx, ry, k) {
    p.shade(cx - rx - 2, cy - ry - 2, cx + rx + 2, cy + 3, (x, y, out) => {
      const dx = (x - cx) / rx, dy = (y - cy) / ry, a = Math.atan2(dy, dx);
      const rr = 1 + 0.12 * noise(a * 5, o.seed + 3);
      const d = Math.hypot(dx, dy);
      if (dy > 0.15 + 0.12 * noise(dx * 6, o.seed + 9) || d > rr) return;   // 下缘不规整（伞缘小褶）
      if (d > rr - 0.2 || dy > 0.02) { out.c = d > rr - 0.12 ? INK : RIM; out.a = k; return; }   // 1 格描边 + 亮缘
      const q = clamp(1 - d);
      out.c = BELL[clamp(Math.round(q * 1.5 + (dy < -0.4 ? 1 : 0) + 0.3 * noise(x * 0.6, y * 0.6)), 0, 3)];
      out.a = k;   // 伞身用色阶表现通透（半透明会抖成网点）
    });
    if (core) { p.px(cx - rx * 0.35, cy - ry * 0.55, hex("#ffffff")); p.px(cx - rx * 0.35 + 1, cy - ry * 0.55, RIM); }   // 高光
  }
  function threads(p, cx, cy, dir, len, sway, k, n) {   // 丝须：从伞缘垂下（dir 方向），1 格宽，尾部淡
    for (let i = 0; i < n; i++) {
      const ox = (i - (n - 1) / 2) * 2.4, ph = i * 1.7;
      for (let d = 0; d < len; d += 0.6) {
        const w = Math.sin(d * 0.5 + sway + ph) * d / len * 2.2;
        const x = cx + ox + dir[0] * d - dir[1] * w, y = cy + 1 + dir[1] * d + dir[0] * w;
        p.dot(x, y, d > len * 0.7 ? C[4] : i === 1 ? LAV : C[5], k * (1 - d / len * 0.5));
      }
    }
  }
  return {
    update(dt) {
      t += dt;
      if (mv === "sting" && !hit && t >= 0.08) {
        hit = true;
        for (let k = 0; k < (+o.spray > 0 ? 9 : 0); k++) {
          const a = Rg.range(-0.9, 0.9), v = Rg.range(40, 110);
          ps.spawn(k % 3 ? P.MOTE : P.SPARK, 10, 0, Math.cos(a) * v, Math.sin(a) * v - 20, Rg.range(0.2, 0.4) * (quick ? 0.6 : 1), k % 3 === 0 ? MZ.lav : C[6], 0.8);
        }
        if (deco) lights.add(10, 0, 16, MZ.lav, 0.7, 0.2);
      }
      if (mv === "idle" && deco && Rg.chance(0.12)) ps.spawn(P.STAR, Rg.range(-5, 5), Rg.range(-4, 2), 0, -Rg.range(6, 12), 0.4, Rg.chance(0.5) ? MZ.lav : C[6], 0.8);
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) { if (deco) ps.draw(p, "back"); },
    draw(p) {
      if (mv === "idle") {   // 一张一缩（按循环相位）
        const ph = TAU * t / LOOP, pulse = Math.sin(ph);
        if (deco) p.glow(0, -2, 10, LAV, 0.18 + 0.06 * pulse);
        if (core) { threads(p, 0, 0, [0, 1], 12 + 2 * pulse, ph, 0.9, 3); bell(p, 0, -1 - pulse * 0.6, 7 + 0.8 * pulse, 6.5 - 0.7 * pulse, 1); }
      } else if (mv === "dart") {   // 压扁前冲：伞盖朝 +x，丝须往 -x 拖直
        const ph = TAU * t / LOOP;
        if (deco) p.glow(0, 0, 9, LAV, 0.2);
        if (core) {
          threads(p, -3, -1, [-1, 0], 14, ph * 2, 0.85, 3);
          p.shade(-6, -5, 7, 5, (x, y, out) => {   // 侧看伞盖：朝前的子弹形
            const dx = x / 6.5, dy = y / 4.2;
            if (dx < -0.5 || dx * dx * (dx > 0 ? 1 : 0.4) + dy * dy > 1) return;
            const e = dx * dx * (dx > 0 ? 1 : 0.4) + dy * dy;
            out.c = e > 0.75 ? INK : e > 0.5 ? RIM : BELL[clamp(Math.round(2 - dy * 1.5), 0, 3)];
          });
          p.px(3, -2, hex("#ffffff"));
        }
      } else {   // sting：伞盖收拢、丝须往前一甩缠上
        const k = 1 - smooth(0.2, 0.45 * (quick ? 0.7 : 1), t), lash = ease.outCubic(clamp(t / 0.1));
        if (core && k > 0) {
          bell(p, -6, -1, 5.5, 4.5 + lash, k);
          for (let i = 0; i < 3; i++) for (let d = 0; d < 16 * lash; d += 0.6) {
            const w = Math.sin(d * 0.6 + i * 2) * 1.6 * (1 - lash * 0.5);
            p.dot(-3 + d, -1 + (i - 1) * 1.6 + w, d > 12 ? LAV : C[6], k);
          }
        }
        if (deco) { lights.draw(p); }
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
