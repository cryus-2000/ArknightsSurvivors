// 拉普兰德远程普攻「远掷」刀波弹体（docs/242 放开版，用户 11-03 定第 1 条）：俯视，原点 = 弹体中心，正右为飞行方向，游戏里按方向旋转。
// 弹体口径（seg_skadi proj_hold）：等宽 4 帧 —— 第 0 帧出手、第 1 帧飞行中一直停着、第 2–3 帧消散（命中 max_hits 或飞满距离）。
// 原作普攻远程 whitew_attack_02_trail（Claude outputs/pixelfx_ul_lappland/ref/）：贴地的一道暗色刀波，前沿一条白刃，身后拖暗影，
//   不是发光的弹丸。本作照这个写：暗灰的新月刀身（低于背景亮度一阶的冷灰），前沿 1 格白刃，内沿第二道细刃；身后几缕暗丝。
// 高度 = 判定宽 blade_w ÷ PX（targets judge 传 hw）。
// elite：E0 刀身 + 白刃；E1 刀身上烙一枚歪十字（精神摧毁封印）；E2 身后再跟一道错位的残刃（双生刃），白刃带原作淡蓝。
// 分层：core = 刀身、白刃、封印纹、残刃；deco = 暗丝、刃尖两三粒亮屑（克制，不铺光晕）。
import { Rng, fit, hex, clamp } from "../../core/index.js";

export const meta = {
  name: "Lappland thrown blade wave",
  desc: "A dark grey crescent blade wave with a single bright white leading edge and a thin inner edge, trailing a few dark threads; a seal mark at elite 1, a second offset ghost blade at elite 2.",
  tags: ["projectile", "blade", "topdown", "strip"],
  size: [60, 40],
  origin: [34, 20],
  duration: 0.16,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: ["#2b3036", "#52565a", "#868c8e", "#a9aeb3", "#c9ced3", "#e6eaee", "#ffffff"],   // 同 S2（原作 langtou_02 冷灰白）
    hw: 12.5,         // 判定半宽（1x），由 targets judge 覆盖
    elite: 2,
    quick: 0,         // 1 = 队友版（残刃 / 暗丝减半）
    layer: "all",
    seed: 11,
  },
};

export function create(o) {
  const C = fit(o.palette, 7), Rg = new Rng(o.seed), el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", BLUE = hex("#d6ebf6");
  const H = Math.min(+o.hw, 17);
  const threads = Array.from({ length: quick ? 2 : 4 }, () => ({ y: Rg.range(-H * 0.6, H * 0.6), L: Rg.range(10, 22), x0: Rg.range(-6, 0) }));
  const flecks = Array.from({ length: el + 1 }, () => ({ y: Rg.range(-H * 0.9, H * 0.9), x: Rg.range(-3, 3) }));
  let t = 0;
  // 新月：前沿 x = cx + R·cos，取 |y| ≤ H 的一段；刀身厚度从中间往两端收尖
  const blade = (p, cx, R, thick, ciEdge, ciBody, cut) => {
    for (let y = -H; y <= H; y += 1) {
      const u = y / H;
      if (cut && Math.abs(u) > cut) continue;
      const xe = cx + Math.sqrt(Math.max(0, R * R - y * y)) - R;   // 前沿
      const th = Math.max(1, Math.round(thick * (1 - u * u * 0.85)));
      for (let k = 1; k <= th; k++) p.dot(Math.round(xe) - k, y, C[k === th ? ciBody - 1 : ciBody]);
      p.dot(Math.round(xe), y, ciEdge);
      if (th >= 3 && Math.abs(u) < 0.7) p.dot(Math.round(xe) - th + 1, y, C[ciBody + 1]);   // 内沿第二道细刃
    }
  };
  return {
    update(dt) { t += dt; },
    draw(p) {
      const f = Math.min(3, Math.round(t * 20));   // 0 出手 / 1 飞行 / 2–3 消散
      const edge = el >= 2 && f === 1 ? BLUE : C[6];
      if (deco && f <= 2) for (const th of threads) {   // 身后暗丝：几根长短不一的横线，消散帧缩短
        const L = th.L * (f === 0 ? 0.5 : f === 2 ? 0.6 : 1);
        for (let k = 0; k < L; k++) p.blend(th.x0 - k, th.y, C[2], 0.6 * (1 - k / L));
      }
      if (core && el >= 2 && f >= 1 && f <= 2) blade(p, -6, H * 1.15, 4, C[f === 1 ? 4 : 3], 1, f === 2 ? 0.5 : 0.85);   // 双生刃：错后半个身位的暗残刃
      if (core) {
        if (f === 0) blade(p, 2, H * 1.05, 4, C[6], 3, 0.7);            // 出手：窄一点、白刃更亮
        else if (f === 1) blade(p, 6, H * 1.1, 7, edge, 2, 0);          // 飞行：整道新月
        else if (f === 2) blade(p, 8, H * 1.15, 4, C[5], 2, 0.75);       // 消散：刀身变薄、两端先断
        else blade(p, 10, H * 1.2, 2, C[3], 2, 0.4);                    // 最后一帧：只剩中段一缕
      }
      if (core && el >= 1 && f <= 1) {   // 精神摧毁：刀身上一枚歪十字（一长一短）
        p.line(-3, -3, 2, 3, C[6]); p.line(-2, 3, 1, -2, C[5]);
      }
      if (deco && f === 1) for (const q of flecks) p.blend(6 + q.x, q.y, C[5], 0.7);   // 刃尖两三粒亮屑
    },
  };
}
