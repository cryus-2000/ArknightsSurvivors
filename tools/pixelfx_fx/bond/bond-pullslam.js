// 羁绊技「手术刀」概念 B（docs/314；原作：乌尔比安把锚称作「手术刀」，教斯卡蒂节制用力）：
// 老师布置、学生下手——乌尔比安抡锚掷进怪群、锚爪咬地 → 往回一拽，把一路的怪拖成一堆堆到斯卡蒂面前 → 斯卡蒂一剑劈下，冲击只在那一堆里炸开（收着力，外面的怪不受波及）。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, WHITE } from "../../core/index.js";
import { Foes, op } from "./_scene.js";
import { anchor, chain, UL } from "./_anchor.js";

export const meta = {
  name: "Bond pull slam", desc: "Ulpianus hooks the crowd with his anchor and drags a pile to Skadi, who cuts it down with one contained strike.",
  tags: ["bond", "concept"], size: [380, 200], origin: [190, 118], duration: 2.2, loop: false, fps: 30, bg: "dark", options: { seed: 14 },
};

const SK = ["#0b1a3a", "#1c3570", "#3a62c0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"].map(hex);
const ICHOR = [hex("#2a1d40"), hex("#5a3c8a"), hex("#9a7ad0")];
const UX = -176, UY = -34, KX = -150, KY = 30, PX_ = -112, PY = 22, FX = 120, FY = 0;
const T_SPIN = 0.08, T_THROW = 0.42, T_BITE = 0.62, T_PULL = 0.8, T_PILE = 1.12, T_CUT = 1.24;
const HAND = [UX + 4, UY - 11], SPIN = (a) => [UX + 2 + Math.cos(a) * 17, UY - 26 + Math.sin(a) * 7];

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 40, 40, 4, 135, 54);
  const water = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, SK[5], SK[4], SK[3]] });
  const ichor = new Particles({ rng: R, ground: () => 10, sparks: [ICHOR[2], ICHOR[1], ICHOR[0]] });
  const lights = new Lights();
  const pile = [];
  let t = 0, bit = false, cut = false;
  const aEnd = Math.PI * 3;
  const anc = () => {
    if (t < T_SPIN) return [UX + 9, UY - 2];
    if (t < T_THROW) return SPIN(Math.PI * 0.5 + ease.inQuad((t - T_SPIN) / (T_THROW - T_SPIN)) * Math.PI * 2.5);
    const [sx, sy] = SPIN(aEnd);
    if (t < T_BITE) { const k = ease.outQuad((t - T_THROW) / (T_BITE - T_THROW)); return [lerp(sx, FX, k), lerp(sy, FY, k) - 40 * Math.sin(Math.PI * k)]; }
    if (t < T_PULL) return [FX, FY];
    if (t < T_PILE) { const k = ease.inQuad((t - T_PULL) / (T_PILE - T_PULL)); return [lerp(FX, PX_ + 14, k), lerp(FY, PY, k)]; }
    if (t < T_CUT + 0.3) return [PX_ + 14, PY];
    const k = clamp((t - T_CUT - 0.3) / 0.3); return [lerp(PX_ + 14, HAND[0], ease.inQuad(k)), lerp(PY, HAND[1], k) - 20 * Math.sin(Math.PI * k)];
  };
  return {
    update(dt) {
      t += dt;
      const [ax, ay] = anc();
      if (t >= T_BITE && !bit) { bit = true; lights.add(FX, FY, 50, UL[5], 0.6, 0.12); for (let i = 0; i < 14; i++) water.spawn(P.SPARK, FX, FY, R.range(-120, 120), R.range(-160, -30), R.range(0.2, 0.45)); }
      if (t > T_PULL && t < T_PILE) {   // 拖回：锚经过的怪被钩住、跟着锚走，堆在锚前面
        for (const f of foes.alive()) if (!f.hold && Math.hypot(f.x - ax, (f.y - ay) * 1.4) < 26) {
          const k = pile.length; pile.push(f); f.th = t;
          const ox = -6 - (k % 4) * 5 + R.range(-2, 2), oy = (Math.floor(k / 4) % 3 - 1) * 6 + R.range(-2, 2);
          f.hold = () => { const [x, y] = anc(); return [x + ox - 8, y + oy]; };
        }
        if (R.range(0, 1) < 0.7) water.spawn(P.SPARK, ax + 6, ay, R.range(20, 120), R.range(-80, -10), R.range(0.15, 0.3));
      }
      if (t >= T_CUT && !cut) {   // 一剑：只炸这一堆
        cut = true; lights.add(PX_, PY - 4, 80, SK[5], 1.0, 0.18);
        for (const f of pile) { f.hold = null; f.th = t; f.vx = R.range(-50, 50); f.vy = R.range(-30, 30); f.life = 0.22; for (let i = 0; i < 5; i++) ichor.spawn(P.SPARK, f.x, f.y - 3, R.range(-110, 110), R.range(-200, -30), R.range(0.25, 0.55)); }
        for (let i = 0; i < 30; i++) water.spawn(P.SPARK, PX_ + R.range(-8, 8), PY, R.range(-90, 90), R.range(-260, -60), R.range(0.3, 0.7));
      }
      foes.update(dt, t); water.update(dt); ichor.update(dt); lights.update(dt);
    },
    drawBack(p) {
      if (t > T_PULL && t < T_PILE + 0.6) {   // 锚拖过的地痕（碎点）
        const [ax] = anc(), fade = 1 - smooth(T_PILE, T_PILE + 0.6, t);
        for (let x = ax; x < FX; x += 2) if (Math.sin(x * 1.7) > -0.3) p.dot(x, PY * (FX - x) / (FX - PX_ - 14) + FY + 3 + Math.round(Math.sin(x * 0.5)), UL[2], 0.7 * fade);
      }
      if (t > T_CUT) {   // 收住的一刀：落点一小块裂口，不外扩
        const fade = 1 - smooth(T_CUT + 0.4, T_CUT + 0.9, t);
        for (let i = -22; i <= 22; i++) p.dot(PX_ + i * 0.4, PY + i * 0.5 + Math.round(Math.sin(i * 1.3)), Math.abs(i) < 8 ? SK[5] : SK[2], fade);
      }
    },
    draw(p) {
      op(p, UX, UY, UL[2], hex("#e9edf5"), (t > T_THROW - 0.06 && t < T_THROW + 0.25) || (t > T_PULL && t < T_PILE) ? 1 : 0, 1);
      if (t >= T_SPIN && t < T_THROW) p.line(HAND[0], HAND[1], HAND[0] + 2, HAND[1] - 6, hex("#e9edf5"));
      op(p, KX, KY, SK[1], hex("#cfd6e4"), t > T_CUT - 0.2 && t < T_CUT + 0.25 ? 1 : 0, 1);
      foes.draw(p, t);
      const [ax, ay] = anc();
      if (t >= T_SPIN && t < T_THROW) chain(p, HAND[0], HAND[1], ax, ay, 1, 0);
      else if (t >= T_THROW && t < T_CUT + 0.6) chain(p, HAND[0], HAND[1], ax, ay - 10, 1, t < T_BITE ? 10 : t < T_PULL ? 4 : 0);
      anchor(p, ax, t < T_THROW ? ay + 6 : ay - 10, t < T_SPIN ? 0 : t < T_THROW ? Math.atan2(ay - (UY - 26), ax - UX - 2) - Math.PI / 2 : t < T_BITE ? (t - T_THROW) * 14 : t < T_PILE ? -Math.PI / 2 + 0.3 : 0, t < T_THROW ? 0.8 : 1);
      // 斯卡蒂一剑：举剑（蓄）→ 一拍从头顶劈到落点的大月牙
      const sw = t - T_CUT + 0.05;
      if (sw > -0.2 && sw < 0) p.beam(KX + 2, KY - 12, KX - 6, KY - 40, 3, SK[4]);
      if (sw >= 0 && sw < 0.28) {
        const fade = 1 - smooth(0.06, 0.28, sw), k = ease.outExpo(clamp(sw / 0.05));
        p.arc(KX + 4, KY - 14, 44, (u) => 11 * Math.sin(Math.PI * u) + 1, -2.2, -2.2 + 2.1 * k, (u, v) => (v > 0.8 ? WHITE : v > 0.5 ? SK[5] : SK[3]), fade);
      }
      water.draw(p); ichor.draw(p); lights.draw(p);
      if (t > T_CUT && t < T_CUT + 0.07) p.ellipse(PX_, PY - 2, 20, 8, WHITE, 0.7);
    },
  };
}

function lerp(a, b, k) { return a + (b - a) * k; }
