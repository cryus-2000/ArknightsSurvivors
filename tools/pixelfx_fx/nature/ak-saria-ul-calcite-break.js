// 塞雷娅琥珀晶簇「break」段（时长 / 循环与主文件不同，只改 meta）
import { meta as base, create as make } from "./ak-saria-ul-calcite.js";

export const meta = { ...base, name: base.name + " (break)", duration: 0.6, loop: false, options: { ...base.options, phase: "break" } };
export const create = (o) => make({ ...o, phase: "break" });
