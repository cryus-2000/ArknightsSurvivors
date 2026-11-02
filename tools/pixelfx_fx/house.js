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

// ---- 干员色阶（7 阶：暗 → 设定色 → 白）。设定色按 PRTS 立绘（docs/87 §4.3）；低三阶 = 设定色 × 明度 35% / 60% / 80%、饱和度不降（docs/238，11-02）：
//      发光特效淡出靠 alpha，不往深海黑靠；深海暗阶 ENV 只给烟、碎石、焦痕。浊心斯卡蒂是用户定的暗色阶，例外
export const OP = {
  angelina: ["#3e2d55", "#6b4d91", "#8e66c2", "#b280f2", "#cdacf7", "#e8d9fb", "#ffffff"],
  exusiai: ["#551b1b", "#912e2e", "#c23d3d", "#f24c4c", "#f78b8b", "#fbc9c9", "#ffffff"],
  eyjafjalla: ["#592d12", "#994d1f", "#cc6629", "#ff8033", "#ffac7a", "#ffd9c2", "#ffffff"],
  gladiia: ["#1b2d46", "#2e4d77", "#3d669f", "#4c80c7", "#8bacdb", "#c9d9ee", "#ffffff"],
  hoshiguma: ["#55431b", "#91732e", "#c2993d", "#f2bf4c", "#f7d58b", "#fbecc9", "#ffffff"],
  irene: ["#553647", "#915c7a", "#c27aa3", "#f299cc", "#f7bdde", "#fbe0f0", "#ffffff"],
  kaltsit: ["#31592d", "#54994d", "#70cc66", "#8cff80", "#b4ffac", "#dcffd9", "#ffffff"],
  lappland: ["#4d4e55", "#838691", "#afb3c2", "#dbe0f2", "#e8ebf7", "#f4f6fb", "#ffffff"],
  mizuki: ["#15214b", "#253980", "#314cab", "#3d5fd6", "#8f9ae6", "#c9bdf0", "#ffffff"],
  logos: ["#313659", "#545c99", "#707acc", "#8c99ff", "#b4bdff", "#dce0ff", "#ffffff"],
  lumen: ["#314c59", "#548299", "#70aecc", "#8cd9ff", "#b4e6ff", "#dcf4ff", "#ffffff"],
  saria: ["#594022", "#996e3a", "#cc934e", "#ffb861", "#ffd198", "#ffead0", "#ffffff"],
  siege: ["#59461f", "#997735", "#cc9f47", "#ffc759", "#ffdb93", "#ffeecd", "#ffffff"],
  skadi: ["#1f3155", "#355491", "#4770c2", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"],
  skalter: ["#0a0610", "#24081a", "#460d22", "#6e122d", "#9c1b38", "#e9c9d0", "#ffffff"],
  specter_unchained: ["#434c55", "#738291", "#99aec2", "#bfd9f2", "#d5e6f7", "#ecf4fb", "#ffffff"],
  suzuran: ["#594928", "#997d45", "#cca75c", "#ffd173", "#ffe1a4", "#fff1d5", "#ffffff"],
  texas: ["#593112", "#99541f", "#cc7029", "#ff8c33", "#ffb47a", "#ffdcc2", "#ffffff"],
  ulpianus: ["#283e55", "#456b91", "#5c8ec2", "#73b2f2", "#a4cdf7", "#d5e8fb", "#ffffff"],
  wisadel: ["#551412", "#91221f", "#c22d29", "#f23833", "#f77e7a", "#fbc3c2", "#ffffff"]
};

// ---- 时序（docs/229 §2.4–2.5）
export const FPS = { basic: 24, skill: 20, enemy: 20, ult: 20, tail: 15 };   // tail：余韵段可降帧
export const DUR = { basicHit: 0.2, basicMuzzle: 0.15, skillMin: 0.3, skillMax: 0.6, enemyBurst: 0.4,
  basicTail: 0.15, skillTail: 0.6 };   // 余韵（docs/229 §2.5）：主体之后另给，alpha ≤ TAIL_ALPHA、像素稀疏
export const TAIL_ALPHA = 0.4;
// 光晕（docs/229 §2.7）：light 层单独导出成 <名>_glow 帧条、游戏里加色叠画，不再烤进颜色后量化。k = opts.light（导出缺省 0.5）；ring = 光晕半径 / 核心半径
export const GLOW = { k: 0.5, ring: 2.5 };
// 亮暗节奏：首帧爆亮（返回 ≥ 1 的「热度」，0 帧 = 满热），之后按 cool 秒降到 0；色阶下标 = 最亮 - 热度损失
export const heat = (t, cool = 0.35) => 1 - clamp(t / cool);
export const HERO_FRAMES = 1;          // 爆亮只占 1 帧（最多 2 帧）

// ---- 体量（docs/229 §2.7）：刀光弧半径 / 伤害半径
export const REACH = { sweep: 0.85, line: 1.0, ring: 1.0, hitMax: 1.5 };
