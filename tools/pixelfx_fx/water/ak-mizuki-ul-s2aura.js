// 水月 S2 循环件（aura）：画法在 ak-mizuki-ul-s2.js（move = aura），这里只给循环的 meta（时长 1.2 秒、首尾相接）。
import { create as base, meta as m0 } from "./ak-mizuki-ul-s2.js";

export const meta = { ...m0, name: "Mizuki S2 aura", desc: "Two tentacles sway behind Mizuki while Prisoner's Dilemma lasts (loop).", size: [200, 180], origin: [100, 120], duration: 1.2, loop: true, options: { ...m0.options, move: "aura" } };

export function create(o) {
  return base({ ...o, move: "aura" });
}
