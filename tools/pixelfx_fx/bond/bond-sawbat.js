// 羁绊技「双鳍 · 击锯」概念（docs/314，用户 11-07「锯子 + 剑」）：归溟幽灵鲨把锯刃转着抛高 → 斯卡蒂抡巨剑像挥棒一样把它击飞 →
// 锯刃沿一条直道一路锯过去（火星 + 体液 + 地上一道锯痕）→ 嵌进地里炸开。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, mix, WHITE } from "../../core/index.js";
import { Foes, op, groove } from "./_scene.js";

export const meta = {
  name: "Bond saw bat", desc: "Specter tosses her spinning saw, Skadi bats it with her greatsword, it grinds down a lane and bursts.",
  tags: ["bond", "concept"], size: [380, 190], origin: [190, 118], duration: 2.0, loop: false, fps: 30, bg: "dark", options: { seed: 9 },
};

const SK = ["#0b1a3a", "#1c3570", "#3a62c0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"].map(hex);
const SP = ["#0d1832", "#1d3866", "#2c5a9a", "#3a77c2", "#78afe6", "#c4e2fa", "#ffffff"].map(hex);
const SPA = hex("#ffa04a"), STEEL = [hex("#3a4250"), hex("#7a8494"), hex("#c8d0dc")], ICHOR = [hex("#2a1d40"), hex("#5a3c8a"), hex("#9a7ad0")];
const PX_ = -168, PY = 30, KX = -128, KY = 10;         // 幽灵鲨、斯卡蒂
const T_TOSS = 0.12, T_HIT = 0.55, T_END = 1.0, HX = -112, HY = -26, EX = 165, EY = 4;

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 34, 40, 4, 125, 46);
  const sparks = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, hex("#ffe0a0"), SPA, hex("#8a3a10")] });
  const ichor = new Particles({ rng: R, ground: () => 10, sparks: [ICHOR[2], ICHOR[1], ICHOR[0]] });
  const lights = new Lights();
  let t = 0, hit = false, burst = false;
  const saw = () => {   // 锯刃中心 [x, y(含高度)]
    if (t < T_TOSS) return [PX_ + 8, PY - 12];
    if (t < T_HIT) { const k = (t - T_TOSS) / (T_HIT - T_TOSS); return [lerp(PX_ + 8, HX, k), lerp(PY - 12, HY, k) - 46 * Math.sin(Math.PI * k) * (1 - k * 0.6)]; }
    if (t < T_HIT + 0.08) return [HX, HY];   // 击中顿帧
    const k = clamp((t - T_HIT - 0.08) / (T_END - T_HIT - 0.08)), e = ease.outQuad(k);
    return [lerp(HX, EX, e), lerp(HY, EY - 8, Math.min(1, e * 2.2))];
  };
  return {
    update(dt) {
      t += dt;
      const [sx, sy] = saw();
      if (t >= T_HIT && !hit) { hit = true; lights.add(HX, HY, 110, WHITE, 1.0, 0.16); for (let i = 0; i < 26; i++) sparks.spawn(P.SPARK, HX, HY, R.range(-60, 260), R.range(-220, 80), R.range(0.2, 0.55)); }
      if (t > T_HIT + 0.08 && t < T_END) {
        for (const f of foes.alive()) if (Math.abs(f.x - sx) < 12 && Math.abs(f.y - (sy + 8)) < 20) {
          foes.hit(f, t, R.range(20, 90), Math.sign(f.y - sy || 1) * R.range(80, 170));
          for (let i = 0; i < 5; i++) ichor.spawn(P.SPARK, f.x, f.y - 3, R.range(-60, 160), R.range(-200, -30), R.range(0.25, 0.6));
        }
        for (let i = 0; i < 3; i++) sparks.spawn(P.SPARK, sx - 4, sy + 9, R.range(-240, -60), R.range(-180, -20), R.range(0.12, 0.35));
      }
      if (t >= T_END && !burst) {
        burst = true; lights.add(EX, EY - 6, 120, SPA, 1.0, 0.25);
        for (let i = 0; i < 40; i++) sparks.spawn(P.SPARK, EX, EY - 4, R.range(-260, 200), R.range(-300, -20), R.range(0.3, 0.8));
        for (const f of foes.alive()) if (Math.hypot(f.x - EX, (f.y - EY) * 1.6) < 60) foes.hit(f, t + R.range(0, 0.05), (f.x - EX) * 3, (f.y - EY) * 3);
      }
      foes.update(dt, t); sparks.update(dt); ichor.update(dt); lights.update(dt);
    },
    drawBack(p) {
      if (t > T_HIT + 0.08) { const [sx] = saw(); groove(p, HX + 10, EY + 2, EX, EY + 2, clamp((sx - HX - 10) / (EX - HX - 10)), SPA, hex("#3a2a24"), 1 - smooth(1.5, 2.0, t)); }
    },
    draw(p) {
      op(p, PX_, PY, SP[2], hex("#dfe6f2"), t < 0.25 ? 1 : 0, 1);
      op(p, KX, KY, SK[1], hex("#cfd6e4"), t > T_HIT - 0.15 && t < T_HIT + 0.3 ? 1 : 0, 1);
      foes.draw(p, t);
      // 斯卡蒂的巨剑挥击：蓄力（剑往后）→ 一拍抡出的大月牙拖影
      const sw = t - (T_HIT - 0.05);
      if (sw > -0.25 && sw < 0) { const k = (sw + 0.25) / 0.25; p.beam(KX + 2, KY - 10, KX - 14 - 6 * k, KY - 30 - 4 * k, 3, SK[4]); p.line(KX + 2, KY - 11, KX - 14 - 6 * k, KY - 31 - 4 * k, SK[6]); }
      if (sw >= 0 && sw < 0.3) {
        const fade = 1 - smooth(0.06, 0.3, sw), k = ease.outExpo(clamp(sw / 0.06));
        p.arc(KX + 2, KY - 12, 40, (u) => 10 * Math.sin(Math.PI * u) + 1, -2.6, -2.6 + 2.4 * k, (u, v) => (v > 0.8 ? WHITE : v > 0.5 ? SK[5] : SK[3]), fade);
      }
      // 锯刃
      if (t < T_END + 0.02) {
        const [sx, sy] = saw(), r = 9, spin = t * (t > T_HIT ? 70 : 30);
        p.circle(sx, sy, r, STEEL[1]); p.circle(sx, sy, r - 3, STEEL[0]); p.circle(sx - 1, sy - 1, 2, STEEL[2]);
        for (let i = 0; i < 10; i++) { const a = spin + i * Math.PI / 5; p.tri(sx + Math.cos(a) * r, sy + Math.sin(a) * r, sx + Math.cos(a + 0.35) * (r + 4), sy + Math.sin(a + 0.35) * (r + 4), sx + Math.cos(a + 0.5) * r, sy + Math.sin(a + 0.5) * r, i % 2 ? STEEL[2] : SPA); }
        if (t > T_HIT + 0.08) { p.glow(sx, sy, 16, SPA, 0.5); for (let j = 1; j < 5; j++) p.circle(sx - j * 7, sy, r - j, SPA, 0.35 - j * 0.07); }
        else p.glow(sx, sy, 8, SPA, 0.25);
      }
      sparks.draw(p); ichor.draw(p); lights.draw(p);
      if (t > T_HIT && t < T_HIT + 0.08) p.circle(HX, HY, 14, WHITE, 0.9);
      if (t > T_END && t < T_END + 0.07) p.circle(EX, EY - 6, 22, WHITE, 0.8);
    },
  };
}

function lerp(a, b, k) { return a + (b - a) * k; }
