// 水月 S2 循环件（bind）：画法在 ak-mizuki-ul-s2.js（move = bind），这里只给循环的 meta（时长 0.8 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-s2.js";

export const meta = { ...m0, name: "Mizuki S2 bind", desc: "A small tendril coils round a bound enemy's feet (loop).", size: [60, 40], origin: [30, 28], duration: 0.8, loop: true, options: { ...m0.options, move: "bind" } };

export function create(o) {
  return base({ ...o, move: "bind" });
}
