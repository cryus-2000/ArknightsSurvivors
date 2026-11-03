// 塞雷娅琥珀晶簇「idle」段（时长 / 循环与主文件不同，只改 meta）
import { meta as base, create as make } from "./ak-saria-ul-calcite.js";

export const meta = { ...base, name: base.name + " (idle)", duration: 1.6, loop: true, options: { ...base.options, phase: "idle" } };
export const create = (o) => make({ ...o, phase: "idle" });
