// 推进之王连携尾锤砸坑 / 维什戴尔连携弹坑（D 组）：@2x 密度，俯视圆形静态图（脚本按 sy 压扁成地面透视、负责淡出），原点 = 坑心。
// 替换 fx_lk_sg_crater1–3（kind 0，灰金土坑）与 fx_ws_crater（kind 1，焦黑弹坑，4 帧 = 4 种变体，按时间换 seed）。
// 坑沿是不规整的碎土唇（噪声半径），坑底暗，向外甩出不等长的裂纹与碎块；不画同心圈、不等距放射。
import { Rng, fit, clamp, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Siege crater",
  desc: "A still top-down crater: a ragged lip of broken earth, a dark floor, uneven cracks and chunks thrown outward; kind 1 is a scorched blast pit with four variants.",
  tags: ["earth", "crater", "ground", "still"],
  size: [148, 148],
  origin: [74, 74],
  duration: 0.4,
  loop: false,
  fps: 10,
  bg: "ground",
  options: { palette: ["#0e0c0a", "#2a241c", "#4a3e2e", "#6e5c40", OP.siege[2], OP.siege[3], OP.siege[5]], kind: 0, radius: 46, variants: 1, seed: 1 },
};

export function draw(p, t, o) {
  const nv = Math.max(1, +o.variants), fi = Math.floor(t * 10 + 1e-6);
  if (fi >= nv) return;
  const C = fit(o.palette, 7), R = new Rng(o.seed * 31 + fi * 7), R0 = o.radius, scorch = +o.kind === 1;
  const lip = (a) => R0 * (0.82 + 0.16 * noise(a * 2.2, o.seed + fi * 13)) + 2.5 * noise(a * 9, o.seed + fi * 5);
  // 坑底与坑壁
  for (let y = -R0 - 8; y <= R0 + 8; y++)
    for (let x = -R0 - 8; x <= R0 + 8; x++) {
      const d = Math.hypot(x, y), a = Math.atan2(y, x), L = lip(a);
      if (d > L + 4) continue;
      if (d > L) { if (noise(x * 0.5, y * 0.5 + fi) > 0.1) p.px(x, y, C[y < 0 ? 4 : 3]); continue; }   // 碎土唇（上沿受光）
      const q = d / L, lit = -Math.sin(a) * 0.5 + 0.5;   // 坑壁：上半背光、下半受光
      const ci = q < 0.55 ? (scorch ? 0 : 1) : clamp(Math.round(1 + (q - 0.55) * 4 + (y > 0 ? lit : 0) * 1.5), 1, 4);
      p.px(x, y, C[ci]);
    }
  // 向外的裂纹：条数、角度、长短都随机，带分叉
  for (let a = R.range(0, 1); a < TAU - 0.4; a += R.range(0.5, 1.4)) {
    let x = Math.cos(a) * lip(a), y = Math.sin(a) * lip(a), aa = a;
    const len = R0 * R.range(0.25, 0.6);
    for (let s = 0; s < len; s += 1.5) {
      aa += R.range(-0.4, 0.4);
      x += Math.cos(aa) * 1.5; y += Math.sin(aa) * 1.5;
      p.px(x, y, C[s < len * 0.5 ? 1 : 2]);
      if (R.chance(0.04)) { const b = aa + R.sign() * 0.8; for (let k = 1; k < 6; k++) p.px(x + Math.cos(b) * k, y + Math.sin(b) * k, C[2]); }
    }
  }
  // 碎块
  for (let i = 0; i < 10; i++) {
    const a = R.range(0, TAU), d = R0 * R.range(1.0, 1.45), s = R.range(1, 3);
    p.rect(Math.cos(a) * d, Math.sin(a) * d, s, s, C[R.int(2, 4)]);
  }
  if (scorch) for (let i = 0; i < 6; i++) { const a = R.range(0, TAU), d = R0 * R.range(0.1, 0.5); p.px(Math.cos(a) * d, Math.sin(a) * d, C[5]); }   // 坑底余烬
}
