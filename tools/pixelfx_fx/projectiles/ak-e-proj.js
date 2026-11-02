// 组 E 敌方弹体循环帧条（docs/229 §2.5 弹道档：循环 ≤ 4 帧、首尾无缝；docs/236）。原点 = 弹体中心，朝 +x（游戏按飞行方向旋转）。
// kind：spore 孢子团（不规则软团 + 2–3 缕拖尾，轻微鼓缩）；orb 侵蚀弹（实心核 + 冒泡拖尾）；glob 抛物酸团（翻滚的不规则团，自带高光转圈）；
// shard 冰棱弹（细长多面晶体，刃口高光沿长边走）。R = 弹体半长（纹素）。色：DANGER_RAMP；boss = 1 用 Boss 色阶。
// 纯函数写法（draw(p, t, o)），按 cycle 相位画，导出 4 帧刚好一圈。
import { clamp, TAU, WHITE, hex, mix } from "../../core/index.js";
import { DANGER_RAMP, FPS } from "../house.js";

const BOSS_RAMP = ["#2a0e06", "#5c1d0a", "#a33814", "#ff6726", "#ffa07a", "#ffdcd0", "#ffffff"];
const GREY_RAMP = ["#262626", "#4a4a4a", "#737373", "#9e9e9e", "#c8c8c8", "#ececec", "#ffffff"];   // ramp: "grey"：中性灰阶，给代码按弹色着色的件（Boss 弹迸散 / 拖尾）


export const meta = {
  name: "AK enemy projectile",
  desc: "Enemy projectile loop seen from above, facing right: a spore puff, a corrosive orb with a bubbling tail, a tumbling acid glob or a faceted ice shard, in the danger ramp.",
  tags: ["projectile", "enemy", "loop"],
  size: [40, 24],
  origin: [24, 12],
  duration: 0.2,
  loop: true,
  fps: FPS.enemy,
  bg: "ground",
  options: { R: 6, kind: "orb", boss: 0, ramp: "", seed: 1 },
};

// 一组固定的抖动（按种子），保证轮廓不规整但每帧一致
function jit(seed, n) {
  let s = seed * 9301 + 49297;
  return Array.from({ length: n }, () => ((s = (s * 9301 + 49297) % 233280) / 233280));
}

export function draw(p, t, o) {
  const RAMP = (o.ramp === "grey" ? GREY_RAMP : o.boss ? BOSS_RAMP : DANGER_RAMP).map(hex), R = o.R, ph = (t / meta.duration) % 1, K = o.kind;
  const J = jit(o.seed + 3, 16);
  const blob = (cx, cy, r, sq, rot, cols) => {
    const n = 8, pts = Array.from({ length: n }, (_, i) => {
      const a = rot + (i / n) * TAU, rr = r * (0.78 + 0.34 * J[i]);
      return [cx + Math.cos(a) * rr, cy + Math.sin(a) * rr * sq];
    });
    p.poly(pts, cols[0]);
    p.poly(pts.map(([x, y]) => [cx + (x - cx) * 0.62 - 0.6, cy + (y - cy) * 0.62 - 0.6]), cols[1]);
    p.poly(pts.map(([x, y]) => [cx + (x - cx) * 0.28 - 1, cy + (y - cy) * 0.28 - 1]), cols[2]);
  };
  if (K === "spore") {
    const s = 1 + 0.08 * Math.sin(ph * TAU);
    for (let k = 0; k < 3; k++) {   // 拖尾三缕，长短不一、相位错开
      const L = R * (1.2 + 0.6 * J[k + 8]), off = (k - 1) * R * 0.35, w = Math.sin((ph + J[k]) * TAU) * 1.2;
      for (let x = 0; x < L; x += 1) p.blend(-R * 0.6 - x, off * (1 - x / L) + w * (x / L), x < L * 0.4 ? RAMP[2] : RAMP[1], 1 - x / L > 0.3 ? 1 : 0.6);
    }
    blob(0, 0, R * s, 0.85, ph * 0.6, [RAMP[2], RAMP[3], RAMP[5]]);
  } else if (K === "orb") {
    for (let k = 0; k < 4; k++) {   // 冒泡拖尾：气泡沿 -x 漂走，相位循环
      const u = (ph + k / 4 + J[k] * 0.1) % 1, x = -R * 0.6 - u * R * 1.8, y = (J[k + 4] - 0.5) * R * 0.9 * (0.4 + u);
      p.disc(x, y, Math.max(0.6, R * 0.32 * (1 - u)), u < 0.5 ? RAMP[3] : RAMP[2], 1 - u * 0.6);
    }
    blob(0, 0, R, 0.9, 0.3, [RAMP[1], RAMP[3], RAMP[5]]);
    p.dot(R * 0.25, -R * 0.3, WHITE);
  } else if (K === "glob") {
    const rot = ph * TAU;   // 翻滚：轮廓转一圈，高光跟着绕
    blob(0, 0, R, 0.9, rot, [RAMP[2], RAMP[3], RAMP[4]]);
    p.dot(Math.cos(rot) * R * 0.45, Math.sin(rot) * R * 0.4 - 0.5, WHITE);
    p.dot(-R * 1.1 - J[2] * 2, Math.sin(rot * 2) * 1.5, RAMP[2]);
  } else if (K === "trail") {
    // 拖尾（Boss 弹 fx_px_btrail 的替代，代码按弹色着色、按速度拉长）：右端 = 弹尾，往左逐级变暗变稀；碎光点按相位往左流，长短不一
    const L = R * 2;
    for (let x = 0; x < L; x += 1) {
      const q = x / L, wv = Math.max(0, 1.6 - q * 2.2) * (0.7 + 0.3 * Math.sin((q * 3 + ph) * TAU));
      if (wv <= 0.2) continue;
      for (let y = -Math.ceil(wv); y <= Math.ceil(wv); y++) {
        const c = q < 0.15 ? RAMP[5] : q < 0.4 ? RAMP[4] : RAMP[3];
        if (Math.abs(y) <= wv - 0.5) p.px(-x, y, c);
        else p.blend(-x, y, c, 0.45);   // 边缘真半透明，不用抖动（docs/229 §2.4 禁棋盘格）
      }
    }
    for (let k = 0; k < 4; k++) {
      const u = (ph + J[k]) % 1, x = -L * (0.25 + 0.75 * u), y = (J[k + 4] - 0.5) * 6 * u;
      p.blend(x, y, u < 0.5 ? RAMP[4] : RAMP[2], 1 - u * 0.7);
    }
  } else {   // shard
    const L = R, w = Math.max(1.5, R * 0.28);
    const pts = [[L, 0], [L * 0.35, -w], [-L * 0.8, -w * 0.6], [-L, 0], [-L * 0.75, w * 0.7], [L * 0.3, w]];
    p.poly(pts, RAMP[2]);
    p.poly([[L, 0], [L * 0.35, -w], [-L * 0.8, -w * 0.6], [-L * 0.6, 0]], RAMP[3]);
    const hx = -L * 0.7 + ((ph * 1.7) % 1) * L * 1.5;   // 高光沿上棱走
    p.line(hx - 2, -w * 0.55, hx + 1, -w * 0.75, RAMP[5]);
    p.dot(L - 0.5, 0, WHITE);
  }
  if (K !== "trail") p.glow(0, 0, R * 1.6, RAMP[3], 0.25);
}
