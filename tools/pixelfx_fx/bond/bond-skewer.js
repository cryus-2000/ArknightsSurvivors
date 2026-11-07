// 羁绊技「引潮夺命 · 串刺」概念（docs/314）：歌蕾蒂娅掷长槊贯穿一排怪 → 槊尾一顿 → 拽回；串在槊上的一排经过归溟幽灵鲨时被锯刃一刀削开。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, mix, scale, WHITE } from "../../core/index.js";
import { Foes, op, SHADOW } from "./_scene.js";

export const meta = {
  name: "Bond skewer", desc: "Gladiia hurls her spear through a row of foes, yanks it back, and Specter saws the skewered row apart.",
  tags: ["bond", "concept"], size: [380, 190], origin: [190, 118], duration: 2.0, loop: false, fps: 30, bg: "ground", options: { seed: 4 },
};

const GL = ["#0d1a2e", "#1f3658", "#35598f", "#4c80c7", "#7fa6e0", "#c9d9ee", "#ffffff"].map(hex);
const SP = ["#0d1832", "#1d3866", "#2c5a9a", "#3a77c2", "#78afe6", "#c4e2fa", "#ffffff"].map(hex);
const SPA = hex("#ffa04a"), ICHOR = [hex("#2a1d40"), hex("#5a3c8a"), hex("#9a7ad0")];
const GX = -170, GY = 6, SX = -40, SY = -34;          // 歌蕾蒂娅、幽灵鲨脚下
const T_THROW = 0.22, T_STICK = 0.42, T_PULL = 0.62, T_BACK = 1.05, T_SAW = 0.86, END = 160;

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 34, 40, 4, 125, 46);
  const water = new Particles({ rng: R, ground: () => 8, sparks: [WHITE, GL[5], GL[4], GL[3]] });
  const ichor = new Particles({ rng: R, ground: () => 8, sparks: [ICHOR[2], ICHOR[1], ICHOR[0]] });
  const metal = new Particles({ rng: R, ground: () => 8, sparks: [WHITE, hex("#ffd9a0"), SPA, hex("#a04a10")] });
  const lights = new Lights();
  const skew = [];
  let t = 0, stuck = false, sawed = false, thrown = false;
  const head = () => {   // 槊尖 x（地面 y = 0）
    if (t < T_THROW) return GX + 12;
    if (t < T_STICK) return GX + 12 + (END - GX - 12) * ease.outQuart((t - T_THROW) / (T_STICK - T_THROW));
    if (t < T_PULL) return END + Math.round(Math.sin(t * 90) * 1.2 * (1 - (t - T_STICK) / (T_PULL - T_STICK)));
    if (t < T_BACK) return END + (GX + 20 - END) * ease.inOutQuad((t - T_PULL) / (T_BACK - T_PULL));
    return GX + 20;
  };
  return {
    update(dt) {
      t += dt;
      const hx = head();
      if (t >= T_THROW && !thrown) { thrown = true; lights.add(GX, -10, 50, GL[4], 0.5, 0.2); }
      if (t >= T_THROW && t < T_STICK) {   // 飞行中：车道上的串起来，车道边的被冲开
        for (const f of foes.alive()) {
          if (f.x > hx || f.hold) continue;
          if (Math.abs(f.y) < 16 && skew.length < 9) { const k = skew.length; skew.push(f); f.th = t; f.hold = () => [head() - 12 - k * 8, -2 + (k % 2) * 2]; for (let i = 0; i < 5; i++) water.spawn(P.SPARK, f.x, -4, R.range(-40, 120), R.range(-120, -30), R.range(0.2, 0.45)); }
          else if (Math.abs(f.y) < 34) foes.hit(f, t, 30, Math.sign(f.y) * 140);
        }
        water.spawn(P.SPARK, hx - 4, -5, R.range(-160, -40), R.range(-70, 10), R.range(0.15, 0.3));
      }
      if (t >= T_STICK && !stuck) { stuck = true; lights.add(END, -6, 40, GL[5], 0.6, 0.15); for (let i = 0; i < 18; i++) water.spawn(P.SPARK, END, -4, R.range(-90, 140), R.range(-200, -40), R.range(0.3, 0.6)); }
      if (t >= T_SAW && !sawed) {   // 锯刃削开：串上的全部爆开
        sawed = true;
        lights.add(SX + 10, -6, 90, SPA, 0.9, 0.18);
        for (const f of foes.list) if (f.hold) {
          f.hold = null; f.th = t; f.vx = R.range(-60, 60); f.vy = R.range(-40, 60); f.life = 0.25;
          for (let i = 0; i < 6; i++) ichor.spawn(P.SPARK, f.x, f.y - 3, R.range(-140, 140), R.range(-220, -20), R.range(0.3, 0.7));
          for (let i = 0; i < 3; i++) metal.spawn(P.SPARK, f.x, f.y - 4, R.range(40, 260), R.range(-160, 40), R.range(0.15, 0.35));
        }
      }
      foes.update(dt, t); water.update(dt); ichor.update(dt); metal.update(dt); lights.update(dt);
    },
    drawBack(p) {
      if (t > T_STICK && t < T_BACK + 0.6) {   // 槊拖回时在地上犁出的水痕
        const x0 = Math.min(head(), END), fade = 1 - smooth(T_BACK, T_BACK + 0.6, t);
        for (let x = x0; x <= END; x += 1) { const hz = Math.sin(x * 1.3) * 0.5 + 0.5; if (hz > 0.25) p.dot(x, 1 + Math.round(Math.sin(x * 0.4)), mix(GL[1], GL[3], hz), 0.8 * fade); }
      }
    },
    draw(p) {
      op(p, GX, GY, GL[2], hex("#e8e4f0"), t > 0.12 && t < 0.5 ? 1 : 0, 1);
      op(p, SX, SY, SP[2], hex("#dfe6f2"), t > T_SAW - 0.12 && t < T_SAW + 0.25 ? 1 : 0, 1);
      foes.draw(p, t);
      // 长槊
      if (t >= 0.08 && t < T_BACK + 0.05) {
        const hx = head(), L = 74, y = -5;
        const tail = t < T_THROW ? hx - 30 - 10 * smooth(0.08, T_THROW, t) : hx - L;
        p.beam(tail, y, hx - 6, y, 2.2, GL[3]);
        p.line(tail, y - 1, hx - 6, y - 1, GL[5]);
        p.tri(hx - 7, y - 4, hx + 4, y, hx - 7, y + 4, GL[5]);
        p.px(hx + 3, y, WHITE); p.px(hx + 2, y, WHITE);
        p.line(hx - 9, y - 5, hx - 5, y - 2, GL[4]); p.line(hx - 9, y + 5, hx - 5, y + 2, GL[4]);   // 倒刺
        p.glow(hx, y, 10, GL[5], 0.35);
        if (t >= T_THROW && t < T_STICK) for (let i = 1; i < 6; i++) p.line(hx - 20 - i * 18, y + (i % 2 ? -3 : 3), hx - 8 - i * 18, y + (i % 2 ? -3 : 3), GL[4], 0.7 - i * 0.1);   // 速度线
      }
      // 锯刃：从幽灵鲨头顶往下一刀劈过车道（带齿的月牙）
      const sa = t - T_SAW + 0.06;
      if (sa > 0 && sa < 0.34) {
        const k = ease.outExpo(clamp(sa / 0.08)), fade = 1 - smooth(0.1, 0.34, sa), cx = SX + 6, cy = SY - 4, r = 52;
        const a0 = -1.2, a1 = -1.2 + 2.6 * k;
        p.arc(cx, cy, r, (u) => 7 * Math.sin(Math.PI * u) + 1, a0, a1, (u, v) => (v > 0.75 ? WHITE : v > 0.45 ? SP[5] : SP[3]), fade);
        for (let i = 0; i < 14; i++) {   // 锯齿
          const a = a0 + (a1 - a0) * (i + 0.5) / 14, x = cx + Math.cos(a) * (r + 1), y = cy + Math.sin(a) * (r + 1);
          p.tri(x, y, x + Math.cos(a + 0.6) * 4, y + Math.sin(a + 0.6) * 4, x + Math.cos(a) * 1.5 - Math.sin(a) * 2, y + Math.sin(a) * 1.5 + Math.cos(a) * 2, i % 3 ? SP[5] : SPA, fade);
        }
        p.glowLine(cx + Math.cos(a1) * r, cy + Math.sin(a1) * r, cx + Math.cos(a1 - 0.4) * r, cy + Math.sin(a1 - 0.4) * r, 4, SPA, 0.6 * fade);
      }
      water.draw(p); ichor.draw(p); metal.draw(p); lights.draw(p);
      if (t > T_SAW && t < T_SAW + 0.07) p.ellipse(SX + 6, 0, 30, 6, WHITE, 0.6);
    },
  };
}
