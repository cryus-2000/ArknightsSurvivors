// 组 E 骑士终局冰材质（docs/236）：final_boss_materials.gd 按固定画布、固定帧窗口、scale 1.0（1 纹素 = 1 世界像素）取帧，
// 所以按「形状 + 阶段」分别渲染，由 tools/pixelfx_fx/foe/fixed_e.py 裁固定框、重采样、拼成代码要的帧布局。原点 = 脚底（地面接触点）。
// shape：crystal 冰晶簇（主晶 + 2–3 根副晶，高低 / 粗细 / 倾角都随机）；crest 冰浪冠（低矮的一簇碎冰刺）；wall 冰墙段（一排高低不一的冰板）。
// phase：rise 从地面顶出（首帧根部爆亮）；hold 循环（高光沿棱走，首尾无缝）；break 碎裂（裂纹先亮 → 断成碎片下落、尘散开，末帧空）。
// 色：Boss 色阶（docs/229 §4，敌方不用深海青）；体量按调用处的世界像素（crystal 高 ≤ 110，crest 高 ≤ 26，wall 高 ≤ 56）。
import { Rng, clamp, ease, TAU, WHITE, hex, mix, crystal } from "../../core/index.js";
import { FPS } from "../house.js";

const BOSS_RAMP = ["#2a0e06", "#5c1d0a", "#a33814", "#ff6726", "#ffa07a", "#ffdcd0", "#ffffff"];
const GREY = hex("#6a6466");

export const meta = {
  name: "AK enemy ice",
  desc: "Final boss ice from above-front: faceted crystal clusters, a low crest of shards or a wall of slabs that thrust up, glint while held, and shatter into falling chips.",
  tags: ["ice", "enemy", "boss"],
  size: [96, 140],
  origin: [48, 132],
  duration: 0.5,
  loop: false,
  fps: FPS.enemy,
  bg: "ground",
  options: { shape: "crystal", phase: "rise", H: 100, seed: 1 },
};

export function create(o) {
  const RAMP = BOSS_RAMP.map(hex), Rn = new Rng(o.seed), S = o.shape, PH = o.phase, D = meta.duration;
  const RMP = [RAMP[1], RAMP[2], RAMP[3], RAMP[4], RAMP[5]];   // crystal() 用的明暗（暗 → 亮）
  const DU = [mix(RAMP[0], GREY, 0.3), mix(RAMP[1], GREY, 0.6), mix(RAMP[2], GREY, 0.7)];
  const H = o.H;
  // 晶体排布：主晶居中最高，副晶左右、矮一截、倾斜；冰墙是一排板（间距随机）；冰浪冠是 4–6 根矮刺
  const spikes = [];
  if (S === "crystal") {
    spikes.push({ x: 0, h: H, w: H * 0.16, lean: Rn.range(-0.08, 0.08) });
    for (let k = 0; k < Rn.int(2, 3); k++) spikes.push({ x: Rn.sign() * Rn.range(6, 16), h: H * Rn.range(0.35, 0.65), w: H * Rn.range(0.08, 0.12), lean: Rn.range(-0.35, 0.35) });
  } else if (S === "crest") {
    let x = -18;
    while (x < 18) { spikes.push({ x, h: H * Rn.range(0.45, 1.0), w: Rn.range(3, 5), lean: Rn.range(-0.4, 0.4) }); x += Rn.range(5, 10); }
  } else {
    let x = -28;
    while (x < 28) { spikes.push({ x, h: H * Rn.range(0.6, 1.0), w: Rn.range(6, 10), lean: Rn.range(-0.12, 0.12) }); x += Rn.range(7, 13); }
  }
  spikes.sort((a, b) => b.h - a.h);   // 高的先画（在后），矮的压在前
  const chips = spikes.flatMap((s) => Array.from({ length: Rn.int(2, 4) }, () => ({ x: s.x + Rn.range(-s.w, s.w), y0: -s.h * Rn.range(0.2, 0.9), vx: Rn.range(-30, 30), vy: Rn.range(-60, -10), r: Rn.range(0.6, 1.4), s: Rn.int(1, 3) })));
  let t = 0;
  return {
    update(dt) { t += dt; },
    draw(p) {
      const u = clamp(t / D);
      if (PH === "rise") {
        const g = ease.outBack(clamp(t / (D * 0.8)));
        for (const s of spikes) crystal(p, s.x, 0, s.h * g, s.w, s.lean * s.h * g, RMP, { glint: t < 0.12 ? 1 : 0 });
        if (t < 0.08) p.ellipse(0, 0, 10, 3, t < 0.04 ? WHITE : RAMP[4]);   // 顶出瞬间根部爆亮
        for (const c of chips) if (t < 0.3) p.rect(c.x + c.vx * t * 0.3, -2 + c.vy * t * 0.4, c.s, c.s, DU[2]);
        p.glow(0, -H * 0.3, H * 0.5, RAMP[3], 0.3 * (1 - u));
      } else if (PH === "hold") {
        const ph = (t / D) % 1;   // 循环：高光沿主晶棱从下往上走
        for (const s of spikes) crystal(p, s.x, 0, s.h, s.w, s.lean * s.h, RMP, { glint: 0 });
        const m = spikes[0], y = -m.h * (0.15 + 0.7 * ph), x = m.x + m.lean * m.h * (-y / m.h);
        p.line(x - 1, y + 2, x + 1, y - 2, RAMP[5]);
      } else {   // break：前 0.15 秒裂纹发亮，之后碎块下落散开
        const crack = clamp(t / 0.15), fall = clamp((t - 0.12) / (D - 0.12));
        if (fall <= 0) {
          for (const s of spikes) crystal(p, s.x, 0, s.h, s.w, s.lean * s.h, RMP, { glint: 0 });
          for (const s of spikes) for (let k = 0; k < 3; k++) {
            const y = -s.h * (0.2 + 0.25 * k) * crack;
            p.line(s.x - s.w * 0.6, y, s.x + s.w * 0.6, y - 2, k === 0 ? RAMP[5] : RAMP[4]);
          }
        } else {
          for (const s of spikes) {   // 断成 3 截，往下塌、外倒、边落边缩小，到底就没了（不透明，不用抖动淡出）
            if (fall > 0.85) continue;
            for (let k = 0; k < 3; k++) {
              const h0 = s.h * k / 3, h1 = s.h * (k + 1) / 3, dy = fall * fall * (40 + 30 * k), dx = (s.lean + (k - 1) * 0.3) * fall * 30;
              const sh = 1 - fall * 0.7, cy = -(h0 + h1) / 2 + dy, hh = (h1 - h0) / 2 * sh, ww = s.w * 0.5 * sh * (1 - k / 4);
              if (cy - hh > 0) continue;
              p.poly([[s.x - ww + dx, cy + hh], [s.x + ww + dx, cy + hh], [s.x + ww * 0.6 + dx, cy - hh], [s.x - ww * 0.6 + dx, cy - hh]], k === 2 ? RAMP[3] : fall < 0.4 ? RAMP[2] : RAMP[1]);
            }
          }
          for (const c of chips) {
            const tt = t - 0.12, x = c.x + c.vx * tt, y = Math.min(0, c.y0 + c.vy * tt + 300 * tt * tt);
            if (fall < 0.9) p.rect(x, y, c.s, c.s, y >= -0.5 ? DU[1] : RAMP[3]);
          }
          if (fall < 0.8) p.disc(0, -2, 14 * (0.5 + fall), DU[1], 0.3 * (1 - fall));   // 碎尘
        }
      }
    },
  };
}
