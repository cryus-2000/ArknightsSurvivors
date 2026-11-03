// 变细样张 B（PX 1）：同一刀光，几何 ×2、像素图元不放大，画布 520；游戏里按 @2x 缩回。只出样张，未铺开（11-03）
import { meta as M, create } from "./ak-skadi-ul-slash.js";

export const meta = { ...M, name: "Skadi slash unleashed (PX 1 sample)", size: [520, 520], origin: [260, 260], options: { ...M.options, px2: 1 } };
export { create };
