// 流明 S3「灯火不灭」开启（pixelfx 放开版，docs/242；开关 fx/px_unleashed）：原点 = 队长脚底（灯塔立起的位置）。
// 照原作 lumen_skill_03_start_02 + buff_02（提灯处爆出一颗横长的四芒灯光 star_03，身边几道弧形水流 lumen_08 往上扫）：
// 灯高处（-48）一颗四芒灯光：横芒长、竖芒短、斜向两对小芒，首帧白、第 2 帧降一档，0.4 s 收；三道 1–2 像素的弧形水流从脚边绕着往上扫开；
// 水流甩下成组的水珠。不画圆光、不画外扩环。只有 E2（精二解锁）。
// 分层：core = 四芒灯光、水流弧；deco = 灯光外的淡光、水珠、上飘光点。只用钢蓝 7 阶。
import { Particles, P, Rng, fit, clamp, smooth, ease, TAU } from "../../core/index.js";

export const meta = {
  name: "Lumen lantern undying start unleashed",
  desc: "A long four-pointed lamp flare bursts at lantern height while three thin arcs of water sweep up around the target.",
  tags: ["water", "light", "buff", "one-shot"],
  size: [136, 128],
  origin: [68, 108],
  duration: 0.9,
  loop: false,
  fps: 20,
  bg: "dark",
  options: { palette: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"], layer: "all", quick: 0, seed: 3 },
};

export function create(o) {
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), q = o.quick ? 0.6 : 1;
  const LY = -48;
  const arcs = [];
  for (let i = 0; i < 3; i++) arcs.push({ a0: Rg.range(0, TAU), sw: Rg.range(2.2, 3.4) * (i % 2 ? 1 : -1), rx: Rg.range(16, 26), h: Rg.range(50, 80), d: i * 0.06 + Rg.range(0, 0.04) });
  const ps = new Particles({ rng: Rg, ground: () => 1e9 });
  for (let g = 0; g < 3; g++) {
    const a = Rg.range(0, TAU), x = Math.cos(a) * 20, y = -Rg.range(20, 50);
    for (let k = 0; k < Rg.int(2, 3); k++) ps.spawn(P.FLAKE, x + k, y, Math.cos(a) * 30, -20 + k * 6, Rg.range(0.3, 0.45) * q + 0.1, C[5], 1, 0.15 + g * 0.05);
  }
  for (let i = 0; i < 5; i++) ps.spawn(P.MOTE, Rg.range(-20, 20), Rg.range(-30, 0), 0, Rg.range(-30, -15), Rg.range(0.5, 0.8) * q, C[5], 0.6, 0.25 + Rg.range(0, 0.3));
  let t = 0;
  const arcPt = (a, u) => { const an = a.a0 + a.sw * u; return [Math.cos(an) * a.rx * (1 - 0.3 * u), -u * a.h + Math.sin(an) * a.rx * 0.35, Math.sin(an)]; };
  return {
    update(dt) { t += dt; ps.update(dt); ps.list.forEach((p) => p.k === P.FLAKE && (p.vy += 180 * dt)); },
    drawBack(p) {
      if (deco && t < 0.45) p.glow(0, LY, 16, C[4], 0.35 * (1 - t / 0.45));
    },
    draw(p) {
      if (core) {
        // 四芒灯光：0.4 s 收；首帧白
        const u = clamp(t / (0.4 * q + 0.1));
        if (u < 1) {
          const k = 1 - ease.inQuad(u), rays = [[1, 0, 44], [-1, 0, 44], [0, 1, 16], [0, -1, 22], [0.7, 0.7, 7], [-0.7, 0.7, 7], [0.7, -0.7, 9], [-0.7, -0.7, 9]];
          for (const [dx, dy, L] of rays) {
            const len = L * k;
            for (let s = 0; s <= len; s += 0.5) {
              const v = s / Math.max(len, 1);
              p.blend(dx * s, LY + dy * s, t < 0.05 ? (v < 0.7 ? C[6] : C[5]) : v < 0.3 ? C[6] : v < 0.7 ? C[5] : C[4], 1 - v * 0.6);   // blend：渐隐不出抖点
            }
          }
        }
        // 弧形水流：头部沿螺旋往上扫，尾巴跟着收
        for (const a of arcs) {
          const h = ease.outCubic(clamp((t - a.d) / 0.3)), tl = clamp((t - a.d - 0.15) / (0.35 * q));
          for (let w = tl; w <= h; w += 0.008) {
            const [x, y, z] = arcPt(a, w), v = (w - tl) / Math.max(h - tl, 0.01);
            p.dot(x, y, z < -0.3 ? C[3] : v > 0.8 ? C[6] : C[5], z < -0.3 ? 0.7 : 1);
            if (v > 0.5 && z >= -0.3) p.dot(x, y + 1, C[4], 0.8);
          }
        }
      }
      if (deco) ps.draw(p, "front");
    },
  };
}
