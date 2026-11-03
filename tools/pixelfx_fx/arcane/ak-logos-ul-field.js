// 逻各斯 S3「延异视阈」扇形咒域地面（docs/242；开关 fx/px_unleashed），照原作 logos_skill3_range_01 还原（Claude outputs/logos_ref/）：
//   暗色墨地（AB 深蓝黑，半透明）、外缘一圈蓝色光带（原作 quan_blue / trail_65 的蓝外晕）、内侧一道暗紫光带（原作暖色内带改紫，避开结晶暖金）、
//   扇形四角各一颗暗色四芒星（原作 d_x_ab：star_164 AB + 蓝芯）、域内零星白色字符条闪现（原作 zifu_001）、冷白星点缓缓下落（原作 xxlizi，改冷白）。
// 原点 = 逻各斯脚底（圆形咒域 = 圆心），正右 = 扇形朝向；判定是正圆，帧条不压扁（sy 选项留给原作对照）。循环帧（游戏里按扇形朝向旋转、按当前半径 / R 缩放，开 / 收由代码淡入淡出）。
// 判定形状：半角 deg / 2、半径 R（judge：s3_fan_deg、range × s3_fan_r；外缘弧和两条边是核心层，内部填充与光归装饰层）。
import { Rng, fit, hex, clamp, smooth, noise, noise2, TAU } from "../../core/index.js";

export const meta = {
  name: "Logos acuity field",
  desc: "A dark ink fan of a domain on the ground: blue glowing rim, a violet inner band, dark four-point stars at the corners, white glyph strips flickering inside.",
  tags: ["arcane", "ink", "field", "ground", "loop"],
  size: [330, 330],
  origin: [165, 165],
  duration: 0.8,
  loop: true,
  fps: 15,   // 15 fps × 0.8 s 循环 = 12 帧（网页低档同帧数，不因抽帧变多；显存，docs/242 §11.1）
  bg: "dark",
  options: {
    palette: ["#07081a", "#11143a", "#1f2560", "#33407f", "#5b67a8", "#9aa3d6", "#dfe3f7", "#ffffff"],
    accent: "#a487ff",
    deg: 100,
    R: 150,
    sy: 1,     // 地面压扁（游戏里扇形 / 圆形判定是正圆，按朝向旋转画，所以缺省不压）
    circ: 0,   // 1 = 整圈圆形咒域（终结技「咒域宣判」，照原作 S3 的圆环墨域）
    layer: "all",
    seed: 5,
  },
};

const LOOP = 0.8;
const BAND = ["#.#.##.#..###.#.#.##..#", "###.#..##.#.#.##..#.#.#", "#.#.##.#..#.#.#.##.##.#"];

export function create(o) {
  const SY = +o.sy;
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), ACC = hex(o.accent);
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const circ = +o.circ > 0, H = circ ? Math.PI : (o.deg * Math.PI) / 360, R = o.R;
  // 四角暗星：扇形两个尖角（弧两端）+ 两条边中段各一颗（位置带抖动，不等距）
  const stars = (circ ? [0, 1, 2].map((i) => [R * Rg.range(0.75, 0.95), (i + Rg.range(0.1, 0.9)) * TAU / 3]) : [[R * 0.97, -H], [R * 0.97, H], [R * Rg.range(0.45, 0.55), -H * 0.98], [R * Rg.range(0.45, 0.55), H * 0.98]]).map(([r, a]) => ({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, L: Rg.range(7, 10), ph: Rg.range(0, TAU) }));
  // 白色字符条：位置、长短、亮灭时刻都随机
  const strips = [];
  for (let i = 0; i < (circ ? 16 : 9); i++) {
    const r = R * Rg.range(0.25, 0.9), a = Rg.range(-H * 0.85, H * 0.85);
    strips.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, n: Rg.int(8, 16), c0: Rg.int(0, 8), on: Rg.range(0, LOOP), len: Rg.range(0.3, 0.6) });
  }
  const motes = [];
  for (let i = 0; i < (circ ? 30 : 18); i++) {
    const r = R * Rg.range(0.15, 0.95), a = Rg.range(-H, H);
    motes.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, ph: Rg.range(0, LOOP), h: Rg.range(8, 18) });
  }
  let t = 0;
  const inFan = (x, y) => {   // 局部坐标（已压扁）→ 是否在扇形内，返回 [r / R, 角度 / 半角]
    const yy = y / SY, r = Math.hypot(x, yy), a = Math.atan2(yy, x);
    return [r / R, a / H];
  };
  return {
    update(dt) { t = (t + dt) % LOOP; },
    drawBack(p) {
      if (!deco) return;
      const ph = (t / LOOP) * TAU;
      for (let y = Math.floor(-R * SY - 4); y <= R * SY + 4; y++) for (let x = circ ? -R - 6 : -4; x <= R + 6; x++) {   // 真半透明（blend），不用 shade 的抖动
        const [rr, aa] = inFan(x, y);
        if (rr > 1.04 || Math.abs(aa) > 1.02) continue;
        const edgeR = 1 - rr, edgeA = 1 - Math.abs(aa), wob = noise2(x * 0.08 + Math.cos(ph) * 1.5, y * 0.12 + Math.sin(ph) * 1.5, 3);
        // 墨地：中间深、靠外略亮；浮动墨纹
        let c = C[0], a = 0.42 + 0.12 * wob;
        const ang = Math.atan2(y / SY, x), gapR = circ ? noise(ang * 1.7 + 5, 9) : 1, gapI = circ ? noise(ang * 2.3 + 1, 13) : 1;   // 圆形咒域：外缘 / 内带按角度断续（不成整环，§9.3 同心圈）
        if (rr > 0.86 + 0.05 * wob + (circ ? 0.06 * gapR : 0) && gapR > -0.15) { c = C[3]; a = 0.35 + 0.3 * (1 - edgeR / 0.14); }   // 外缘蓝光带
        else if (rr > 0.55 && rr < 0.68 + 0.04 * wob && gapI > -0.05 && !circ) { c = rr < 0.6 ? C[2] : ACC; a = 0.16 + 0.08 * Math.sin(ph + rr * 9); }   // 内侧暗紫带（原作暖色内带；圆形咒域不画，会成同心圈）
        else if (wob > 0.35) { c = C[1]; a = 0.5; }   // 墨纹
        if (!circ && edgeA < 0.06) { c = C[3]; a = Math.max(a, 0.45); }
        p.blend(x, y, c, clamp(a * (circ ? 1 : smooth(0, 0.08, rr)), 0, 1));
      }
      for (const m of motes) {   // 冷白星点缓缓下落、明灭
        const u = ((t - m.ph + LOOP) % LOOP) / LOOP, k = Math.sin(u * Math.PI);
        if (k > 0.3) p.dot(m.x, m.y - m.h * (1 - u), k > 0.85 ? C[7] : C[5], k);
      }
    },
    draw(p) {
      if (core) {
        // 判定边缘：外弧 + 两条边（1 格亮线，噪声断续 + 慢慢流动），弧上亮、边上淡一阶
        for (let a = -H; a <= H; a += 0.004) {
          const flow = noise(a * 9 - t * 6, 7);
          if (flow < -0.55 || (circ && noise(a * 1.3 + 2, 17) < -0.2)) continue;
          p.px(Math.cos(a) * R, Math.sin(a) * R * SY, C[flow > 0.4 ? 6 : 5]);
        }
        if (!circ) for (const s of [-1, 1]) for (let r = 6; r <= R; r += 0.7) {
          const flow = noise(r * 0.15 + t * 5 + s * 3, 11);
          if (flow < -0.4) continue;
          p.px(Math.cos(s * H) * r, Math.sin(s * H) * r * SY, C[flow > 0.45 ? 5 : 4]);
        }
        // 四角暗星（原作 d_x_ab：黑色四芒星 + 蓝芯，缓慢呼吸）
        for (const st of stars) {
          const k = 0.8 + 0.2 * Math.sin((t / LOOP) * TAU + st.ph), L = Math.round(st.L * k);
          for (let i = 0; i <= L; i++) {
            const ci = i < 2 ? 4 : i < L * 0.5 ? 1 : 0;
            p.px(st.x + i, st.y, C[ci]); p.px(st.x - i, st.y, C[ci]);
            if (i <= L * 0.6) p.px(st.x, st.y + i, C[ci]), p.px(st.x, st.y - i, C[ci]);
          }
        }
        // 白色字符条：一段段亮起、写出、熄灭
        for (const s of strips) {
          const u = ((t - s.on + LOOP) % LOOP);
          if (u > s.len) continue;
          const k = Math.min(1, u / 0.15), f = smooth(s.len * 0.6, s.len, u), n = Math.round(s.n * k);
          for (let c = 0; c < n; c++) for (let r = 0; r < 3; r++) {
            if (BAND[r][(s.c0 + c) % BAND[0].length] !== "#" || noise2(c, r + u * 9, 5) < f * 2 - 1) continue;
            p.px(s.x - s.n / 2 + c, s.y - 1 + r, c === n - 1 ? C[7] : f > 0.4 ? C[5] : C[6]);
          }
        }
      }
    },
  };
}
