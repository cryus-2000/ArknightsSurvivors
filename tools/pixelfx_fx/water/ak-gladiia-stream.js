// 歌蕾蒂娅水流两件（替换 fx_gladiia_pull / fx_gladiia_water_glide）：@2x，游戏 scale 0.9–1.0，正右为朝向（pull 由代码转向区域中心，glide 随跑动方向转）。
// mode "pull"（S3 / 天赋把敌人往里卷）：一条深海水带从后往前抽过去，头部卷起白浪、身后拖细水珠，粗细按噪声起伏，0.4 秒。
// mode "glide"（跑动时脚下水迹，地面层）：脚后拖出两道不等长、不对称的白沫浪线（V 字尾迹），中间一片半透明水面，0.4 秒散开。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Gladiia stream",
  desc: "Pull: a deep-sea water ribbon lashes forward with a curling foam head and trailing droplets. Glide: an asymmetric V wake of foam lines behind her feet.",
  tags: ["water", "stream", "trail", "one-shot"],
  size: [128, 48],
  origin: [64, 24],
  duration: 0.4,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.gladiia],
    mode: "pull",
    seed: 4,
  },
};

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), pull = o.mode === "pull";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[5]] });
  let t = 0, last = -60;

  function ribbon(p) {
    const head = -52 + 110 * ease.outQuart(clamp((t + 0.02) / 0.22)), tail = -60 + 120 * smooth(0.08, 0.36, t);
    if (head - tail < 2) return;
    const seen = new Set();
    for (let x = tail; x <= head; x += 0.5) {
      const v = (x - tail) / (head - tail), yc = 4 * Math.sin(x * 0.06 + 1.1) + 2 * noise(x * 0.08, o.seed);
      const w = (1.5 + 4.5 * Math.pow(v, 1.3)) * (0.8 + 0.4 * (0.5 + 0.5 * noise(x * 0.15, o.seed + 3)));
      for (let d = -w; d <= w; d += 0.5) {
        const px = Math.round(x), py = Math.round(yc + d), k = px * 1000 + py;
        if (seen.has(k)) continue;
        seen.add(k);
        const q = Math.abs(d) / w, topLit = d < 0;
        const ci = clamp(Math.round(2.5 + v * 2.5 + (q > 0.6 && topLit ? 1.5 : 0) + (t < 0.03 ? 2 : 0)), 1, 7);
        p.blend(px, py, C[ci], q > 0.7 ? 0.75 : 0.6);
      }
    }
    // 头部卷浪：往上翻的一小钩
    for (let k = 0; k < 10; k++) {
      const a = -0.4 - k * 0.3, r = 5 - k * 0.3;
      p.blend(Math.round(head - 2 + Math.cos(a) * r), Math.round(-3 + Math.sin(a) * r), C[7], 0.9);
    }
  }

  function wake(p) {
    const u = clamp(t / 0.36), spread = ease.outQuad(u), fade = 1 - smooth(0.18, 0.38, t);
    if (fade <= 0) return;
    const arms = [{ s: -1, L: 44, a: 0.32 }, { s: 1, L: 34, a: 0.24 }];   // 两道不等长、不对称
    for (const m of arms) {
      for (let i = 0; i <= m.L * (0.4 + 0.6 * spread); i++) {
        const x = 6 - i, y = m.s * (i * m.a * (0.6 + 0.6 * spread) + 1.2 * noise(i * 0.3, o.seed + m.s));
        const v = i / m.L;
        p.blend(Math.round(x), Math.round(y), C[clamp(Math.round(7 - v * 3 - (1 - fade) * 2 + (t < 0.03 ? 1 : 0)), 3, 7)], (1 - v * 0.6) * fade);
      }
    }
    for (let x = 4; x > -30 * (0.4 + 0.6 * spread); x--)        // 中间半透明水面
      for (let y = -Math.abs(x) * 0.22; y <= Math.abs(x) * 0.18; y++) p.blend(x, Math.round(y), C[3], 0.3 * fade);
  }

  return {
    update(dt) {
      t += dt;
      if (pull) {
        const head = -52 + 110 * ease.outQuart(clamp((t + 0.02) / 0.22));
        while (last < head - 6 && t < 0.3) {
          last += Rg.range(6, 14);
          ps.spawn(P.FLAKE, last, Rg.range(-6, 6), Rg.range(-40, -10), Rg.range(-30, 30), Rg.range(0.1, 0.2), C[Rg.int(4, 7)], 1.5);
        }
      } else if (t < 0.02) {
        for (let i = 0; i < 4; i++) ps.spawn(P.FLAKE, Rg.range(-4, 4), Rg.range(-3, 3), Rg.range(-60, -20), Rg.range(-25, 25), Rg.range(0.12, 0.22), C[Rg.int(5, 7)], 1.5);
      }
      ps.update(dt);
    },
    draw(p) {
      if (pull) ribbon(p); else wake(p);
      ps.draw(p);
    },
  };
}
