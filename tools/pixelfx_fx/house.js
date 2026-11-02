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
  eyjafjalla: ["#442f2c", "#824a2e", "#c16531", "#ff8033", "#ffac7a", "#ffd9c2", "#ffffff"],
  gladiia: ["#182f51", "#294a78", "#3a65a0", "#4c80c7", "#8bacdb", "#c9d9ee", "#ffffff"],
  hoshiguma: ["#413f32", "#7c6a3b", "#b79444", "#f2bf4c", "#f7d58b", "#fbecc9", "#ffffff"],
  irene: ["#413552", "#7c567b", "#b778a4", "#f299cc", "#f7bdde", "#fbe0f0", "#ffffff"],
  kaltsit: ["#284f40", "#498a55", "#6ac46a", "#8cff80", "#b4ffac", "#dcffd9", "#ffffff"],
  lappland: ["#3b475c", "#707a8e", "#a6adc0", "#dbe0f2", "#e8ebf7", "#f4f6fb", "#ffffff"],
  mizuki: ["#0d0e27", "#1e2766", "#284286", "#3d5fd6", "#8f9ae6", "#c9bdf0", "#ffffff"],
  logos: ["#28355f", "#495694", "#6a78ca", "#8c99ff", "#b4bdff", "#dce0ff", "#ffffff"],
  lumen: ["#28455f", "#497694", "#6aa8ca", "#8cd9ff", "#b4e6ff", "#dcf4ff", "#ffffff"],
  saria: ["#443d38", "#826646", "#c18f53", "#ffb861", "#ffd198", "#ffead0", "#ffffff"],
  siege: ["#444136", "#826e42", "#c19a4d", "#ffc759", "#ffdb93", "#ffeecd", "#ffffff"],
  skadi: ["#1b325c", "#30508e", "#446ec0", "#598cf2", "#93b4f7", "#cddcfb", "#ffffff"],
  skalter: ["#0a0610", "#24081a", "#460d22", "#6e122d", "#9c1b38", "#e9c9d0", "#ffffff"],
  specter_unchained: ["#34455c", "#62768e", "#91a8c0", "#bfd9f2", "#d5e6f7", "#ecf4fb", "#ffffff"],
  suzuran: ["#44433c", "#82724e", "#c1a261", "#ffd173", "#ffe1a4", "#fff1d5", "#ffffff"],
  texas: ["#44322c", "#82502e", "#c16e31", "#ff8c33", "#ffb47a", "#ffdcc2", "#ffffff"],
  ulpianus: ["#213c5c", "#3c638e", "#588ac0", "#73b2f2", "#a4cdf7", "#d5e8fb", "#ffffff"],
  wisadel: ["#411d2c", "#7c262e", "#b72f31", "#f23833", "#f77e7a", "#fbc3c2", "#ffffff"]
};

// ---- 时序（docs/229 §2.4–2.5）
export const FPS = { basic: 24, skill: 20, enemy: 20, ult: 20 };
export const DUR = { basicHit: 0.2, basicMuzzle: 0.15, skillMin: 0.3, skillMax: 0.6, enemyBurst: 0.4 };
// 亮暗节奏：首帧爆亮（返回 ≥ 1 的「热度」，0 帧 = 满热），之后按 cool 秒降到 0；色阶下标 = 最亮 - 热度损失
export const heat = (t, cool = 0.25) => 1 - clamp(t / cool);
export const HERO_FRAMES = 1;          // 爆亮只占 1 帧（最多 2 帧）

// ---- 体量（docs/229 §2.7）：刀光弧半径 / 伤害半径
export const REACH = { sweep: 0.85, line: 1.0, ring: 1.0, hitMax: 1.5 };
