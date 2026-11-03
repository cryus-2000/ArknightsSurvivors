// Mon3tr 精二身侧骨刃（只改 meta）：2 帧、游戏里 4 fps（kaltsit.json summons.mon3tr.fx side：frames 2、anchor [8, 12]）
import { meta as base, create as make } from "./ak-kaltsit-ul-aura.js";

export const meta = { ...base, name: base.name + " (blade)", size: [16, 24], origin: [8, 12], duration: 0.5, fps: 4, options: { ...base.options, move: "blade" } };
export const create = (o) => make({ ...o, move: "blade" });
