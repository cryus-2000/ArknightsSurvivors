// 塞雷娅琥珀晶簇「grow」段（时长 / 循环与主文件不同，只改 meta）
import { meta as base, create as make } from "./ak-saria-ul-calcite.js";

export const meta = { ...base, name: base.name + " (grow)", duration: 0.4, loop: false, options: { ...base.options, phase: "grow" } };
export const create = (o) => make({ ...o, phase: "grow" });
