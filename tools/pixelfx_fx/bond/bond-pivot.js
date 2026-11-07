// 羁绊技「漩涡钉锚 · 钉桩回旋」概念（docs/314）：歌蕾蒂娅的长槊从天上钉进怪群当桩（乌尔比安「向歌蕾蒂娅核实坐标」）→
// 乌尔比安掷锚、锚链缠上长槊 → 锚绕槊甩一整圈、越绕越紧，把一圈怪卷向中间 → 锚砸在槊旁炸开水冠。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, WHITE } from "../../core/index.js";
import { Foes, op } from "./_scene.js";
import { anchor, chain, UL } from "./_anchor.js";

export const meta = {
  name: "Bond pivot anchor", desc: "Gladiia's spear stakes the crowd; Ulpianus's anchor chain wraps it and swings round, reeling the crowd in, then slams.",
  tags: ["bond", "concept"], size: [380, 200], origin: [190, 118], duration: 2.2, loop: false, fps: 30, bg: "dark", options: { seed: 6 },
};

const GL = ["#0d1a2e", "#1f3658", "#35598f", "#4c80c7", "#7fa6e0", "#c9d9ee", "#ffffff"].map(hex);
const CX = 50, CY = 2, R0 = 100, SQ = 0.5, UX = -170, UY = 12, GX = -150, GY = -40;
const T_STAKE = 0.32, T_THROW = 0.45, T_WRAP = 0.7, T_SLAM = 1.45;

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 38, CX, CY, 130, 52);
  const water = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, GL[5], GL[4], GL[3]] });
  const lights = new Lights();
  let t = 0, staked = false, slammed = false;
  const ang = () => { const k = clamp((t - T_WRAP) / (T_SLAM - T_WRAP)); return -0.2 + ease.inQuad(k) * Math.PI * 2.4; };
  const rad = () => R0 * (1 - 0.82 * ease.inQuad(clamp((t - T_WRAP) / (T_SLAM - T_WRAP))));
  const anc = () => {
    if (t < T_THROW) return [UX + 10, UY - 14];
    if (t < T_WRAP) { const k = (t - T_THROW) / (T_WRAP - T_THROW); return [lerp(UX + 10, CX + Math.cos(-0.2) * R0, k), lerp(UY - 14, CY + Math.sin(-0.2) * R0 * SQ, k) - 40 * Math.sin(Math.PI * k)]; }
    if (t < T_SLAM) return [CX + Math.cos(ang()) * rad(), CY + Math.sin(ang()) * rad() * SQ];
    return [CX + 14, CY + 4];
  };
  return {
    update(dt) {
      t += dt;
      if (t >= T_STAKE && !staked) { staked = true; lights.add(CX, CY, 60, GL[5], 0.7, 0.15); for (let i = 0; i < 16; i++) water.spawn(P.SPARK, CX, CY, R.range(-120, 120), R.range(-180, -30), R.range(0.25, 0.5)); }
      if (t > T_WRAP && t < T_SLAM) {   // 锚链扫过的：卷进来（按当前半径收）
        const a = ang(), r = rad();
        for (const f of foes.alive()) {
          const dx = f.x - CX, dy = (f.y - CY) / SQ, d = Math.hypot(dx, dy);
          if (d < r + 6 && !f.hold) {
            const fa = Math.atan2(dy, dx), da = ((a - fa) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2);
            if (da < 0.5) { const dd = d; f.hold = () => { const rr = Math.min(dd, rad() * (0.5 + 0.5 * dd / Math.max(1, R0))); const aa = fa + (ang() - a) * 0.8; return [CX + Math.cos(aa) * rr, CY + Math.sin(aa) * rr * SQ]; }; f.th = t; }
          }
        }
        const [ax, ay] = anc();
        water.spawn(P.SPARK, ax, ay - 4, R.range(-60, 60), R.range(-100, -20), R.range(0.15, 0.35));
      }
      if (t >= T_SLAM && !slammed) {
        slammed = true; lights.add(CX, CY - 6, 140, GL[5], 1.0, 0.25);
        for (let i = 0; i < 60; i++) water.spawn(P.SPARK, CX + R.range(-10, 10), CY, R.range(-200, 200), R.range(-320, -40), R.range(0.3, 0.9));
        for (const f of foes.list) if (f.hold) { f.hold = null; f.th = t + R.range(0, 0.04); f.vx = (f.x - CX) * 4 + R.range(-40, 40); f.vy = (f.y - CY) * 4; }
      }
      foes.update(dt, t); water.update(dt); lights.update(dt);
    },
    drawBack(p) {
      if (t > T_WRAP && t < T_SLAM + 0.5) {   // 锚扫过的水面涡纹（碎点，不画实线圈）
        const fade = 1 - smooth(T_SLAM, T_SLAM + 0.5, t), a1 = ang(), r = rad();
        for (let i = 0; i < 70; i++) { const u = i / 70, a = a1 - u * 2.2, rr = r + u * 24 + Math.sin(i * 2.3) * 4; if (Math.sin(i * 7.1) > -0.2) p.dot(CX + Math.cos(a) * rr, CY + Math.sin(a) * rr * SQ + 1, u < 0.2 ? GL[5] : GL[3], (1 - u) * 0.8 * fade); }
      }
    },
    draw(p) {
      op(p, UX, UY, UL[2], hex("#e9edf5"), t > T_THROW - 0.12 && t < T_THROW + 0.2 ? 1 : 0, 1);
      op(p, GX, GY, GL[2], hex("#e8e4f0"), t < T_STAKE ? 1 : 0, 1);
      foes.draw(p, t);
      // 长槊：从天上竖直落下钉住
      const sy = t < T_STAKE ? CY - 200 + 200 * ease.inQuad(t / T_STAKE) : CY, fade = 1 - smooth(1.7, 2.1, t);
      p.beam(CX, sy - 44, CX, sy - 2, 2.2, GL[3], fade); p.line(CX - 1, sy - 44, CX - 1, sy - 2, GL[5], fade);
      p.tri(CX - 3, sy - 6, CX, sy + 4, CX + 3, sy - 6, GL[5], fade); p.glow(CX, sy - 20, 10, GL[4], 0.3 * fade);
      // 锚 + 锚链（链：桩顶 → 锚）
      if (t < T_SLAM + 0.5) {
        const [ax, ay] = anc(), al = t > T_SLAM ? 1 - smooth(T_SLAM + 0.2, T_SLAM + 0.5, t) : 1;
        if (t > T_THROW && t < T_WRAP) chain(p, UX + 4, UY - 10, ax, ay - 10, 1, 8);
        if (t >= T_WRAP && t < T_SLAM) chain(p, CX, CY - 30, ax, ay - 12, 1, 0);
        anchor(p, ax, ay - 10, t < T_WRAP ? (t - T_THROW) * 14 : t < T_SLAM ? ang() + Math.PI / 2 : 0, 1, al);
      }
      water.draw(p); lights.draw(p);
      if (t > T_SLAM && t < T_SLAM + 0.07) p.ellipse(CX, CY - 4, 40, 18, WHITE, 0.8);
    },
  };
}

function lerp(a, b, k) { return a + (b - a) * k; }
