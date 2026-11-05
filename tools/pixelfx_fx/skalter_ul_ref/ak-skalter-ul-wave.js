// 浊心斯卡蒂普攻「声浪」（docs/242 放开版；ob_core circle 判定 src「声浪」，注册表 data/px_ul.json 接管）：1x，俯视，原点 = 歌域圆心（以队长为中心），地面透视 sy 0.55。
// 每秒一次，所以克制：只有一道断续的歌声前沿从内推到歌域边缘（判定半径 R，judge 传入；运行时按当前半径 ÷ fit 缩放），前沿后面一层很淡的水幕，零星海蓝光点骑在浪头上。
// 和技能分开：普攻没有潮冠、没有浪柱、没有触须，只有地面上的一道前沿。
// 精英档（docs/91 §13）：E0 前沿 + 光点；E1「余音」= 前沿散去后外圈 80–100% 起 2–3 段更细的回声弧（同一时刻只有一道环）；
// E2「远古血亲」= 前沿浪头带海蓝高光，前沿上随机两三处探出海嗣鳍尖一闪即没。
import { Particles, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skalter song wave",
  desc: "Her basic song wave: one broken wine-dark front rolls out to the edge of her song field with sea-blue glints on its crest; higher ranks add echo arcs and seaborn fin tips.",
  tags: ["water", "song", "wave", "ring", "topdown", "one-shot"],
  size: [220, 140],
  origin: [110, 72],
  duration: 0.75,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: [...OP.skalter],
    sea: ["#0b1a2e", "#14324f", "#1f5468", "#3b8e89", "#7fc4bf", "#d6f0ec"],   // 海蓝 / 灰青（PRTS 帽 #3B8E89、饰边 #6ACCCA 压饱和）
    R: 95,           // 歌域边缘（1x）= judge: aura ÷ PX
    elite: 2,
    quick: 0,        // 1 = 队友版：余韵减半，亮度不降
    layer: "all",
    seed: 4,
  },
};

const SY = 0.55, FRONT = 0.26;

export function create(o) {
  const C = fit(o.palette, 8), S = fit(o.sea, 6), Rg = new Rng(o.seed), R = o.R, el = +o.elite;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const tail = [0.22, 0.3, 0.42][el] * (+o.quick ? 0.5 : 1);
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [S[5], S[4], S[3]] });
  // 前沿的缺口：随机步长、宽窄不一（不等分）
  const gaps = [];
  for (let a = Rg.range(0, 0.9); a < TAU - 0.2; a += Rg.range(0.9, 2.1)) gaps.push({ a, w: Rg.range(0.1, 0.32) });
  const inGap = (a) => gaps.some((g) => { let d = a - g.a; d -= Math.round(d / TAU) * TAU; return Math.abs(d) < g.w; });
  const echo = [];
  if (el >= 1) for (let i = 0, a0 = Rg.range(0, TAU), n = Rg.int(2, 3); i < n; i++) { echo.push({ a: a0, w: Rg.range(0.3, 0.75) }); a0 += Rg.range(1.5, 2.6); }
  const onEcho = (a) => echo.some((g) => { let d = a - g.a; d -= Math.floor(d / TAU) * TAU; return d < g.w; });
  const fins = [];
  if (el >= 2) for (let a = Rg.range(0, 1.5); a < TAU - 0.5; a += Rg.range(1.6, 2.8)) fins.push({ a, h: Rg.range(11, 17), d: Rg.range(0.12, 0.2), lean: Rg.range(-0.6, 0.6) });
  const glints = [];
  for (let i = 0, n = [5, 7, 10][el]; i < n; i++) glints.push({ a: Rg.range(0, TAU), d: Rg.range(0, 0.2), l: Rg.range(0.15, 0.15 + tail) });
  const front = (t) => R * (0.3 + 0.7 * ease.outCubic(clamp(t / FRONT)));
  const jag = (a) => 1 + 0.04 * noise(a * 3.1, o.seed) + 0.02 * noise(a * 8.7, o.seed + 5);
  let t = 0;

  function arc(p, rr, k, far, pick, crestCol, crest2 = false) {
    if (k <= 0.02) return;
    for (let a = 0; a < TAU; a += 0.7 / rr) {
      if ((Math.sin(a) < 0) !== far || !pick(a)) continue;
      const r = rr * jag(a), x = Math.round(Math.cos(a) * r), y = Math.round(Math.sin(a) * r * SY);
      const hi = 0.5 + 0.5 * noise(a * 5 + t * 5, o.seed + 2);
      p.blend(x, y, hi > 0.72 ? crestCol : C[clamp(Math.round(2 + 3.5 * k), 2, 5)], (far ? 0.6 : 0.88) * k);   // 1 格宽前沿（§12.5 做细）
      p.blend(Math.round(Math.cos(a) * r * 0.975), Math.round(Math.sin(a) * r * 0.975 * SY), C[clamp(Math.round(1 + 2 * k), 1, 3)], 0.55 * k);   // 内侧一格暗边，给前沿一点厚度
      if (crest2 && hi > 0.45) p.blend(Math.round(Math.cos(a) * (r + 1.2)), Math.round(Math.sin(a) * (r + 1.2) * SY), S[4], (far ? 0.5 : 0.8) * k);   // E2 浪头：外侧一格海蓝亮边，断续
    }
  }

  function sheet(p, far) {   // 前沿后的淡水幕（装饰）
    const rf = front(t), k = 1 - smooth(FRONT * 0.6, FRONT + 0.1, t);
    if (k <= 0.02) return;
    const B = rf * 1.05;
    p.shade(-B, -B * SY, B, B * SY, (x, y) => {
      if ((y < 0) !== far) return;
      const a = Math.atan2(y / SY, x);
      if (inGap(a)) return;
      const q = Math.hypot(x, y / SY) / (rf * jag(a));
      if (q > 1 || q < 0.84) return;
      p.blend(x, y, C[2], 0.26 * k * (q - 0.84) / 0.16);
    });
  }

  function draws(p, far) {
    if (deco) sheet(p, far);
    if (core) {
      const k = 1 - smooth(FRONT * 0.7, FRONT + 0.12, t), hot = t < 0.05;
      arc(p, front(t), k, far, (a) => !inGap(a), hot ? C[6] : el >= 2 ? S[4] : C[5], el >= 2);
      if (el >= 1) { const u = t - FRONT - 0.06; if (u > 0) arc(p, R * (0.82 + 0.18 * ease.outQuad(clamp(u / 0.25))), 0.85 * (1 - smooth(0.15, 0.32, u)), far, onEcho, S[4]); }
      for (const f of fins) {   // E2 海嗣鳍尖：从前沿上探出一下就没
        if ((Math.sin(f.a) < 0) !== far) continue;
        const u = t - f.d;
        if (u < 0 || u > 0.22) continue;
        const h = f.h * Math.sin(Math.PI * u / 0.22), r = front(f.d) * jag(f.a), bx = Math.cos(f.a) * r, by = Math.sin(f.a) * r * SY;
        for (let d = 0; d <= h; d += 1) {
          const v = d / Math.max(h, 1), w = 2.4 * (1 - v);
          for (let q = -w; q <= w; q += 1) p.blend(Math.round(bx + q + f.lean * d), Math.round(by - d), q < -w + 1 ? S[5] : S[2], 0.95);
        }
      }
    }
  }

  return {
    update(dt) { t += dt; ps.update(dt); },
    drawBack(p) { draws(p, true); },
    draw(p) {
      draws(p, false);
      if (deco) for (const g of glints) {   // 浪头上的海蓝光点，前沿过去后在原地闪一下再淡（余韵 ≤ 0.4）
        const u = (t - g.d) / g.l;
        if (u < 0 || u >= 1) continue;
        const r = front(g.d + 0.05) * jag(g.a), x = Math.round(Math.cos(g.a) * r), y = Math.round(Math.sin(g.a) * r * SY) - 1;
        p.blend(x, y, S[5], (u < 0.3 ? 0.85 : 0.4) * (1 - u));
      }
      if (core && t < 0.05) { p.px(0, 0, C[6]); p.px(1, 0, C[5]); p.px(0, -1, C[5]); }   // 圆心一点起手亮
    },
  };
}
