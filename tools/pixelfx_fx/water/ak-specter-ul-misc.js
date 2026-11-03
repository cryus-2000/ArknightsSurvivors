// 归溟幽灵鲨放开版其余件（docs/242；用户 11-04：往外发散的光环一律不要——这里的件都往里收、或贴着原地转 / 起伏，不画外扩圈）。
// 原作参照（build/ark_ref/specter_unchained，只作参照）：beidong_buff_01 / 02（替身光环：地面海水纹 + 泡）、birth_01_start（现身：水柱 + 碎沫）。
// move（俯视地面透视 y × SY；原点见各条）：
//   curl   精一卷刃：外圈几道海军蓝水纹往里卷进锯口（半径 R → 0.55R），原点 = 脚底
//   fall   S2 结束倒下化替身：身上水带往上散 + 碎沫，原点 = 脚底（侧视）
//   back   替身归队：四周水沫往身上收拢，原点 = 脚底（侧视）
//   aura   替身光环一拍（每秒一次，天赋 拥抱自我）：判定半径上一圈断续的海水边（边缘不规整、有缺口），里面水纹往里流，原点 = 替身脚底
//   pulse  替身闪现的一次法术脉冲：绕替身一圈的海军蓝水旋（半径内，往里收），原点 = 替身脚底
//   appear 替身闪现现身：地面水花往上收成一柱，原点 = 脚底（侧视）
//   burst  替身闪现消散：碎成泡沫往上飘，原点 = 脚底（侧视）
//   tide   成长 血色潮痕：地上一摊不规整的深海水痕（边在判定半径上、断续），内部细纹往里流，原点 = 圆心
//   quake  成长 锯鸣·共振 震地：不规则分叉裂口 + 碎石尘（不画冲击环），原点 = 圆心
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";
import { OP } from "../house.js";

const shadeB = (p, x0, y0, x1, y1, fn) => {
  const o = { c: 0, a: 1 };
  p.each(x0, y0, x1, y1, (x, y, sx, sy) => { o.c = 0; o.a = 1; const c = fn(x, y, o) || o.c; if (c && o.a > 0) p.blendPx(sx, sy, c, Math.min(1, o.a)); });
};

export const meta = {
  name: "Specter misc pieces",
  desc: "Inward-curling water strokes, a stand-in's broken sea-water aura edge, collapsing splashes, foam bursts, a creeping tide stain and an irregular ground rupture.",
  tags: ["water", "buff", "summon", "ground", "one-shot"],
  size: [220, 150],
  origin: [110, 95],
  duration: 1.6,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    navy: OP.specter_unchained,   // 海军蓝七阶取 house.js（PRTS 饰「蓝披带」#152E57，组长 11-04 批）
    tide: ["#04121a", "#0a2430", "#123a48", "#1c5464", "#2f7486", "#5d9aa8", "#a6ccd4"],   // 潮痕：低饱和深海青（10-14 用户：别和敌方红色预警重合）
    blood: ["#100403", "#2a0906", "#4a1108", "#741a0c", "#962614", "#b4482c", "#e0b8a8"],
    ember: ["#160605", "#3e0e08", "#7a1e0c", "#b8361a", "#e45a2a", "#ffa47a", "#fff0e6"],
    radius: 80,
    sy: 0.55,
    move: "curl",
    life: 0.6,
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const NV = fit(o.navy, 7), TD = fit(o.tide, 7), BL = fit(o.blood, 7), EM = fit(o.ember, 7);
  const Rg = new Rng(o.seed), mv = o.move, SY = +o.sy, R = +o.radius, LIFE = +o.life;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [EM[5], EM[4], EM[4], EM[3]], haze: NV[4] }), lights = new Lights();
  const dir = Rg.chance(0.5) ? 1 : -1;
  let t = 0, fired = false;
  const at = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * SY];
  const near = (a) => 0.5 + 0.5 * Math.sin(a);

  // 一道沿 path(f) 的带子（f 0 → 1），宽 w0、撕裂边、可见段 [gone, grow]；ramp 选色、foam 内沿白沫
  function band(p, path, w0, grow, gone, seed, ramp, foam, aMul = 1) {
    if (grow - gone < 0.02) return;
    const N = 220;
    for (let i = 0; i <= N; i++) {
      const f = i / N;
      if (f > grow || f < gone) continue;
      const [x, y] = path(f), [x2, y2] = path(Math.min(1, f + 0.012));
      const tl = Math.hypot(x2 - x, y2 - y) || 1, nx = -(y2 - y) / tl, ny = (x2 - x) / tl;
      const tear = 0.55 + 0.45 * noise(f * 11, seed) + 0.3 * noise(f * 29, seed + 3);
      const w = w0 * tear * Math.min(1, clamp((grow - f) / 0.15) * 1.3 + 0.15) * Math.min(1, clamp((f - gone) / 0.2) * 1.5 + 0.2);
      if (w < 0.4) continue;
      for (let d = -w; d <= w; d += 0.5) {
        const e = Math.abs(d) / w, crest = foam && d < -w + 1 && noise(f * 17, seed + 7) > 0;
        const ci = crest ? 6 : clamp(Math.round(2 + 2 * (1 - e) + 1.2 * noise(f * 8 + d * 0.5, seed + 11)), 1, 5);
        p.blendPx(p.cellX(x + nx * d, y + ny * d), p.cellY(x + nx * d, y + ny * d), ramp[ci], (e > 0.8 ? 0.5 : 0.9) * aMul);
      }
    }
  }
  const spiral = (r0, r1, turns, a0, lift = 0) => (f) => {
    const a = a0 + dir * TAU * turns * f, r = r0 + (r1 - r0) * ease.inOutSine(f);
    return [Math.cos(a) * r, Math.sin(a) * r * SY - lift * Math.sin(Math.PI * f)];
  };
  // 断续的圈边（aura / tide）：只在 noise > 阈值处画，边缘起伏；k 透明度
  function brokenEdge(p, r, w, k, seed, ramp, rot, gap) {
    shadeB(p, -r - w - 3, -(r + w + 3) * SY, r + w + 3, (r + w + 3) * SY, (x, y, out) => {
      const yy = y / SY, rr = Math.hypot(x, yy), a = Math.atan2(yy, x);
      const n = noise(a * 5 + rot, seed) + 0.5 * noise(a * 13 - rot, seed + 1);
      if (n < gap) return;
      const er = r + 1.8 * noise(a * 9, seed + 2);
      const d = er - rr;
      if (d < -0.6 || d > w) return;
      out.c = ramp[d < 0.8 ? 5 : clamp(Math.round(4 - 2 * d / w), 2, 4)];
      out.a = (d < 0.8 ? 0.9 : 0.55) * k * (0.6 + 0.4 * near(a));
    });
  }

  const strokes = [];   // curl / pulse / tide 的水纹：起点角度不等距
  const ns = mv === "curl" ? 4 : mv === "pulse" ? 2 : mv === "tide" ? 5 : mv === "aura" ? 3 : 0;
  for (let i = 0, a = Rg.range(0, TAU); i < ns; i++, a += TAU / ns + Rg.range(-0.5, 0.5)) strokes.push({ a, s: o.seed + 13 * i, d: Rg.range(0, 0.08), tw: Rg.range(0.25, 0.4) });

  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        if (mv === "fall" || mv === "burst") for (let i = 0; i < 18; i++) {   // 泡沫往上飘（不成圈）
          const x = Rg.range(-10, 10), y = Rg.range(-36, -6);
          ps.spawn(i % 3 ? P.MOTE : P.STAR, x, y, Rg.range(-18, 18), Rg.range(-50, -15), Rg.range(0.4, 0.8) * LIFE, NV[4 + Rg.int(0, 2)], Rg.range(0.7, 1.3), Rg.range(0, 0.2));
        }
        if (mv === "back") for (let i = 0; i < 16; i++) {   // 四周水沫往身上收
          const a = Rg.range(0, TAU), r = Rg.range(26, 40), x = Math.cos(a) * r, y = Math.sin(a) * r * SY - 16;
          ps.spawn(P.MOTE, x, y, -x * 3, -(y + 16) * 3, Rg.range(0.25, 0.35), NV[5 + Rg.int(0, 1)], Rg.range(0.8, 1.3), Rg.range(0, 0.1));
        }
        if (mv === "quake") {
          for (let i = 0; i < 22; i++) {
            const a = Rg.range(0, TAU), r = Rg.range(0.2, 0.9) * R, x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
            ps.spawn(i % 2 ? P.GRIT : P.SPARK, x, y, Rg.range(-10, 10), -Rg.range(40, 110), Rg.range(0.3, 0.6), i % 2 ? NV[2] : 0, Rg.range(0.8, 1.4), Rg.range(0, 0.08));   // 碎石从裂口往上蹦（§14.7 不往外甩）
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (!core) return;
      if (mv === "curl") for (const s of strokes) {   // 外圈水纹卷进锯口
        const u = t - s.d;
        if (u > 0) band(p, spiral(R, R * 0.55, s.tw, s.a), 2.6, ease.outCubic(clamp(u / 0.2)), smooth(0.14, 0.38, u), s.s, NV, true);
      }
      if (mv === "aura") {   // 断续海水边 + 里面往里流的水纹；一拍里亮起又回落（不外扩）
        const k = smooth(0, 0.12, t) * (1 - smooth(LIFE - 0.35, LIFE, t));
        brokenEdge(p, R, 3.2, k * (0.75 + 0.25 * (1 - smooth(0, 0.25, t))), o.seed, NV, t * 0.8 * dir, -0.25);
        for (const s of strokes) band(p, spiral(R * 0.92, R * 0.45, 0.22, s.a + dir * t * 0.6), 1.8, ease.outCubic(clamp((t - s.d) / 0.4)), smooth(0.35, LIFE, t - s.d), s.s, NV, false, 0.7);
      }
      if (mv === "tide") {   // 潮痕：断续边 + 内部细纹往里流，1.5 秒里慢慢褪
        const k = smooth(0, 0.15, t) * (1 - smooth(LIFE - 0.5, LIFE, t));
        brokenEdge(p, R, 2.4, k, o.seed + 40, TD, t * 0.3, -0.35);
        for (const s of strokes) band(p, spiral(R * 0.95, R * 0.35, 0.18, s.a), 1.4, ease.outCubic(clamp((t - s.d) / 0.6)), smooth(0.5, LIFE, t - s.d), s.s, TD, false, 0.6 * k);
      }
      if (mv === "pulse") for (const s of strokes) {   // 绕替身一圈的水旋，往里收
        const u = t - s.d;
        if (u > 0) band(p, spiral(R, R * 0.4, 0.75, s.a), 3.2, ease.outCubic(clamp(u / 0.16)), smooth(0.12, 0.34, u), s.s, NV, true);
      }
      if (mv === "quake") {   // 不规则分叉裂口：几条主裂（角度不等距、折线），各自再分叉；爆亮血红 → 暗红
        const k = 1 - smooth(LIFE * 0.55, LIFE, t), heat = 1 - smooth(0.05, 0.35, t);
        const g = ease.outCubic(clamp(t / 0.08));
        for (let i = 0, a = Rg.range(0, 1) + o.seed; i < 5; i++) {
          const a0 = (o.seed * 1.7 + i * 1.31 + noise(i * 3.3, o.seed) * 0.8) % TAU, L = R * (0.55 + 0.4 * (0.5 + 0.5 * noise(i * 5.1, o.seed + 4))) * g;
          let x = 0, y = 0, aa = a0;
          for (let d = 0; d < L; d += 1) {
            aa += 0.35 * noise(d * 0.15 + i * 7, o.seed + 9);
            x += Math.cos(aa); y += Math.sin(aa) * SY;
            const w = 1.4 * (1 - d / L) + 0.4;
            for (let q = -w; q <= w; q += 0.5) p.blendPx(p.cellX(x, y + q), p.cellY(x, y + q), Math.abs(q) > w - 0.5 ? BL[1] : BL[clamp(Math.round(2 + 3.5 * heat), 2, 6)], 0.9 * k);
            if (d > L * 0.35 && Math.abs(noise(d * 0.3 + i, o.seed + 21)) > 0.82 && d % 3 === 0) {   // 分叉（短）
              let bx = x, by = y, ba = aa + (noise(d, o.seed) > 0 ? 0.7 : -0.7);
              for (let e = 0; e < L * 0.25; e += 1) { bx += Math.cos(ba); by += Math.sin(ba) * SY; p.blendPx(p.cellX(bx, by), p.cellY(bx, by), BL[clamp(Math.round(2 + 2.5 * heat), 2, 5)], 0.85 * k); }
            }
          }
        }
      }
    },
    draw(p) {
      if (core && (mv === "fall" || mv === "appear")) {   // 水带绕身往上（倒下化替身 / 现身）
        for (let i = 0; i < 2; i++) {
          const u = t - i * 0.05, helix = (f) => { const a = i * 2.5 + dir * TAU * 1.1 * f; return [Math.cos(a) * 12 * (1 - 0.4 * f), Math.sin(a) * 12 * SY * 0.6 - 44 * f]; };
          if (u > 0) band(p, helix, 2.6, ease.outCubic(clamp(u / 0.22)), smooth(0.18, LIFE * 0.8, u), o.seed + 5 * i, NV, true);
        }
      }
      if (core && mv === "back") {   // 归队：一道水带从外往脚下收
        band(p, spiral(34, 4, 0.8, Rg.range(0, 0) + 0.7), 2.8, ease.outCubic(clamp(t / 0.22)), smooth(0.16, LIFE, t), o.seed, NV, true);
      }
      if (core && mv === "burst") {   // 消散：身形处的水带往上散开、断成几截（不画泡圈）
        for (let i = 0; i < 2; i++) {
          const helix = (f) => { const a = i * 2.9 + dir * TAU * 0.9 * f; return [Math.cos(a) * 10 * (1 + 0.6 * f), -12 + Math.sin(a) * 10 * SY * 0.6 - 40 * f - 20 * t]; };
          band(p, helix, 2.2, 1, smooth(0, LIFE, t + 0.05 * i), o.seed + 9 * i, NV, true, 1 - smooth(LIFE * 0.6, LIFE, t));
        }
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
