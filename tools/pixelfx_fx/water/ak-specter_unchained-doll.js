// 归溟幽灵鲨「替身人偶」出现 / 消散（seg_specter 叠在人偶本体帧条上，替换 fx_specter_doll_appear / fx_specter_doll_burst）：@2x，原点 = 人偶身体中心（脚底上方 32 px）。
// mode "appear"（5 帧 = 0.25 秒）：脚下一闪，几缕苍白水流从脚边不等角地螺旋往上收拢到身形里，最后在胸口合成一点白。
// mode "burst"（6 帧 = 0.3 秒）：身形中心一闪，整团水体往外炸成大小不一的水珠和水雾，水珠带重力落下；不用棋盘格淡出（旧版末段就是）。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Specter doll wake",
  desc: "Appear: pale water threads spiral up from the feet and gather into the body. Burst: the body flashes and blows out into uneven droplets and mist that fall.",
  tags: ["water", "spawn", "death", "one-shot"],
  size: [96, 104],
  origin: [48, 52],
  duration: 0.3,
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.specter_unchained],
    mode: "appear",
    seed: 3,
  },
};

const FEET = 32;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), burst = o.mode === "burst";
  const ps = new Particles({ rng: Rg, ground: () => FEET + 2, sparks: [C[7], C[6], C[5], C[4]], haze: C[4] });
  const threads = [];
  for (let a = Rg.range(0, 0.6); a < TAU; a += Rg.range(0.8, 1.6))
    threads.push({ a, r: Rg.range(12, 22), d: Rg.range(0, 0.05), turns: Rg.range(0.6, 1.1) * (Rg.chance(0.5) ? 1 : -1), top: Rg.range(-14, -4) });
  let t = 0, fired = false;
  const DUR = burst ? 0.3 : 0.25;

  function appear(p) {
    if (t >= DUR - 0.02) return;                            // 5 帧后交给人偶本体，末帧为空
    for (const s of threads) {
      const u = clamp((t - s.d) / (DUR - 0.08));
      if (u <= 0) continue;
      const head = ease.inOutQuad(u), tail = Math.max(0, head - 0.45);
      for (let k = 0; k <= 24; k++) {
        const v = tail + (head - tail) * k / 24;
        const ang = s.a + s.turns * TAU * v, rr = s.r * (1 - v * 0.85);
        const x = Math.cos(ang) * rr, y = FEET - (FEET - s.top) * v + Math.sin(ang) * rr * 0.35;
        const q = k / 24;
        p.blend(Math.round(x), Math.round(y), C[clamp(Math.round(4 + q * 3 - (1 - u) * 1.5), 2, 7)], 0.5 + q * 0.45);
      }
    }
    if (t < 0.03) p.disc(0, FEET, 6, C[7], 0.9);              // 首帧脚下一闪
    if (t > DUR - 0.09) p.disc(0, -6, 2.5, C[7], 1);   // 合成：胸口一点白
  }

  return {
    update(dt) {
      t += dt;
      if (burst && !fired) {
        fired = true;
        for (let i = 0; i < 16; i++) {
          const a = Rg.range(0, TAU), sp = Rg.range(50, 150), x = Rg.range(-8, 8), y = Rg.range(-22, 22);
          ps.spawn(i % 3 === 0 ? P.VAPOUR : P.SPARK, x, y, Math.cos(a) * sp, Math.sin(a) * sp * 0.8 - 40, Rg.range(0.15, 0.26), C[Rg.int(4, 7)], Rg.range(1.5, 3.5));
        }
      }
      ps.update(dt);
    },
    draw(p) {
      if (!burst) return appear(p);
      if (t < 0.03) {                                         // 首帧：身形一团白
        p.shade(-12, -26, 12, 26, (x, y, out) => {
          const r = Math.hypot(x / 10, y / 24) / (1 + 0.2 * noise(Math.atan2(y, x) * 3, o.seed));
          if (r > 1) return;
          if (r > 0.75) p.blend(x, y, C[6], 0.8); else out.c = C[7];
        });
      } else if (t < 0.08) {
        p.shade(-14, -28, 14, 28, (x, y) => {
          const r = Math.hypot(x / 12, y / 26) / (1 + 0.3 * noise(Math.atan2(y, x) * 4, o.seed + 2));
          if (r > 1 || r < 0.55) return;
          p.blend(x, y, C[5], (1 - r) * 1.6);
        });
      }
      ps.draw(p);
    },
  };
}
