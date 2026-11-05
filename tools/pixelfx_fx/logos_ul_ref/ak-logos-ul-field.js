// 逻各斯 S3「延异视阈」扇形咒域地面（docs/242；开关 fx/px_unleashed），照原作 logos_skill3_range_01 还原（Claude outputs/logos_ref/）：
//   暗色墨地（AB 深蓝黑，半透明）、外缘一圈蓝色光带（原作 quan_blue / trail_65 的蓝外晕）、内侧一道暗紫光带（原作暖色内带改紫，避开结晶暖金）、
//   扇形四角各一颗暗色四芒星（原作 d_x_ab：star_164 AB + 蓝芯）、域内零星白色字符条闪现（原作 zifu_001）、冷白星点缓缓下落（原作 xxlizi，改冷白）。
// 原点 = 逻各斯脚底（圆形咒域 = 圆心），正右 = 扇形朝向；判定是正圆，帧条不压扁（sy 选项留给原作对照）。循环帧（游戏里按扇形朝向旋转、按当前半径 / R 缩放，开 / 收由代码淡入淡出）。
// 判定形状：半角 deg / 2、半径 R（judge：s3_fan_deg、range × s3_fan_r；外缘弧和两条边是核心层，内部填充与光归装饰层）。
import { Rng, fit, hex, clamp, smooth, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

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
    palette: ["#07081a", ...OP.logos],   // house.js OP.logos（§14）
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
  // 贴地实心暗靛墨迹（总组长 11-04：取代半透明迷彩墨底 / 乱码字符条 / 冷白星点）：判定范围内散几摊不规则实心墨，墨与墨之间露地面（怪和敌弹看得清）
  const stains = [];
  const CSZ = [0.12, 0.08, 0.05];   // 圆形咒域（终结技）只散 3 小摊、大小拉开（总组长 11-04：9 块一样大散得太开 → 0.3 倍又太大，占半个屏幕高）
  for (let i = 0, n = circ ? 3 : 6, tries = 0; i < n && tries < 400; tries++) {
    const r = R * Math.sqrt(Rg.range(0.04, circ ? 0.45 : 0.72)), a = Rg.range(-H * 0.85, H * 0.85), sz = R * (circ ? CSZ[i] : Rg.range(0.09, 0.17));
    const x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
    if (stains.some((q) => Math.hypot(q.x - x, q.y - y) < (q.sz + sz) * 1.05)) continue;   // 不互相压成一大片
    stains.push({ x, y, sz, seed: Rg.range(0, 50), ph: Rg.range(0, TAU) });
    i++;
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
      if (!circ) for (const st of stains) p.glow(st.x, st.y, st.sz * 0.9, C[3], 0.12);   // 扇形墨迹边一点冷光（照地）；圆形咒域不画（实机读成灰蓝半透明边，总组长 11-04）
    },
    draw(p) {
      if (core) {
        // 判定边缘：外弧 + 两条边（1 格亮线，噪声断续 + 慢慢流动），弧上亮、边上淡一阶
        if (!circ) for (let a = -H; a <= H; a += 0.004) {
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
        // 实心墨迹：暗靛身（中心更深）、1 格蓝边，边缘随相位轻轻起伏（不外扩、不溶解）
        for (const st of stains) {
          const B = Math.ceil(st.sz * 1.3);
          for (let y = -B; y <= B; y++) for (let x = -B; x <= B; x++) {
            const a = Math.atan2(y, x), d = Math.hypot(x, y), rr = st.sz * (0.78 + 0.32 * noise(a * 2.1 + st.seed, 7) + 0.04 * Math.sin((t / LOOP) * TAU + st.ph + a));
            if (d > rr) continue;
            p.px(st.x + x, st.y + y, circ ? (d > rr - 1.1 ? C[1] : C[0]) : d > rr - 1.1 ? C[3] : d < rr * 0.5 ? C[0] : C[1]);   // 圆形咒域：实心墨黑芯 + 1 px 暗靛描边（总组长 11-04）
          }
        }
      }
    },
  };
}
