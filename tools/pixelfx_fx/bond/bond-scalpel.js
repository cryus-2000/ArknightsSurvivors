// 羁绊技「手术刀 · 借刀」概念（docs/314；原作：乌尔比安把四爪巨锚称作「手术刀」，拿它教斯卡蒂节制用力）：
// 乌尔比安把锚抛给斯卡蒂 → 斯卡蒂接住、抡着锚链精准地横扫一刀（锚走过的地方只留一串水珠，怪被定住）→ 停一拍 → 一线上的怪同时裂开 → 锚飞回老师手里。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, WHITE } from "../../core/index.js";
import { Foes, op } from "./_scene.js";
import { anchor, chain, UL } from "./_anchor.js";

export const meta = {
  name: "Bond scalpel", desc: "Ulpianus tosses his anchor to Skadi, who sweeps it once with surgical precision; a beat later everything on the line splits.",
  tags: ["bond", "concept"], size: [380, 200], origin: [190, 118], duration: 2.2, loop: false, fps: 30, bg: "dark", options: { seed: 12 },
};

const SK = ["#0b1a3a", "#1c3570", "#3a62c0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"].map(hex);
const ICHOR = [hex("#2a1d40"), hex("#5a3c8a"), hex("#9a7ad0")];
const UX = -172, UY = -34, KX = -140, KY = 26, RX = 290, RY = 100, CX = -140, CY = 26;
const T_CATCH = 0.4, T_SW0 = 0.58, T_SW1 = 0.86, T_CUT = 1.12, T_BACK = 1.5;
const A0 = -0.55, A1 = 0.42;   // 扫过的角度（椭圆，圆心在斯卡蒂）

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 38, 40, 4, 130, 52);
  const water = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, SK[5], SK[4], SK[3]] });
  const ichor = new Particles({ rng: R, ground: () => 10, sparks: [ICHOR[2], ICHOR[1], ICHOR[0]] });
  const lights = new Lights();
  const marked = [];
  let t = 0, cut = false;
  const swA = () => A0 + (A1 - A0) * ease.inOutCubic(clamp((t - T_SW0) / (T_SW1 - T_SW0)));
  const onArc = (a) => [CX + Math.cos(a) * RX * 0.62, CY + Math.sin(a) * RY];
  const anc = () => {
    if (t < 0.1) return [UX + 8, UY - 12];
    if (t < T_CATCH) { const k = (t - 0.1) / (T_CATCH - 0.1); return [lerp(UX + 8, KX + 8, k), lerp(UY - 12, KY - 14, k) - 40 * Math.sin(Math.PI * k)]; }
    if (t < T_SW0) return [KX + 10 - 6 * smooth(T_CATCH, T_SW0, t), KY - 18];
    if (t < T_BACK) return onArc(t < T_SW1 ? swA() : A1);
    const k = clamp((t - T_BACK) / 0.35); const [x, y] = onArc(A1); return [lerp(x, UX + 8, ease.inQuad(k)), lerp(y, UY - 12, k) - 30 * Math.sin(Math.PI * k)];
  };
  return {
    update(dt) {
      t += dt;
      if (t > T_SW0 && t < T_SW1) {   // 锚扫过：怪定住（不飞），记下
        const [ax, ay] = anc();
        for (const f of foes.alive()) if (!f.marked && Math.hypot(f.x - ax, (f.y - ay) * 1.3) < 16) { f.marked = true; f.hold = () => [f.x, f.y]; marked.push(f); }
        if (R.range(0, 1) < 0.8) water.spawn(P.SPARK, ax, ay - 2, R.range(-30, 30), R.range(-60, -10), R.range(0.12, 0.25));
      }
      if (t >= T_CUT && !cut) {   // 同时裂开
        cut = true; lights.add(40, 0, 160, SK[5], 0.7, 0.18);
        for (const f of marked) { f.hold = null; f.th = t; f.vx = R.range(-30, 30); f.vy = R.range(-30, 30); f.life = 0.22; for (let i = 0; i < 6; i++) ichor.spawn(P.SPARK, f.x, f.y - 3, R.range(-120, 120), R.range(-200, -30), R.range(0.25, 0.6)); for (let i = 0; i < 3; i++) water.spawn(P.SPARK, f.x, f.y - 3, R.range(-80, 80), R.range(-160, -40), R.range(0.2, 0.4)); }
      }
      foes.update(dt, t); water.update(dt); ichor.update(dt); lights.update(dt);
    },
    draw(p) {
      op(p, UX, UY, UL[2], hex("#e9edf5"), t < 0.2 || t > T_BACK + 0.25 ? 1 : 0, 1);
      op(p, KX, KY, SK[1], hex("#cfd6e4"), t > T_SW0 - 0.1 && t < T_SW1 + 0.2 ? 1 : 0, 1);
      foes.draw(p, t);
      // 被定住的怪：身上一道细细的亮切口（裂开前一拍）
      if (t > T_SW0 && t < T_CUT) for (const f of marked) { const k = smooth(T_CUT - 0.25, T_CUT, t); p.line(f.x - 4, f.y - 6, f.x + 4, f.y - 1, k > 0.5 ? WHITE : SK[5], 0.5 + 0.5 * k); }
      const [ax, ay] = anc();
      if (t > T_CATCH && t < T_BACK) chain(p, KX + 4, KY - 12, ax, ay - 6, 1, 0);
      if (t < T_BACK + 0.36) anchor(p, ax, ay - 8, t < T_CATCH ? t * 12 : t < T_SW0 ? -0.4 : t < T_BACK ? swA() + Math.PI / 2 : t * 12, 1);
      water.draw(p); ichor.draw(p); lights.draw(p);
    },
  };
}

function lerp(a, b, k) { return a + (b - a) * k; }
