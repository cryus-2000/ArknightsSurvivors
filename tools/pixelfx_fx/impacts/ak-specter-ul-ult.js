// 归溟幽灵鲨终结技「弹射撕裂」放开版件（设计用户 10-30 / 10-31 已定稿：弹射时每处一把小锯 → 收尾一把血色巨锯落地磨地 → 猛地横切过整片敌群；这里只换画风）。
// 编排在 game/scripts/run/ult_fx_specter.gd（照 ult_fx_c.sb_* 的时序），这里出各件帧条。俯视地面透视（y × SY）。
// move：
//   minisaw 弹射落点的小锯（缓出放大、快转、刃口血红、甩火星），原点 = 锯心
//   dash    弹射血线：沿 +x 一道细血线，头亮尾暗、从尾部收掉，原点 = 中点（代码按长度 sx 拉伸）
//   tear    落点撕痕：一道短口子，血红爆亮冷成暗红，原点 = 中心
//   bigsaw  收尾巨锯：落地一帧白热 → 狂转磨地、一侧甩火星，原点 = 锯心
//   cut     横切：一帧伸满的白热切口 → 血红 → 上下错开成两半、两侧喷碎屑，原点 = 中点
//   scar    切痕：地上留一道深切口慢慢冷却（低帧率），原点 = 中点
// 不画往外扩的光环（用户 11-04）；锯身是有齿的转动锯片（运动模糊 + 刃口），不是实心圆盘。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

// 真半透明着色（blendPx）：p.shade 的 out.a < 1 会抖成棋盘点
const shadeB = (p, x0, y0, x1, y1, fn) => {
  const o = { c: 0, a: 1 };
  p.each(x0, y0, x1, y1, (x, y, sx, sy) => { o.c = 0; o.a = 1; const c = fn(x, y, o) || o.c; if (c && o.a > 0) p.blendPx(sx, sy, c, Math.min(1, o.a)); });
};

export const meta = {
  name: "Specter ultimate pieces",
  desc: "Pieces for a bouncing saw rampage: small biting saws, blood streaks, tears, a giant blood saw grinding the ground and one clean cross-cut.",
  tags: ["impact", "saw", "slash", "ultimate", "one-shot"],
  size: [240, 170],
  origin: [120, 85],
  duration: 1.0,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    steel: ["#16181d", "#2c3038", "#4a505b", "#767d88", "#a9a19b", "#d4d0cc", "#ffffff"],
    blood: ["#100204", "#2a0508", "#4e0a10", "#7a1018", "#a01c22", "#c84a44", "#f0c8c0"],
    spark: ["#ffffff", "#ffd8b8", "#ff8a4a", "#e2502a"],
    sy: 0.55,
    move: "minisaw",
    seed: 3,
    layer: "all",
  },
};

export function create(o) {
  const STL = fit(o.steel, 7), BL = fit(o.blood, 7), SPK = fit(o.spark, 4);
  const Rg = new Rng(o.seed), mv = o.move, SY = +o.sy;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [SPK[1], SPK[2], SPK[2], SPK[3]], haze: BL[3] }), lights = new Lights();   // 火星不用纯白（巨锯甩火星时间长，纯白会连成「持续白」）
  const dir = Rg.chance(0.5) ? 1 : -1;
  let t = 0, fired = false;
  const big = mv === "bigsaw", R = big ? 70 : 34;
  const LIFE = { minisaw: 0.32, bigsaw: 0.85, dash: 0.3, tear: 0.9, cut: 0.5, scar: 2.0 }[mv] || 0.5;
  const teethN = [];   // 不等距齿
  for (let a = Rg.range(0, 0.3); a < TAU - 0.15; a += Rg.range(0.22, 0.42) * (big ? 0.6 : 1)) teethN.push({ a, h: Rg.range(0.7, 1.3) * (big ? 9 : 5.5) });

  function saw(p, t) {   // 转动的锯片：刃口（血红亮边）+ 齿 + 锯身运动模糊（半透明、带径向纹）+ 轴心
    const grow = big ? (t < 0.06 ? 1.12 - 0.12 * t / 0.06 : 1) : 0.6 + 0.4 * ease.outCubic(clamp(t / 0.05));
    const k = 1 - smooth(LIFE - (big ? 0.4 : 0.1), LIFE, t), rot = dir * t * (big ? 28 : 40);
    const r0 = R * grow, hot = t < 0.05;
    if (k <= 0.02) return;
    const B = r0 + (big ? 12 : 7);
    shadeB(p, -B, -B * SY - 2, B, B * SY + 2, (x, y, out) => {
      const yy = y / SY, r = Math.hypot(x, yy), a = Math.atan2(yy, x);
      let tooth = 0;
      for (const th of teethN) {
        let d = ((a - rot - th.a) % TAU + TAU) % TAU;
        if (d < 0.16) { tooth = Math.max(tooth, th.h * (1 - d / 0.16)); }   // 斜齿：前缘陡、后缘缓
      }
      if (r > r0 + tooth) return;
      const near = 0.5 + 0.5 * Math.sin(a);                         // 近亮远暗
      if (r > r0 - 1.5) { out.c = hot ? BL[6] : (r > r0 ? BL[4 + (near > 0.5 ? 1 : 0)] : BL[5]); out.a = k; return; }   // 刃口 + 齿
      if (r < r0 * 0.14) { out.c = STL[1]; out.a = k; return; }      // 轴心
      const streak = noise(r * 0.7 + rot * 2, o.seed + 9) + 0.5 * noise(a * 3 - rot, o.seed + 11);   // 运动模糊的周向纹
      if (r < r0 * 0.24) { out.c = STL[3]; out.a = k; return; }
      const ci = clamp(Math.round(2 + 1.5 * near + streak * 1.2 + (hot ? 2 : 0)), 1, 5);
      out.c = big && streak < 0.25 ? BL[clamp(ci, 1, 4)] : STL[ci];   // 巨锯：锯身掺暗血红（血色巨锯），亮纹仍是钢色
      out.a = (0.55 + 0.3 * near) * k;
    });
  }

  function line(p, t, L, W, cool) {   // 沿 +x 的血线：头亮尾暗、尾部收掉、边缘 noise 起伏
    const head = mv === "dash" ? ease.outExpo(clamp(t / 0.05)) : 1, tail = smooth(0.06, LIFE, t);
    const x0 = L * (tail - 0.5), x1 = L * (head - 0.5);
    if (x1 - x0 < 1) return;
    shadeB(p, x0 - 1, -W - 3, x1 + 1, W + 3, (x, y, out) => {
      const v = (x - x0) / Math.max(1, x1 - x0), w = W * (0.3 + 0.7 * Math.sin(Math.PI * Math.min(1, 0.15 + v * 0.85))) * (1 + 0.25 * noise(x * 0.3, o.seed + 3));
      const e = Math.abs(y) / Math.max(0.5, w);
      if (e > 1) return;
      const h = t < 0.05 ? 2 : t < 0.12 ? 1 : 0;
      out.c = e > 0.7 ? BL[2] : BL[clamp(Math.round(3 + 2 * v + h - cool * smooth(0.1, LIFE, t) * 2), 2, 6)];
      out.a = (e > 0.7 ? 0.6 : 0.95) * (1 - smooth(LIFE * 0.7, LIFE, t) * 0.5);
    });
  }

  function slit(p, t, L, W, x0) {   // 地面口子：中间宽两头尖，爆亮后冷成暗红（tear / scar）
    const grow = ease.outCubic(clamp(t / 0.05)), k = 1 - smooth(LIFE * 0.6, LIFE, t);
    if (k <= 0.02) return;
    const Lg = L * grow;
    shadeB(p, x0 - 1, -W - 2, x0 + Lg + 1, W + 2, (x, y, out) => {
      const v = (x - x0) / Math.max(1, L);
      if (v < 0 || v > grow) return;
      const w = W * Math.pow(Math.sin(Math.PI * v), 0.6) + 0.3 + 0.6 * noise(x * 0.5, o.seed + 13);
      const yc = 1.2 * noise(x * 0.12, o.seed + 17);
      const e = Math.abs(y - yc) / Math.max(0.4, w);
      if (e > 1) return;
      const heat = 1 - smooth(0.04, LIFE * 0.4, t);
      out.c = e > 0.65 ? BL[1] : BL[clamp(Math.round(2 + 3.5 * heat * (1 - e)), 1, 6)];
      out.a = (e > 0.65 ? 0.8 : 0.95) * k;
    });
  }

  return {
    update(dt) {
      t += dt;
      if (!fired) {
        fired = true;
        if (mv === "minisaw" || mv === "bigsaw") {
          lights.add(0, 0, R * 0.9, BL[4], big ? 0.45 : 0.3, big ? 0.3 : 0.15);
        } else if (mv === "cut") {
          for (let x = Rg.range(-105, -97); x < 105; x += Rg.range(5, 14)) {   // 切口两侧往两边喷碎屑 / 火星（步长随机）
            const s = Rg.chance(0.5) ? 1 : -1, sp = Rg.range(80, 220);
            ps.spawn(Rg.chance(0.6) ? P.SPARK : P.GRIT, x, s * 3, Rg.range(-30, 30), s * sp * SY, Rg.range(0.2, 0.45), Rg.chance(0.5) ? STL[3] : BL[4], Rg.range(0.7, 1.3));
          }
        }
      }
      if ((mv === "minisaw" || mv === "bigsaw") && t < LIFE - 0.12) {   // 锯缘一侧往切向甩火星
        const n = big ? 3 : 1;
        for (let i = 0; i < n; i++) if (Rg.chance(big ? 0.9 : 0.7)) {
          const a = Rg.range(0.2, 1.4) * (Rg.chance(0.5) ? 1 : -1) + Math.PI * 0.5, x = Math.cos(a) * R, y = Math.sin(a) * R * SY;
          const tx = -Math.sin(a) * dir, sp = Rg.range(120, 260) * (big ? 1.3 : 1);
          ps.spawn(P.SPARK, x, y, tx * sp, -Rg.range(20, 90), Rg.range(0.15, 0.35));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (core && mv === "tear") slit(p, t, 36, 2.2, -18);
      if (core && mv === "scar") slit(p, t, 210, 2.6, -105);
      if (core && big && t > 0.04) {   // 磨地：锯下一道被磨亮的地面（偏一侧的短弧，不是圆环）
        const k = smooth(0.04, 0.1, t) * (1 - smooth(LIFE - 0.3, LIFE, t));
        for (let a = 0.15 * Math.PI; a < 0.85 * Math.PI; a += 0.012) {
          const n = noise(a * 9, o.seed + 31);
          if (n < -0.2) continue;
          const x = Math.cos(a) * (R + 2), y = Math.sin(a) * (R + 2) * SY + 2;
          p.blendPx(p.cellX(x, y), p.cellY(x, y), BL[n > 0.4 ? 4 : 2], 0.8 * k);
        }
      }
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (core && (mv === "minisaw" || big)) saw(p, t);
      if (core && mv === "dash") line(p, t, 104, 2.4, 1);
      if (core && mv === "cut") {   // 横切：0–0.05 一帧伸满白热 → 血红 → 0.12 起上下错开成两半
        const split = 4 * ease.outCubic(clamp((t - 0.12) / 0.15));
        if (t < 0.12) line(p, t, 212, 6, 0.5);
        else { const tx = p.tx, ty = p.ty; p.place(tx, ty - split); line(p, t, 212, 3.4, 1); p.place(tx, ty + split); line(p, t, 212, 3.4, 1); p.place(tx, ty); }
      }
      if (deco && (mv === "minisaw" || big) && t < 0.18) p.glow(0, 0, R * 0.8, BL[4], (big ? 0.5 : 0.35) * (1 - t / 0.18));
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
