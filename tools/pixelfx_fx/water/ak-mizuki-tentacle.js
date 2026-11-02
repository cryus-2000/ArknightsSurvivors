// 水月「触手」（普攻 tentacle / 钉桩 / 病理性依恋砸击，替换 fx_mizuki_tentacle）：@2x 帧条，保留原画布（keep），原点 = 画布水平正中、底边上方 6 px 的地面点，
// 游戏按 bottom 锚（画布底边）× PX × 0.8–0.9 放（每 1x 像素 1.6–1.8 世界像素）。
// 地面裂开一圈不规整的暗水，一根半透明的水母触手从里面抽出：根粗梢细、往一侧弯、梢头卷起抽下，首帧梢头白闪，抽完从梢往根缩回地里。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS, DUR, TAIL_ALPHA } from "../house.js";

export const meta = {
  name: "Mizuki tentacle lash",
  desc: "The ground splits into a ragged dark pool and a translucent jellyfish tentacle whips out of it, curls its tip down in a lash, then sinks back from tip to root.",
  tags: ["water", "tentacle", "jellyfish", "strike", "one-shot"],
  size: [100, 84],
  origin: [50, 78],
  duration: 0.66,   // 主体 + 余韵（技能 ≤ 0.6 s）
  loop: false,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: [...OP.mizuki],
    height: 62,
    seed: 4,
  },
};

const SY = 0.45;

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), H = o.height;
  const ps = new Particles({ rng: Rg, ground: () => 2, sparks: [C[7], C[6], C[5]] });
  const lean = Rg.range(0.2, 0.38), sd = Rg.range(0, 40);
  let t = 0, lashed = false;

  // 触手中心线：s = 0 根 … 1 梢；出时从根往上长，抽时梢头往前卷，收时从梢往根缩
  const spine = (s, t) => {
    const grow = ease.outQuart(clamp((t + 0.02) / 0.1)), lash = ease.inOutQuad(smooth(0.08, 0.2, t));
    const h = H * s * grow;
    const bend = lean * h * (0.5 + s * 0.7) + 3 * noise(s * 4 + t * 6, sd);
    const curl = lash * Math.pow(s, 3) * 18;                 // 梢头往前抽下
    return [bend + curl * 0.8, -h + curl * 0.9];
  };

  function pool(p) {
    const k = 1 - smooth(0.22, 0.4, t), R = 13 * ease.outQuart(clamp(t / 0.06));
    if (k <= 0 || R < 1) return;
    p.shade(-16, -8, 16, 8, (x, y) => {
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / R / (1 + 0.25 * noise(a * 2.4, sd + 3));
      if (r > 1) return;
      p.blend(x, y, C[r > 0.8 ? 4 : 1], (r > 0.8 ? 0.8 : 0.6) * k);
    });
  }

  function body(p) {
    const ret = smooth(0.2, 0.36, t);                         // 从梢往根缩
    const top = 1 - ret;
    if (top <= 0.02) return;
    const N = Math.ceil(H * 1.6), seen = new Set();          // 采样够密，逐像素去重，免得半透明叠出横纹
    for (let i = 0; i <= N * top; i++) {
      const s = i / N, [x, y] = spine(s, t), w = 4.6 * (1 - s * 0.82) + 0.6;
      const hot = t < 0.05 && s > 0.6 ? 2 : 0;              // 首帧梢头白闪
      for (let d = -w; d <= w; d += 0.5) {
        const q = Math.abs(d) / w, edge = q > 0.66;
        const c = C[clamp(Math.round((edge ? 6 : 4) + s * 1.2 - ret * 2 + hot - (d > 0 ? 1 : 0)), 2, 7)];   // 左上受光
        const px = Math.round(x + d), py = Math.round(y), key = px * 1000 + py;
        if (seen.has(key)) continue;
        seen.add(key);
        p.blend(px, py, c, edge ? 0.95 : 0.6);
      }
    }
  }

  // 余韵（docs/229 §2.5）：主体之后留几粒稀疏残光慢慢上浮淡掉，alpha ≤ TAIL_ALPHA；光晕（light 层 → _glow 条）在焦点
  const Rt = new Rng(o.seed + 99), res = [];
  for (let i = 0; i < 7; i++) { const q = ((Rt) => { const a = Rt.range(0, TAU), r = Rt.range(6, 14); return [Math.cos(a) * r, Math.sin(a) * r * SY]; })(Rt); res.push({ x: q[0], y: q[1], d: Rt.range(0, 0.3 * 0.4), l: Rt.range(0.3 * 0.5, 0.3 * 0.6) }); }
  function tailFx(p) {
    for (const r of res) {
      const u = (t - 0.34 - r.d) / r.l;
      if (u < 0 || u >= 1) continue;
      p.blend(Math.round(r.x), Math.round(r.y - u * 4), C[5], TAIL_ALPHA * (1 - u));
    }
  }
  function halo(p) {
    const k = 1 - clamp(Math.abs(t - 0.15) / 0.12);
    if (k > 0) p.glow(8, -40, 18, C[5], 0.9 * k);
  }

  return {
    update(dt) {
      t += dt;
      if (!lashed && t >= 0.18) {
        lashed = true;
        const [x, y] = spine(1, t);
        for (let i = 0; i < 5; i++) {
          const a = Rg.range(0.2, 2.6), sp = Rg.range(40, 110);
          ps.spawn(Rg.chance(0.5) ? P.FLAKE : P.SPARK, x, y, Math.cos(a) * sp, Math.sin(a) * sp * 0.6, Rg.range(0.1, 0.18), C[Rg.int(5, 7)], 1.5);
        }
      }
      ps.update(dt);
    },
    drawBack(p) { pool(p); },
    draw(p) {
      halo(p);
      tailFx(p);
      body(p);
      ps.draw(p);
    },
  };
}
