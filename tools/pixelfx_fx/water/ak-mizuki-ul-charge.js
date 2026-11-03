// 水月循环件（charge）：画法在 ak-mizuki-ul-s2.js（move = charge），这里只给循环的 meta（时长 1.0 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-s2.js";

export const meta = { ...m0, name: "Mizuki charge", desc: "Two tentacle tips peek from the ground at her feet while Awaken is charged (loop).", size: [60, 50], origin: [30, 38], duration: 1.0, loop: true, options: { ...m0.options, move: "charge" } };

export function create(o) {
  return base({ ...o, move: "charge" });
}
