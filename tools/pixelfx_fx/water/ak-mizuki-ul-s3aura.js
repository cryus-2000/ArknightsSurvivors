// 水月循环件（s3aura）：画法在 ak-mizuki-ul-s2.js（move = s3aura），这里只给循环的 meta（时长 1.2 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-s2.js";

export const meta = { ...m0, name: "Mizuki s3aura", desc: "A rippling water patch at her feet while Moon in the Water lasts (loop).", size: [100, 60], origin: [50, 30], duration: 1.2, loop: true, options: { ...m0.options, move: "s3aura" } };

export function create(o) {
  return base({ ...o, move: "s3aura" });
}
