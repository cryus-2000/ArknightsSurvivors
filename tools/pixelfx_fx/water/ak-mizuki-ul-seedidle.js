// 水月深蓝之籽循环件（idle）：画法在 ak-mizuki-ul-seed.js（move = idle），这里只给循环的 meta（时长 0.8 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-seed.js";

export const meta = { ...m0, name: "Mizuki seed idle", duration: 0.8, loop: true, options: { ...m0.options, move: "idle" } };

export function create(o) {
  return base({ ...o, move: "idle" });
}
