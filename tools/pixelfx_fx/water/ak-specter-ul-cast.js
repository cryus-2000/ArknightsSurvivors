// 归溟幽灵鲨技能起手（docs/242 §12.1 起手信号；注册表 cast，vfx.px_ul_cast 在技能开启那一刻脚下播）。原点 = 脚底，侧视 + 地面透视（y × SY）。
// 原作参照（build/ark_ref/specter_unchained，只作参照）：
//   S1 skill_01_start：天上一道白光柱落在身上 + 脚下蓝水环 → 本作改成水旋往里收（用户 11-04：往外发散的光环一律不要）；
//   S2 skill_02_buff_01 / 03：海军蓝水带缠身 + 脚下一点红光；
//   S3 skill_03_start_01 / 02：重锤落地（锤体 Cone 网格）+ 蓝水带。
// move：s1 / s2 / s3；elite 0–2（S1 三档、S2 精一起、S3 只有精二）。E1 加一道水带，E2 水带变宽 + 白沫。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

// 真半透明着色（blendPx）：p.shade 的 out.a < 1 会抖成棋盘点，这里一律走 blendPx
const shadeB = (p, x0, y0, x1, y1, fn) => {
  const o = { c: 0, a: 1 };
  p.each(x0, y0, x1, y1, (x, y, sx, sy) => { o.c = 0; o.a = 1; const c = fn(x, y, o) || o.c; if (c && o.a > 0) p.blendPx(sx, sy, c, Math.min(1, o.a)); });
};

export const meta = {
  name: "Specter skill cast",
  desc: "Skill start cues: a falling pale shaft with a navy swirl drawing in, navy ribbons climbing around the body, and a heavy blood-red saw slamming down.",
  tags: ["water", "buff", "cast", "one-shot"],
  size: [140, 150],
  origin: [70, 118],
  duration: 0.9,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    navy: ["#060d1f", "#0f2550", "#183f86", "#2a62b8", "#5b8fd6", "#a9c6ee", "#eef5ff"],
    blood: ["#100204", "#2a0508", "#4e0a10", "#7a1018", "#a01c22", "#c84a44", "#f0c8c0"],   // 暗血红（色相 355–0°、中段 v≈0.63，和危险色 #ff2667 的亮品红拉开）
    ember: ["#160605", "#3e0e08", "#7a1e0c", "#b8361a", "#e45a2a", "#ffa47a", "#fff0e6"],
    steel: ["#16181d", "#2c3038", "#4a505b", "#767d88", "#a9a19b", "#d4d0cc", "#ffffff"],
    sy: 0.55,
    move: "s1",
    elite: 2,
    layer: "all",
    seed: 5,
  },
};

export function create(o) {
  const NV = fit(o.navy, 7), BL = fit(o.blood, 7), EM = fit(o.ember, 7), STL = fit(o.steel, 7);
  const Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), mv = o.move, SY = +o.sy;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const GK = [0.45, 0.75, 1][el], PM = [0.55, 0.8, 1][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [EM[6], EM[5], EM[5], EM[4]], haze: NV[4] }), lights = new Lights();
  const dir = Rg.chance(0.5) ? 1 : -1;
  let t = 0, fired = false;

  // 水带：沿 path(f) → [x, y]（f 0 尾 → 1 头）画一条宽 w(f) 的带子，边缘 noise 撕裂、内沿断续白沫；grow / gone 控制可见段
  function ribbon(p, path, w0, grow, gone, seed, foam) {
    if (grow - gone < 0.02) return;
    const N = 90;
    for (let i = 0; i <= N; i++) {
      const f = i / N;
      if (f > grow || f < gone) continue;
      const [x, y] = path(f), [x2, y2] = path(Math.min(1, f + 0.01));
      let tx = x2 - x, ty = y2 - y;
      const tl = Math.hypot(tx, ty) || 1;
      const nx = -ty / tl, ny = tx / tl;
      const tear = 0.55 + 0.45 * noise(f * 11, seed) + 0.3 * noise(f * 29, seed + 3);
      const head = clamp((grow - f) / 0.15), tail = clamp((f - gone) / 0.2);
      const w = w0 * tear * Math.min(1, head * 1.3 + 0.15) * Math.min(1, tail * 1.5 + 0.2);
      if (w < 0.4) continue;
      for (let d = -w; d <= w; d += 0.5) {
        const e = Math.abs(d) / w, crest = foam && d < -w + 1 && noise(f * 17, seed + 7) > 0;
        const groove = noise(f * 8 + d * 0.5, seed + 11);
        const ci = crest ? 6 : clamp(Math.round(2 + 2 * (1 - e) + 1.2 * groove), 1, 5);
        p.blendPx(p.cellX(x + nx * d, y + ny * d), p.cellY(x + nx * d, y + ny * d), NV[ci], e > 0.8 ? 0.5 : 0.92);
      }
    }
  }
  // 地面水旋：螺旋从外 r0 收到里 r1（往里收，不往外扩）
  const swirl = (r0, r1, turns, a0) => (f) => {
    const a = a0 + dir * TAU * turns * f, r = r0 + (r1 - r0) * ease.inOutSine(f);
    return [Math.cos(a) * r, Math.sin(a) * r * SY];
  };
  // 身体螺旋：绕身体往上爬
  const helix = (r, h, turns, a0, y0) => (f) => {
    const a = a0 + dir * TAU * turns * f;
    return [Math.cos(a) * r * (1 - 0.35 * f), y0 + Math.sin(a) * r * SY * 0.6 - h * f];
  };
  const SW1 = [swirl(30, 6, 0.9, Rg.range(0, TAU)), swirl(26, 8, 0.7, Rg.range(0, TAU))];
  const HX = [helix(13, 44, 1.3, Rg.range(0, TAU), 0), helix(11, 38, 1.1, Rg.range(0, TAU), -2), helix(15, 50, 1.5, Rg.range(0, TAU), 2)];

  return {
    update(dt) {
      t += dt;
      if (!fired && t >= (mv === "s3" ? 0.12 : 0.04)) {
        fired = true;
        if (mv === "s1") {
          lights.add(0, -20, 34, NV[5], 0.5 * GK, 0.3);
          if (el >= 1) for (let i = 0, n = Math.round(12 * PM); i < n; i++) ps.spawn(P.EMBER, Rg.range(-10, 10), Rg.range(-6, 0), Rg.range(-12, 12), Rg.range(-70, -30), Rg.range(0.4, 0.8), EM[4 + Rg.int(0, 2)], 1, Rg.range(0, 0.25));   // 灯火焰：红橙余烬往上飘
        } else if (mv === "s2") {
          lights.add(0, -2, 20, BL[4], 0.6 * GK, 0.5);
          for (let i = 0, n = Math.round(10 * PM); i < n; i++) ps.spawn(P.MOTE, Rg.range(-12, 12), Rg.range(-40, -4), Rg.range(-8, 8), Rg.range(-30, -10), Rg.range(0.4, 0.7), NV[5 + Rg.int(0, 1)], Rg.range(0.6, 1.1), Rg.range(0, 0.3));
        } else {
          lights.add(14, 0, 40, BL[4], 0.7, 0.35);
          for (let i = 0; i < 26; i++) {   // 砸地：火星与碎屑贴地往两侧溅（不成圈）
            const s = Rg.chance(0.5) ? 1 : -1, sp = Rg.range(60, 200);
            ps.spawn(i % 3 ? P.SPARK : P.GRIT, 14 + Rg.range(-4, 4), Rg.range(-2, 2), s * sp, -Rg.range(20, 110), Rg.range(0.2, 0.45), i % 3 ? 0 : STL[3 + Rg.int(0, 2)], Rg.range(0.7, 1.2));
          }
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) ps.draw(p, "back");
      if (core && (mv === "s1" || mv === "s3")) {   // 地面水旋（往里收）
        const n = mv === "s3" ? 2 : el >= 1 ? 2 : 1;
        for (let i = 0; i < n; i++) {
          const u = t - 0.03 - i * 0.05;
          if (u < 0) continue;
          ribbon(p, SW1[i], (mv === "s3" ? 4 : [2.4, 2.8, 3.4][el]) * (i ? 0.75 : 1), ease.outCubic(clamp(u / 0.22)), smooth(0.2, 0.55, u), o.seed + 31 * i, el >= 2 || mv === "s3");
        }
      }
      if (core && mv === "s3") {   // 砸地口子：两道短撕痕，血红冷成暗红
        const u = t - 0.12;
        if (u > 0 && u < 0.8) {
          const k = 1 - smooth(0.4, 0.8, u);
          for (const [a, L] of [[Rg.range(-0.3, -0.1), 24], [Math.PI + Rg.range(0.1, 0.3), 18]]) {
            for (let d = 0; d < L * ease.outCubic(clamp(u / 0.06)); d += 0.5) {
              const x = 14 + Math.cos(a) * d, y = Math.sin(a) * d * SY + noise(d * 0.4, o.seed + 5) * 1.2, hw = 1.3 * (1 - d / L) + 0.3;
              for (let w = -hw; w <= hw; w += 0.6) p.blendPx(p.cellX(x, y + w), p.cellY(x, y + w), Math.abs(w) > hw - 0.6 ? BL[1] : u < 0.1 ? BL[5] : BL[3], 0.9 * k);
            }
          }
        }
      }
    },
    draw(p) {
      if (core && mv === "s1") {   // 光柱：一道窄光从上落下，首帧白热，随后从上往下收
        const u = t, k = 1 - smooth(0.12, 0.38, u), top = -110 + 90 * smooth(0.05, 0.35, u);
        if (k > 0.02) shadeB(p, -6, top, 6, 0, (x, y, out) => {
          const hw = (2.2 + 1.6 * (1 + y / 110)) * (0.6 + 0.4 * k) * (1 + 0.15 * noise(y * 0.3, o.seed));
          if (Math.abs(x) > hw) return;
          const e = Math.abs(x) / hw;
          out.c = (u < 0.05 ? NV[6] : NV[clamp(Math.round(6 - e * 2.5 - (1 - k) * 2), 2, 6)]);
          out.a = (e > 0.7 ? 0.5 : 0.9) * k;
        });
      }
      if (core && mv === "s2") {   // 水带缠身：两到三道海军蓝水带绕身体往上爬
        const n = el >= 2 ? 3 : 2;
        for (let i = 0; i < n; i++) {
          const u = t - i * 0.06;
          if (u < 0) continue;
          ribbon(p, HX[i], [2.2, 2.6, 3.2][el], ease.outCubic(clamp(u / 0.28)), smooth(0.3, 0.7, u), o.seed + 17 * i, el >= 2);
        }
        const u = t;   // 脚下一点暗红（不倒）：贴地小椭圆，不扩散
        if (u < 0.8) {
          const k = smooth(0, 0.1, u) * (1 - smooth(0.45, 0.8, u));
          shadeB(p, -9, -4, 9, 4, (x, y, out) => {
            const r = Math.hypot(x / 9, y / 4) + 0.25 * noise(Math.atan2(y, x) * 3, o.seed + 41);
            if (r > 1) return;
            out.c = BL[r < 0.35 ? 5 : r < 0.7 ? 4 : 3];
            out.a = (r < 0.7 ? 0.85 : 0.5) * k;
          });
        }
      }
      if (core && mv === "s3") {   // 重锯从上方砸下：钢灰锯身 + 血红刃口，0.12 s 落地后停一下再淡出
        const u = t, land = 0.12, yy = u < land ? -90 * (1 - ease.inCubic(u / land)) : 0, k = 1 - smooth(0.32, 0.55, u);
        if (k > 0.02) {
          // 锯片斜着（透视压扁 + 倾斜）砸进地面：落地后下半截埋进地里，不画成一枚完整圆盘
          const cx = 14, cy = yy - 6, R = 15, RY = 7, tilt = -0.35 * dir, cs = Math.cos(tilt), sn = Math.sin(tilt);
          shadeB(p, cx - R - 5, cy - R - 5, cx + R + 5, cy + R + 5, (x, y, out) => {
            if (u >= land && y > 1.5) return;                              // 埋进地面的部分
            const lx = (x - cx) * cs + (y - cy) * sn, ly = (-(x - cx) * sn + (y - cy) * cs) / (RY / R);
            const r = Math.hypot(lx, ly), a = Math.atan2(ly, lx);
            const tooth = R + 3 * Math.max(0, Math.sin(a * 8 + u * 50 + 1.5 * noise(a * 3, o.seed)));
            if (r > tooth) return;
            if (r > R - 1.6) { out.c = r > R ? BL[u < land + 0.04 ? 6 : 4] : BL[5]; out.a = k; return; }
            if (r < 3) { out.c = STL[1]; out.a = k; return; }
            const mot = noise(r * 0.8 + u * 30, o.seed + 9);               // 转动的径向纹
            out.c = STL[clamp(Math.round(2 + 1.6 * (lx - ly) / (R * 2) + 1 + mot), 1, 5)];
            out.a = k;
          });
          if (u < land) for (let d = 0; d < 30; d += 0.6) p.blendPx(p.cellX(cx, cy - R - d), p.cellY(cx, cy - R - d), BL[4], 0.6 * (1 - d / 30));   // 落下拖光
        }
        const ur = t - 0.14;   // 水带从砸地点绕起
        if (ur > 0) ribbon(p, helix(18, 30, 0.8, Rg.range(0, 0) + 0.3, 0), 3.4, ease.outCubic(clamp(ur / 0.25)), smooth(0.25, 0.6, ur), o.seed + 61, true);
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
