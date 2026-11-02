// 星熊 S3「力之锯」直线斩（docs/228 §7 试点）：俯视，原点 = 线段中点，正右为斩击方向，游戏里按方向旋转。
import { Particles, Lights, P, Rng, fit, sparkle, clamp, smooth, ease, WHITE } from "../../core/index.js";

export const meta = {
  name: "Hoshiguma saw",
  desc: "Top-down straight rip: a white-hot cut races along the line, its rims serrated like a saw, sparks and grit spray off it and a ragged gouge cools from red to soot.",
  tags: ["melee", "slash", "line", "saw", "topdown", "one-shot"],
  size: [176, 88],
  origin: [88, 44],
  duration: 0.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#1c0406", "#4a0a12", "#8e1424", "#d0283a", "#ff5a4a", "#ffa98a", "#ffe9dc", "#ffffff"],
    sparks: ["#fff3d0", "#ffd27a", "#ff7a3a", "#d0283a"],
    len: 110,
    seed: 5,
  },
};

const RUN = 0.06, HOLD = 0.04, COOL = 0.24;
const hash = (i, s) => { const x = Math.sin(i * 127.1 + s * 311.7) * 43758.5453; return x - Math.floor(x); };

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), L = o.len, X0 = -L / 2, X1 = L / 2;
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: o.sparks }), lights = new Lights();
  // 刀痕中线：小幅不规整起伏
  const wob = (x) => 1.2 * Math.sin(x * 0.21 + o.seed) + 0.8 * Math.sin(x * 0.53 + 2.1);
  // 锯齿：间距 3–9 px 不等，齿高随机
  const edges = [0];
  while (edges[edges.length - 1] < L + 10) edges.push(edges[edges.length - 1] + Rg.range(3, 9));
  const toothAt = (u) => { let k = 0; while (edges[k + 1] <= u) k++; return [k, (u - edges[k]) / (edges[k + 1] - edges[k])]; };
  let t = 0.02, ran = X0, done = false;
  return {
    update(dt) {
      t += dt;
      const head = X0 + L * ease.outQuart(clamp(t / RUN));
      while (ran < head) {
        // 锯口一路向两侧和后方喷火星
        const side = Rg.chance(0.5) ? 1 : -1, sp = Rg.range(120, 320), a = Math.PI + side * Rg.range(0.5, 1.3);
        ps.spawn(P.SPARK, ran, wob(ran) + side * 3, Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.1, 0.28));
        if (Rg.chance(0.35)) ps.spawn(P.GRIT, ran, wob(ran), Rg.range(-40, 10), side * Rg.range(20, 60), Rg.range(0.2, 0.3), C[1], 1);
        if (Rg.chance(0.25)) ps.spawn(P.DUST, ran, wob(ran) + side * 4, Rg.range(-20, 5), side * Rg.range(8, 20), Rg.range(0.2, 0.32), C[1], Rg.range(2, 3.5));
        ran += Rg.range(2.5, 5);
      }
      if (!done && t >= RUN) {
        done = true;
        lights.add(X1, wob(X1), 34, C[5], 0.7, 0.28);
        for (let i = 0; i < 14; i++) {
          const a = Rg.range(-0.9, 0.9), sp = Rg.range(150, 380);
          ps.spawn(P.SPARK, X1, wob(X1), Math.cos(a) * sp, Math.sin(a) * sp, Rg.range(0.12, 0.32));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    draw(p) {
      ps.draw(p, "back");
      const head = X0 + L * ease.outQuart(clamp(t / RUN));
      const cool = smooth(RUN + HOLD, RUN + HOLD + COOL, t);
      // 地面刀痕：深色不规整沟，冷却后变成焦痕再淡出
      const gone = smooth(RUN + HOLD + COOL * 0.4, 0.42, t);
      for (let x = X0; x <= head; x++) {
        const y = wob(x), w = 1 + (hash(x | 0, 3) > 0.7 ? 1 : 0);
        for (let d = -w; d <= w; d++) p.dot(x, y + d, C[cool < 0.5 ? 2 : 1], 1 - gone);
      }
      if (cool < 1) {
        // 斩线主体：中间白热、往外逐级变红，两侧锯齿刃口
        const W = 7 * (1 - cool * 0.7);
        for (let x = X0; x <= head; x++) {
          const u = (x - X0) / L, behind = (head - x) / L;
          const taper = Math.min(1, u / 0.12) * Math.min(1, (X1 - x + 2) / 6);
          const [k, f] = toothAt(x - X0);
          const tooth = f * (1 + 3.2 * hash(k, o.seed));   // 单向锯齿，齿高不一
          for (const side of [-1, 1]) {
            const ext = (W + tooth * (side > 0 ? 1 : 0.45) - (side < 0 ? hash(k, 9) * 1.5 : 0)) * taper;
            for (let d = 0; d <= ext; d++) {
              const q = d / Math.max(ext, 1), heat = q + cool * 1.6 + behind * 0.8;
              const ci = clamp(Math.round(7 - heat * 4.2), 0, 7);
              if (ci < 1) continue;
              p.dot(x, wob(x) + side * d, C[ci], q > 0.85 ? 0.6 : 1);
            }
          }
        }
        p.glowLine(X0, 0, head, 0, 8, C[4], 0.22 * (1 - cool));
      }
      // 刀头一路带光，末端星芒
      if (t < RUN + 0.05) p.glow(head, wob(head), 26, C[5], 0.6);
      const g = t - RUN;
      if (g > 0 && g < 0.2) sparkle(p, X1, wob(X1), 11 * ease.outBack(Math.min(1, g / 0.05)) * (1 - g / 0.2), C[7], C[4], 0.6);
      ps.draw(p, "front");
      lights.draw(p);
    },
  };
}
