// 方舟幸存者特效统一规范的 pixelfx 公共模块（docs/229）。各干员 / 敌方特效从这里取色板、密度、时序常量，不要各写各的。
// 改这里要经美术组组长；并行会话只读。
import { clamp } from "../core/index.js";

// ---- 密度（docs/229 §2.1）：1x 美术像素 = 2 世界像素（Game.PX）；@2x 帧条 1 贴图像素 = 1 世界像素
export const PX = 2;
export const SCALE_TOL = 0.1;          // 游戏里按半径适配时，每个 1x 像素占 PX × (1 ± 0.1) 世界像素以内

// ---- 环境与功能色（docs/229 §2.2，取自 balance render/optical_col_*，HSV → 十六进制）
export const ENV = ["#06142a", "#0b2d55", "#134f86", "#1f7fb5", "#3fb4d8", "#8fe3ef", "#d9fbff", "#ffffff"];   // 深海环境梯度（暗 → 亮）
export const DANGER = "#ff2667";       // 敌方危险色 optical_col_danger（h .95 s .85 v 1）
export const DANGER_RAMP = ["#2a0612", "#5c0a26", "#a3143f", "#ff2667", "#ff7aa0", "#ffd0dd", "#ffffff"];
export const BOSS = "#ff6726";         // optical_col_boss（h .05）
export const ENEMY = "#4dc9ff";        // 海嗣本体发光 optical_col_enemy（h .55）
export const EBULLET = "#33ceff";      // 敌弹 optical_col_ebullet
export const LAMP = "#ff9640";         // 我方灯火 optical_col_lamp（h .075）
export const LOOT = "#fff1bf";         // 掉落 optical_col_loot

// ---- 干员色阶（7 阶：暗 → 设定色 → 白）。初值由各干员 JSON 的 col 生成，接手的会话要按 PRTS 立绘核对（docs/87 §4.3）后再改这里
export const OP = {
  angelina: ["#312f5c", "#5c4a8e", "#8765c0", "#b280f2", "#cdacf7", "#e8d9fb", "#ffffff"],
  exusiai: ["#412232", "#7c303b", "#b73e44", "#f24c4c", "#f78b8b", "#fbc9c9", "#ffffff"],
  eyjafjalla: ["#1a0705", "#4a110a", "#8f1d0d", "#d2330f", "#f6561a", "#ff8a3d", "#fff0e0"],   // 11-04 组长 C 审定
  gladiia: ["#182f51", "#294a78", "#3a65a0", "#4c80c7", "#8bacdb", "#c9d9ee", "#ffffff"],
  hoshiguma: ["#413f32", "#7c6a3b", "#b79444", "#f2bf4c", "#f7d58b", "#fbecc9", "#ffffff"],
  irene: ["#413552", "#7c567b", "#b778a4", "#f299cc", "#f7bdde", "#fbe0f0", "#ffffff"],
  kaltsit: ["#1f3510", "#365c1a", "#548a22", "#7fb92e", "#b5e25a", "#e6f9a8", "#ffffff"],   // 11-04 组长 C 审定：黄绿（色相约 85°）
  kaltsit_melt: ["#2e0806", "#560c0a", "#84120e", "#b01c16", "#d8443a", "#f6d8d4", "#ffffff"],   // 11-04 组长 C 审定：熔毁红（色相 2–8°，明度压低）
  lappland: ["#3b475c", "#707a8e", "#a6adc0", "#dbe0f2", "#e8ebf7", "#f4f6fb", "#ffffff"],
  logos: ["#28355f", "#495694", "#6a78ca", "#8c99ff", "#b4bdff", "#dce0ff", "#ffffff"],
  lumen: ["#121a2a", "#1d3150", "#2a5282", "#4285ad", "#7fb2d6", "#c4e0f2", "#ffffff"],   // 11-04 美术组长：钢蓝，PRTS 挑染色 #4285AD；原组偏亮青，太靠近敌弹 #33ceff
  mizuki: ["#070a22", "#111a52", "#1e2f8f", "#3150c8", "#5a7cf0", "#9aa8ff", "#ffffff"],   // 11-04 组长：水月给的 8 色去掉 #dcdcff
  saria: ["#443d38", "#826646", "#c18f53", "#ffb861", "#ffd198", "#ffead0", "#ffffff"],
  siege: ["#1a0806", "#3f120a", "#7a1f0e", "#b9360f", "#e8581a", "#ff9a64", "#ffffff"],   // 11-04 组长 B 审定：熔铁
  skadi: ["#1b325c", "#30508e", "#446ec0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"],
  skalter: ["#3a0d1b", "#5e1424", "#86202d", "#a8323c", "#d2878d", "#f2d8da", "#ffffff"],   // 11-03 美术组 C：PRTS 主服 #B83139 压暗的酒红（build/prts_ref/_colors/skalter.png），中段 v≈0.66、色相 0.99–0.01，避开敌方危险色区 0.92–0.98
  skalter_sea: ["#06141c", "#0b2a35", "#124552", "#1b6466", "#3b8e89", "#86c6bd", "#e8f5f0"],   // 11-04 组长：浊心斯卡蒂原作海水蓝青
  specter_unchained: ["#060d1f", "#0f2550", "#183f86", "#2a62b8", "#5b8fd6", "#a9c6ee", "#eef5ff"],   // 11-04 组长
  suzuran: ["#3a1a10", "#7a3414", "#c2561a", "#ff8426", "#ffb257", "#ffdca6", "#ffffff"],   // 11-04 组长：暖橙（用户定）
  texas: ["#44322c", "#82502e", "#c16e31", "#ff8c33", "#ffb47a", "#ffdcc2", "#ffffff"],
  ulpianus: ["#0c1235", "#1b2a66", "#2c4397", "#4463c8", "#7b93e6", "#c0cbf6", "#ffffff"],   // 11-04 组长 C 审定
  ulpianus_blood: ["#1c0710", "#33101c", "#4d1626", "#6b1e33"],   // 11-04 组长 C：血纹暗段（4 阶）
  ulpianus_dust: ["#131528", "#212842", "#323c5e", "#4a5781", "#6b7ba6", "#9eabcf"],   // 11-04 组长 C：尘（6 阶）
  wisadel: ["#1a0b0f", "#3d1216", "#6e1a1d", "#bc2c2c", "#d9604a", "#f0b8a4", "#fff6f0"]   // 11-04 美术组长：PRTS 主服 #BC2C2C（build/prts_ref/_colors/wisadel.png）；原中段 #f23833 与危险色 #ff2667 色相 / 亮度太近，压暗、高光往暖白
};

// ---- 时序（docs/229 §2.4–2.5）
export const FPS = { basic: 24, skill: 20, enemy: 20, ult: 20 };
export const DUR = { basicHit: 0.2, basicMuzzle: 0.15, skillMin: 0.3, skillMax: 0.6, enemyBurst: 0.4 };
// 亮暗节奏：首帧爆亮（返回 ≥ 1 的「热度」，0 帧 = 满热），之后按 cool 秒降到 0；色阶下标 = 最亮 - 热度损失
export const heat = (t, cool = 0.25) => 1 - clamp(t / cool);
export const HERO_FRAMES = 1;          // 爆亮只占 1 帧（最多 2 帧）

// ---- 体量（docs/229 §2.7）：刀光弧半径 / 伤害半径
export const REACH = { sweep: 0.85, line: 1.0, ring: 1.0, hitMax: 1.5 };

// ---- 参照轮廓（docs/242 §9.2）：有原作形象的招式，外形由 tools/pixelfx_fx/ref/<人>_<招式>.png（1 位黑白，黑 = 形体内部）定死。
// 导出脚本把它读成 o.ref = { w, h, ox, oy, rows }（rows：每行一个字符串，"#" = 内部），代码只在轮廓内部做光流、碎裂、闪烁、生长。
// refMask(o) 返回 { inside(x, y), edge(x, y), w, h, ox, oy }，坐标是特效局部坐标（原点 = 参照图里标的原点）。
export function refMask(o, scale = 1) {
  const r = o.ref;
  if (!r) return null;
  const at = (x, y) => {
    const px = Math.floor(x / scale + r.ox), py = Math.floor(y / scale + r.oy);
    return py >= 0 && py < r.h && px >= 0 && px < r.w && r.rows[py][px] === "#";
  };
  return {
    w: r.w * scale, h: r.h * scale, ox: r.ox * scale, oy: r.oy * scale,
    inside: at,
    edge: (x, y) => at(x, y) && (!at(x - scale, y) || !at(x + scale, y) || !at(x, y - scale) || !at(x, y + scale)),
  };
}

// ---- 不规则工具（docs/242 §9.3：公共模块只给不规则的，不给等距阵列）
// 随机步长：在 [lo, hi] 里走，返回一串累加位置，直到 total
export function jitterSteps(rng, total, lo, hi) {
  const out = [];
  for (let x = rng.range(0, lo); x < total; x += rng.range(lo, hi)) out.push(x);
  return out;
}
// 抖动角度：n 个角度大致铺满 [a0, a1)，每个在等分位置上随机偏移 ± jit（0..0.5，按格宽比例）
export function jitterAngles(rng, n, a0, a1, jit = 0.4) {
  const w = (a1 - a0) / n, out = [];
  for (let i = 0; i < n; i++) out.push(a0 + (i + 0.5 + rng.range(-jit, jit)) * w);
  return out;
}

