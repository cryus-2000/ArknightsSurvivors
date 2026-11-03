// 流明终结技光柱稳住段（pixelfx 放开版，docs/242）：无缝循环 0.4 s，接在 ak-lumen-ul-ult-beacon（冲起 + 点亮）之后，持续 ult/lu_dur。
// 画法与 beacon 共用（白芯 + 钢蓝边轻微呼吸、顶端四芒灯光缓慢明暗）；熄灭由游戏里淡出。原点 = 队长脚底。
import { create as beacon, meta as bm } from "./ak-lumen-ul-ult-beacon.js";

export const meta = { ...bm, name: "Lumen ultimate beacon hold unleashed", desc: "The lighthouse beam holding steady, its lamp slowly breathing.", duration: 0.4, loop: true };

export function create(o) {
  const b = beacon(o, true);
  let t = 0.55;
  return {
    update(dt) { t += dt; b.update(dt); },
    draw(p) { b.draw(p); },
  };
}
