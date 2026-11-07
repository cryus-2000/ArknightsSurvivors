// 羁绊技「宿敌 · 狼衔剑」概念（docs/314）：拉普兰德唤出一匹紫色狼影（荒芜拉普兰德档案「狼之主」），德克萨斯的一柄巨剑落地插住；
// 狼叼起剑柄拖着剑从怪群里一路犁过去（剑尖在地上划沟、两边的怪被掀开），到头一跃把剑甩上天，剑转一圈钉进终点炸开；狼散成紫色碎光。
import { Particles, Lights, P, Rng, hex, clamp, smooth, ease, mix, WHITE } from "../../core/index.js";
import { Foes, op, groove } from "./_scene.js";

export const meta = {
  name: "Bond wolf sword", desc: "A purple wolf shade grabs Texas's giant sword and drags it through the crowd, then flings it to stab the far end.",
  tags: ["bond", "concept"], size: [380, 190], origin: [190, 118], duration: 2.2, loop: false, fps: 30, bg: "dark", options: { seed: 5 },
};

const TX = ["#2c1406", "#5a2808", "#9c4610", "#e2781c", "#ffac3c", "#ffdc9c", "#ffffff"].map(hex);
const LP = ["#15121f", "#2b2542", "#4a4274", "#7b70b4", "#b3aae4", "#e4e0ff", "#ffffff"].map(hex);
const LX = -172, LY = -26, TXX = -172, TXY = 30;
const T_DROP = 0.3, T_GRAB = 0.5, T_RUN = 1.1, T_LEAP = 1.25, T_STAB = 1.45, X0 = -138, X1 = 150, LANE = 2;

// 狼影（朝右，24 × 11），两帧跑步；+ 背上受光沿、# 身体、o 眼、- 嘴
const WOLF = [
  ["                 +  +   ", "                +####   ", "  +            +#####o+ ", " ++#++++++++++++######--", "  #################     ", "   ################     ", "   ###############      ", "   ##  ##     ## ##     ", "  ##    ##   ##   ##    ", " ##      #  ##     ##   ", "##       ## #       #   "],
  ["                 +  +   ", "                +####   ", "               +#####o+ ", " ++++++++++++++#######--", "+##################     ", "   ################     ", "    ##############      ", "     ## ##   ## ##      ", "     # ##    ##  #      ", "    ## #     #   ##     ", "    #  ##   ##    #     "],
];

export function create(o) {
  const R = new Rng(o.seed);
  const foes = new Foes(R, 36, 30, 4, 135, 48);
  const sparks = new Particles({ rng: R, ground: () => 10, sparks: [WHITE, TX[5], TX[4], TX[2]] });
  const motes = new Particles({ rng: R, ground: () => 10, sparks: [LP[6], LP[5], LP[4], LP[2]] });
  const lights = new Lights();
  let t = 0, dropped = false, stabbed = false, gone = false;
  const wolfX = () => (t < T_GRAB ? X0 - 26 + 26 * smooth(0, T_GRAB, t) : X0 + (X1 - X0) * ease.inOutQuad(clamp((t - T_GRAB) / (T_RUN - T_GRAB))));
  const swordAt = () => {   // [剑柄 x, y, 角度]（角度 0 = 剑尖朝右）
    if (t < T_DROP) return [X0 - 4, -150 + 140 * ease.inQuad(t / T_DROP), Math.PI / 2];
    if (t < T_GRAB) return [X0 - 4, -10, Math.PI / 2];
    if (t < T_RUN) return [wolfX() + 2, -6, Math.PI * 0.82];   // 叼在嘴里，剑尖拖在身后地上
    if (t < T_STAB) { const k = clamp((t - T_RUN) / (T_STAB - T_RUN)); return [lerp(X1, X1 + 10, k), -6 - 55 * Math.sin(Math.PI * k), Math.PI * 0.82 + k * Math.PI * 1.68]; }
    return [X1 + 10, -12, Math.PI / 2];
  };
  return {
    update(dt) {
      t += dt;
      if (t < 0.45) for (let i = 0; i < 2; i++) motes.spawn(P.MOTE, LX + R.range(-4, 4), LY - 10, R.range(20, 90), R.range(-40, 10), R.range(0.3, 0.6));
      if (t >= T_DROP && !dropped) { dropped = true; lights.add(X0, -6, 60, TX[4], 0.7, 0.15); for (let i = 0; i < 14; i++) sparks.spawn(P.SPARK, X0 - 4, 0, R.range(-120, 120), R.range(-160, -20), R.range(0.2, 0.45)); }
      if (t > T_GRAB && t < T_RUN) {
        const wx = wolfX();
        for (const f of foes.alive()) if (f.x < wx + 8 && f.x > wx - 40 && Math.abs(f.y - LANE) < 28) {
          foes.hit(f, t, R.range(10, 60), Math.sign(f.y - LANE || 1) * R.range(120, 220));
          for (let i = 0; i < 3; i++) motes.spawn(P.SPARK, f.x, f.y - 3, R.range(-40, 80), R.range(-120, -20), R.range(0.2, 0.4));
        }
        sparks.spawn(P.SPARK, wx - 30, LANE + 2, R.range(-200, -40), R.range(-150, -20), R.range(0.12, 0.3));
        if (R.range(0, 1) < 0.5) motes.spawn(P.VAPOUR, wx - 8, -8, R.range(-60, -20), R.range(-20, 0), R.range(0.3, 0.6), LP[3], R.range(2, 4));
      }
      if (t >= T_RUN && !gone) { gone = true; for (let i = 0; i < 40; i++) motes.spawn(P.SPARK, X1 + R.range(-10, 10), -10 + R.range(-6, 6), R.range(-120, 120), R.range(-200, 40), R.range(0.3, 0.8)); }
      if (t >= T_STAB && !stabbed) {
        stabbed = true; lights.add(X1 + 10, -4, 120, TX[4], 1.0, 0.25);
        for (let i = 0; i < 40; i++) sparks.spawn(P.SPARK, X1 + 10, 0, R.range(-240, 240), R.range(-260, -20), R.range(0.3, 0.8));
        for (const f of foes.alive()) if (Math.hypot(f.x - X1, (f.y - LANE) * 1.5) < 70) foes.hit(f, t + R.range(0, 0.05), (f.x - X1) * 3, (f.y - LANE) * 3);
      }
      foes.update(dt, t); sparks.update(dt); motes.update(dt); lights.update(dt);
    },
    drawBack(p) {
      if (t > T_GRAB) groove(p, X0 - 34, LANE + 4, X1 - 30, LANE + 4, clamp((wolfX() - 30 - X0 + 34) / (X1 - X0)), TX[4], hex("#3a2418"), 1 - smooth(1.7, 2.2, t));
    },
    draw(p) {
      op(p, LX, LY, LP[2], hex("#eceaf2"), t < 0.5 ? 1 : 0, 1);
      op(p, TXX, TXY, hex("#26232a"), hex("#4a3a34"), t > 0.1 && t < 0.4 ? 1 : 0, 1);
      foes.draw(p, t);
      // 巨剑
      if (t < T_STAB + 0.6) {
        const [hx, hy, a] = swordAt(), L = 46, c = Math.cos(a), s = Math.sin(a), tx = hx + c * L, ty = hy + s * L;
        const fade = t > T_STAB ? 1 - smooth(T_STAB + 0.2, T_STAB + 0.6, t) : 1;
        p.beam(hx, hy, tx, ty, 3.5, TX[3], fade); p.line(hx, hy - 1, tx, ty - 1, TX[5], fade); p.line(hx + c * 4, hy + s * 4, tx - c * 3, ty - s * 3, WHITE, 0.6 * fade);
        p.line(hx - s * 6, hy + c * 6, hx + s * 6, hy - c * 6, TX[2], fade);   // 护手
        p.glowLine(hx, hy, tx, ty, 6, TX[4], 0.35 * fade);
      }
      // 狼影
      if (t > 0.15 && t < T_RUN + 0.05) {
        const a = smooth(0.15, 0.45, t) * (1 - smooth(T_RUN - 0.05, T_RUN + 0.05, t)), fr = Math.floor(t * 14) % 2;
        p.ellipse(wolfX() - 18, 2, 26, 3, LP[0], 0.55 * a);
        p.sprite(WOLF[fr], { "#": "#5a4f8e", "+": "#e4e0ff", o: "#ff5ad0", "-": "#b3aae4" }, wolfX() - 44, -24 - (fr ? 2 : 0), { a: a, scale: 2 });
        p.glow(wolfX() - 16, -12, 34, LP[4], 0.4 * a);
      }
      sparks.draw(p); motes.draw(p); lights.draw(p);
      if (t > T_STAB && t < T_STAB + 0.07) p.circle(X1 + 10, -4, 24, WHITE, 0.8);
    },
  };
}

function lerp(a, b, k) { return a + (b - a) * k; }
