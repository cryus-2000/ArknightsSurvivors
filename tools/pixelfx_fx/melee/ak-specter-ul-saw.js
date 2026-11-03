// 归溟幽灵鲨「锯刃」放开版（docs/242，开关 fx/px_unleashed）：贴身 360° 环斩，俯视地面透视（y × SY），原点 = 锯环圆心（脚底 + (0, -10) 世界像素）。
// 原作参照（build/ark_ref/specter_unchained，只作参照）：普攻 attack_start_01 = 锯头处一圈红橙火星锯齿；技能 3 skill_03_* = 深海蓝水带盘旋上卷 + 红锯。
// 本作配色：锯身钢蓝灰（武器 #A9A19B 偏冷）、水带取 PRTS 饰「蓝披带」#152E57 的海军蓝（和敌弹青 #33ceff 靠饱和 / 明度拉开）、
// S3 血锯取瞳色 #E4625C 压暗到 0–3° 色相（和敌方危险色 #ff2667 的 342° 品红拉开）。
// move：basic = 普攻环斩（E0 / E1 / E2 分档）；s3 = 生存的重压（只有 E2）。
//   E0：钢蓝锯痕一圈 + 锯头一段不等距锯齿 + 少量红橙火星。
//   E1：加「卷刃」——外圈一道海军蓝细水带螺旋向内收进锯痕（docs/91 精一卷刃：把外圈敌人吸近）。
//   E2：卷刃水带变成撕裂的宽水带，绕锯盘旋并往上卷起（原作 S3 的蓝水带盘旋），锯头白热齿光。
//   s3：锯身变厚、血红刃口、重齿、慢转 0.9 圈 + 宽水带 + 地面短撕痕（血红冷却成暗红）。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, TAU, noise } from "../../core/index.js";

export const meta = {
  name: "Specter saw ring unleashed",
  desc: "A ground-level 360-degree saw sweep: a steel cutting trace with uneven teeth at the head, navy water ribbons curling in, and a blood-red heavy saw for the pressure skill.",
  tags: ["melee", "saw", "spin", "water", "topdown", "one-shot"],
  size: [240, 180],
  origin: [120, 100],
  duration: 0.9,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    steel: ["#0b1222", "#1a2740", "#33476a", "#5d7396", "#93a8c4", "#cfdbe9", "#ffffff"],
    navy: ["#060d1f", "#0f2550", "#183f86", "#2a62b8", "#5b8fd6", "#a9c6ee", "#eef5ff"],
    blood: ["#140405", "#330a08", "#5e120c", "#8c1a12", "#b8301e", "#de7458", "#ffe8dc"],
    spark: ["#ffffff", "#ffd8b8", "#ff8a4a", "#e2502a"],
    ember: ["#160605", "#3e0e08", "#7a1e0c", "#b8361a", "#e45a2a", "#ffa47a", "#fff0e6"],   // 方案甲：照原作普攻的红橙火星锯（色相 8–18°，避开危险色 342° 与结晶淡金）
    tone: "steel",    // steel = 冷钢蓝（方案乙）/ ember = 红橙火星（方案甲）
    radius: 51,       // 判定半径 / PX（reach 102 → 51；s3 × 1.5 → 76.5），由 targets 的 judge 传
    sy: 0.55,         // 地面透视
    move: "basic",
    elite: 2,
    quick: 0,         // 1 = 队友版（余韵减半）
    layer: "all",
    seed: 3,
  },
};

export function create(o) {
  const ST = fit(o.tone === "ember" ? o.ember : o.steel, 7), NV = fit(o.navy, 7), BL = fit(o.blood, 7), SPK = fit(o.spark, 4);
  const Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), s3 = o.move === "s3", quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const R = +o.radius, SY = +o.sy;
  const DL = (s3 ? 1 : [0.45, 0.7, 1][el]) * (quick ? 0.5 : 1);     // 装饰余韵（docs/242 §10）
  const GK = s3 ? 1 : [0.35, 0.7, 1][el];                            // 光晕
  const PM = s3 ? 1.1 : [0.5, 0.8, 1][el];                           // 颗粒量
  const HOT = s3 ? 2 : [0.8, 1.6, 2.4][el];                          // 白热
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [SPK[0], SPK[1], SPK[2], SPK[3]], haze: NV[4] }), lights = new Lights();
  const dir = Rg.chance(0.5) ? 1 : -1;                              // 旋向（游戏里按朝向镜像）
  const SPIN = s3 ? 0.24 : 0.16;                   // 锯头转完的时长
  const TURN = s3 ? 0.9 : 1.12;                                      // 锯头转过的圈数
  const a0 = Rg.range(0, TAU);
  const W = R * (s3 ? 0.34 : [0.24, 0.27, 0.3][el]);   // 拖影宽（锯头后的扇形运动模糊）                          // 锯痕宽（1x 像素）
  const RAMP = s3 ? BL : ST;
  // 锯齿：不等距（jitter 步长）、大小不一、沿切向斜
  const teeth = [];
  for (let u = Rg.range(0, 0.1); u < 1; u += Rg.range(0.05, 0.11) * (s3 ? 1.3 : 1)) teeth.push({ u, h: Rg.range(0.7, 1.3) * (s3 ? 8 : 5), w: Rg.range(0.06, 0.1) });
  const at = (a, r) => [Math.cos(a) * r, Math.sin(a) * r * SY];      // 地面椭圆上的点
  const depth = (a) => 0.5 + 0.5 * Math.sin(a);                      // 近（下半）亮、远（上半）暗
  const headAng = (t) => a0 + dir * TAU * TURN * ease.outCubic(clamp(t / SPIN));
  // 水带（E1 细、E2 / s3 宽且上卷）：螺旋从外圈 rOut 收到 R，绕 span 圈；lift = 往上卷的高度
  const rib = el >= 1 || s3 ? {
    span: s3 ? 0.95 : el === 1 ? 0.62 : 0.8, rOut: R * 0.98, rIn: R * (s3 ? 0.5 : el === 1 ? 0.62 : 0.55), w: s3 ? 6 : el === 1 ? 3.4 : 4.8,   // 核心不出判定：从刃口往里卷
    lift: s3 ? R * 0.26 : el === 1 ? 0 : R * 0.22, b0: a0 - dir * Rg.range(0.6, 1.0), seed: o.seed + 21, t0: s3 ? 0.03 : 0.04, dur: s3 ? 0.3 : 0.24,
  } : null;
  const scars = [];   // s3 地面撕痕：短而不规整，方向沿切线 ± 抖动
  if (s3) for (let a = Rg.range(0, 1); a < TAU - 0.3; a += Rg.range(0.8, 1.6)) scars.push({ a, L: Rg.range(10, 20), r: R * Rg.range(0.82, 1.02), tw: Rg.range(-0.5, 0.5) });
  let t = 0, passed = 0, landed = false;

  function band(p, t) {   // 锯痕：锯头扫过的那段刃迹（头亮尾暗），首帧白热；随时间从尾部收掉
    const head = clamp(t / SPIN), tailK = smooth(SPIN * 0.4, SPIN + 0.22 * (0.6 + 0.4 * DL), t);
    const tot = TAU * TURN * ease.outCubic(head), VIS = TAU * (s3 ? 0.5 : 0.55);   // 只留锯头后约 0.7 圈：读成在转的锯，不读成闭合圆环
    const tl = Math.max(tot - VIS, tot * tailK);
    if (tot - tl < 0.02) return;
    const hot = t < 0.045 ? HOT : t < 0.09 ? 0.4 : 0;
    const B = R + W + 4;
    p.shade(-B, -B * SY - 2, B, B * SY + 2, (x, y, out) => {
      const yy = y / SY, r = Math.hypot(x, yy), ang = Math.atan2(yy, x);
      let u = (dir * (ang - a0)) % TAU;
      if (u < 0) u += TAU;
      // 第二圈的部分（tot > TAU）：取最靠锯头的那一层
      let s = u;
      while (s + TAU <= tot) s += TAU;
      if (s > tot || s < tl) return;
      const v = (s - tl) / Math.max(0.01, tot - tl);                // 0 尾 → 1 头
      const jag = 1.2 * noise(ang * 9, o.seed) + 0.7 * noise(ang * 23, o.seed + 5);
      const w = W * (0.3 + 0.7 * Math.pow(v, 0.9)) + jag * 0.6;
      const q = (R + 0.5 - r) / Math.max(0.6, w);                    // 0 外缘 → 1 内缘
      if (q < -0.15 || q > 1) return;
      const fib0 = noise(r * 0.32, o.seed + 41) + 0.3 * noise(s * 1.5, o.seed + 43);
      if (q > 0.35 && fib0 < -0.35 + 0.6 * q) return;                // 内侧碎成一条条纤维（不铺实色块）
      const dk = depth(ang);
      if (q < 0.18 && v > 0.15) { out.c = RAMP[hot > 1 ? 6 : v > 0.7 ? 5 : 4]; out.a = 1; return; }   // 外缘 1 格亮刃线
      const fib = noise(r * 1.3, o.seed + 31) + 0.5 * noise(r * 3.1 + s * 2, o.seed + 37);   // 沿转向的纤维纹（运动模糊感），只提亮
      let ci = Math.round(2.2 + 2.8 * v * (0.7 + 0.3 * dk) + hot * 0.8 - q * 1.4 + Math.max(0, fib) * 1.2);
      out.c = RAMP[clamp(ci, 1, 6)];
      out.a = (q > 0.55 ? 0.6 : 0.95) * (0.55 + 0.45 * v);
    });
  }

  function toothPts(p, t) {   // 锯头一段的锯齿：只在锯头附近 0.9 rad 内出现，跟着转
    const hA = headAng(t), k = 1 - smooth(SPIN, SPIN + 0.14, t), span = Math.min(TAU * (s3 ? 0.5 : 0.55), TAU * TURN * ease.outCubic(clamp(t / SPIN)));   // 锯齿铺满可见的拖影段
    if (k <= 0.02) return;
    for (const th of teeth) {
      const a = hA - dir * th.u * span;
      const fade = (1 - th.u * 0.8) * k;
      if (fade < 0.08) continue;
      const h = th.h * (0.6 + 0.4 * fade), dk = depth(a);
      // 三角齿：底在刃线上（宽 th.w rad），尖沿切向前倾、往外 h
      const [bx0, by0] = at(a, R), [bx1, by1] = at(a - dir * th.w, R), [tx, ty] = at(a + dir * th.w * 0.8, R + h);
      const hot = t < 0.05 && th.u < 0.3;
      const steps = Math.ceil(h * 1.6) + 2;
      for (let i = 0; i <= steps; i++) {
        const f = i / steps, lx = bx0 + (tx - bx0) * f, ly = by0 + (ty - by0) * f, rx = bx1 + (tx - bx1) * f, ry = by1 + (ty - by1) * f;
        const n = Math.ceil(Math.hypot(rx - lx, ry - ly) / 0.6) + 1;
        for (let j = 0; j <= n; j++) {
          const g = j / n, x = lx + (rx - lx) * g, y = ly + (ry - ly) * g, edge = j === 0 || f > 0.8;
          const ci = hot ? 6 : clamp(Math.round((edge ? 4 : 2) + 1.5 * dk + fade), 1, s3 ? 5 : 6);
          p.blendPx(p.cellX(x, y), p.cellY(x, y), RAMP[ci], (edge ? 1 : 0.85) * Math.min(1, fade * 1.6));
        }
      }
    }
  }

  function ribbon(p, t) {   // 水带：沿螺旋从外往里收（E1 平铺地面、E2 / s3 往上卷），边缘撕裂（noise），浪尖白沫
    if (!rib) return;
    const u = t - rib.t0;
    if (u < 0) return;
    const grow = ease.outCubic(clamp(u / rib.dur)), gone = smooth(rib.dur * 0.6, rib.dur + 0.32 * (0.5 + 0.5 * DL), u);
    if (grow - gone < 0.02) return;
    const N = Math.ceil(rib.span * TAU * rib.rOut / 0.55);
    for (let i = 0; i <= N; i++) {
      const f = i / N;                                               // 0 外端（起点）→ 1 内端
      if (f > grow || f < gone) continue;
      const a = rib.b0 + dir * rib.span * TAU * f, r = rib.rOut + (rib.rIn - rib.rOut) * ease.inOutSine(f);
      const lift = rib.lift * Math.sin(Math.PI * f) * (1 - gone);
      const [cx, cyg] = at(a, r), cy = cyg - lift;
      const head = clamp((grow - f) / 0.12);                           // 水带头部细、身体粗
      const tear = 0.55 + 0.45 * noise(f * 13, rib.seed) + 0.35 * noise(f * 31, rib.seed + 3);
      const w = rib.w * tear * Math.min(1, head * 1.4 + 0.2);
      if (w < 0.4) continue;
      // 法向（地面椭圆上的径向，抬起时偏竖直）
      const nx = Math.cos(a), ny = Math.sin(a) * SY + (rib.lift > 0 ? -0.6 : 0), nl = Math.hypot(nx, ny);
      const dk = depth(a);
      for (let d = -w; d <= w; d += 0.55) {
        const x = cx + nx / nl * d, y = cy + ny / nl * d, e = Math.abs(d) / w;
        const crest = d < -w + 1.1 && noise(f * 19, rib.seed + 7) > -0.1;   // 内侧浪尖白沫（断续）
        const groove = noise(f * 9 + d * 0.4, rib.seed + 11);
        const ci = crest ? (el >= 2 || s3 ? 6 : 5) : clamp(Math.round(1.5 + 2.4 * dk + 1.2 * groove - e * 1.2 + (t < 0.08 ? 1 : 0)), 1, 5);
        p.blendPx(p.cellX(x, y), p.cellY(x, y), NV[ci], (e > 0.8 ? 0.5 : 0.9) * (1 - 0.5 * clamp((f - gone) < 0.1 ? 1 - (f - gone) / 0.1 : 0)));
      }
    }
  }

  function scarDraw(p, t) {   // s3 地面撕痕：落刀处一道道短口子，血红 → 暗红冷却
    for (const s of scars) {
      const u = t - 0.06 - (dir * (s.a - a0) + TAU) % TAU / (TAU * TURN) * SPIN;
      if (u < 0 || u > 0.75) continue;
      const k = 1 - smooth(0.35, 0.75, u), ta = s.a + dir * Math.PI / 2 + s.tw;
      const [x0, y0] = at(s.a, s.r), L = s.L * ease.outCubic(clamp(u / 0.05));
      for (let d = 0; d < L; d += 0.5) {
        const f = d / s.L, x = x0 + Math.cos(ta) * (d - L / 2), y = y0 + Math.sin(ta) * (d - L / 2) * SY;
        const hw = 1.2 * Math.sin(Math.PI * Math.min(1, f)) + 0.3;
        const c = u < 0.08 ? BL[5] : u < 0.2 ? BL[4] : BL[2];
        for (let w = -hw; w <= hw; w += 0.6) p.blendPx(p.cellX(x, y + w), p.cellY(x, y + w), Math.abs(w) > hw - 0.6 ? BL[1] : c, 0.9 * k);
      }
    }
  }

  return {
    update(dt) {
      t += dt;
      // 锯头甩火星：沿切向往外，步长随机（不等距）
      const tot = TURN * ease.outCubic(clamp(t / SPIN));
      while (passed < tot && passed < TURN) {
        const a = a0 + dir * TAU * passed, [x, y] = at(a, R + 1), tx = -Math.sin(a) * dir, ty = Math.cos(a) * dir * SY;
        if (Rg.chance(0.75 * PM)) {
          const sp = Rg.range(120, 260);
          ps.spawn(P.SPARK, x, y, (tx * 0.85 + Math.cos(a) * 0.35) * sp, (ty * 0.85 + Math.sin(a) * 0.35 * SY) * sp - Rg.range(10, 50), Rg.range(0.12, 0.3) * (0.6 + 0.4 * DL));
        }
        if (deco && Rg.chance(0.35 * PM)) ps.spawn(P.MOTE, x, y, tx * Rg.range(30, 90), ty * Rg.range(30, 90) - 15, Rg.range(0.25, 0.5) * DL, (s3 ? BL : NV)[5], Rg.range(0.6, 1.1));
        passed += Rg.range(0.02, 0.07) / (s3 ? 1.2 : 1);
      }
      if (!landed && t >= SPIN) {
        landed = true;
        lights.add(0, 0, R * 1.2, (s3 ? BL : ST)[4], 0.12 * GK, 0.3);
        if (deco) for (let a = Rg.range(0, 0.3); a < TAU; a += Rg.range(0.2, 0.55) / PM) {   // 余韵：锯痕外缘散成水雾 / 碎光
          const [x, y] = at(a, R + Rg.range(-2, 3));
          ps.spawn(P.MOTE, x, y, Math.cos(a) * Rg.range(10, 40), Math.sin(a) * SY * Rg.range(10, 40) - Rg.range(4, 16), Rg.range(0.3, 0.6) * DL, NV[4 + Rg.int(0, 1)], Rg.range(0.6, 1.0), Rg.range(0, 0.06));   // 不用 VAPOUR（软圆团读成孤立圆点）
          if (el >= 1 && Rg.chance(0.35)) ps.spawn(P.STAR, x, y - Rg.range(0, 6), 0, -8, Rg.range(0.3, 0.6) * DL, (s3 ? BL : NV)[6], Rg.range(0.8, 1.4), Rg.range(0.03, 0.3) * DL);
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (core && s3) scarDraw(p, t);
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      const behindRib = core && rib;
      if (behindRib) ribbon(p, t);
      if (core) band(p, t);
      if (core) toothPts(p, t);
      if (deco && t < SPIN + 0.1) {   // 锯头光晕
        const [x, y] = at(headAng(t), R);
        p.glow(x, y, (s3 ? 30 : 20) * (el === 0 && !s3 ? 0.6 : 1), (s3 ? BL : ST)[5], 0.5 * GK * (1 - clamp((t - SPIN) / 0.1)));
      }
      if (deco) {
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
