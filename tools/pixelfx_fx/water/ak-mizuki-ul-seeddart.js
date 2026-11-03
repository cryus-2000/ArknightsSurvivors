// 水月深蓝之籽循环件（dart）：画法在 ak-mizuki-ul-seed.js（move = dart），这里只给循环的 meta（时长 0.4 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-seed.js";

export const meta = { ...m0, name: "Mizuki seed dart", duration: 0.4, loop: true, options: { ...m0.options, move: "dart" } };

export function create(o) {
  return base({ ...o, move: "dart" });
}
