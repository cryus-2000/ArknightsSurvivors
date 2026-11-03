// 水月终结技大水母浮游循环件：画法在 ak-mizuki-ul-ujelly.js（move = float），这里只给循环的 meta（1 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-ujelly.js";

export const meta = { ...m0, name: "Mizuki ult jellyfish float", duration: 1.0, loop: true, options: { ...m0.options, move: "float" } };

export function create(o) {
  return base({ ...o, move: "float" });
}
