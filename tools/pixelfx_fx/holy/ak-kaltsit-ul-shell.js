// 凯尔希「结构加固」外壳循环（时长 / 画布与主文件不同，只改 meta）：4 帧、游戏里 6 fps 循环（kaltsit.json s1_shell look：frames 4、anchor [24, 20]）
import { meta as base, create as make } from "./ak-kaltsit-ul-aura.js";

export const meta = { ...base, name: base.name + " (shell)", size: [48, 40], origin: [24, 46], duration: 4 / 6, fps: 6, options: { ...base.options, move: "shell" } };
export const create = (o) => make({ ...o, move: "shell" });
