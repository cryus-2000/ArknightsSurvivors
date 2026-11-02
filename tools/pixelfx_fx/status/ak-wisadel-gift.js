// 维什戴尔好礼标记（D 组）：同 ak-wisadel-mark 的 gift 模式，单独成文件好按 6 帧 @10 导出。替换 fx_wisadel_gift_mark。
import { draw as mark, meta as base } from "./ak-wisadel-mark.js";

export const meta = { ...base, name: "Wisadel gift mark", desc: "The gift variant of Wisadel's mark: the inverted spinel with ember flecks drifting round it at uneven spacing.", duration: 0.6, fps: 10, options: { ...base.options, gift: 1 } };

export function draw(p, t, o) { mark(p, t, { ...o, gift: 1 }); }
