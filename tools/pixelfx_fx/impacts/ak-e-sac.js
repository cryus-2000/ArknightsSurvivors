// 组 E 囊海爬行者破膜（docs/236）：同 ak-e-hit 的 goo 写法，只换画布——world.gd 按锚点 (0.5, 0.7) 摆在脚底、前后两层分画（_back 本体前、_front 本体后），
// 写死 6 帧 16 fps，所以导出用 keep 保留画布、原点放在 0.7 高处，opts.half = -1 / 1 分出后层 / 前层。
import { create as hitCreate, meta as hitMeta } from "./ak-e-hit.js";

export const meta = { ...hitMeta, name: "AK enemy sac burst", desc: "Pocket crawler sac bursting from above: a hot pop and goo thrown out and splattering, split into back and front layers.",
  size: [180, 160], origin: [90, 112], fps: 16 };
export const create = hitCreate;
