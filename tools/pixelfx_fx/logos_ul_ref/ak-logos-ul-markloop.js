// 逻各斯放开版：剩余循环画面（docs/242 §0，组长 B 11-04），实心小件、不画圆环：
//   lock   S1「提喻」锁定标记（挂目标头顶，取代细圈 + 两道短线）：一枚实心暗墨倒三角咒印、白芯字符，上下轻浮，每圈白边亮一拍
//   slow   S3 被减速的敌弹标记（套在弹上，取代中心镂空的旧圈）：弹身后一滴拖长的实心暗墨、蓝描边，墨滴慢慢摆动（不是环）
//   rune   成长「铭文」咒文池（地面上方浮着）：一块实心暗墨字符牌（竖长六边形、白字镂空）+ 脚下一摊压扁的暗墨影，牌身缓慢浮动、字符逐个亮
import { Rng, fit, hex, clamp, smooth, noise, noise2, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos ink loop marks unleashed",
  desc: "Logos's looping marks: a solid ink lock sigil bobbing over the locked target, an ink drop trailing a slowed bullet, and a floating ink glyph tablet over a small ink shadow.",
  tags: ["arcane", "ink", "glyph", "loop"],
  size: [64, 64],
  origin: [32, 36],
  duration: 0.8,
  loop: true,
  fps: 15,
  bg: "dark",
  options: {
    palette: ["#07081a", ...OP.logos],
    accent: "#a487ff",
    move: "lock",
    elite: 2,
    layer: "all",
    seed: 3,
  },
};

const LOOP = 0.8;
const GLY = [["#.#", "#.#", "...", ".#."], ["##", "##", "#.", "##"], ["#.#", "#.#", "###", "#.#"], ["###", "#..", "###"], ["###", ".#.", ".#."]];

export function create(o) {
  const C = fit(o.palette, 8), Rg = new Rng(o.seed), ACC = hex(o.accent), el = clamp(Math.round(+o.elite), 0, 2), mv = o.move || "lock";
  const core = o.layer !== "deco", deco = o.layer !== "core";
  let t = 0;
  const glyph = (p, g, x, y, col) => { const rows = GLY[g]; for (let r = 0; r < rows.length; r++) for (let c = 0; c < rows[r].length; c++) if (rows[r][c] === "#") p.px(x + c, y + r, col); };
  return {
    update(dt) { t += dt; },
    drawBack(p) {
      if (!deco) return;
      const ph = (t % LOOP) / LOOP;
      if (mv === "lock") p.glow(0, -2, 7, C[4], 0.18 + 0.12 * Math.max(0, Math.cos(ph * TAU)));
      if (mv === "rune") p.glow(0, -6, 9, C[4], 0.2);
    },
    draw(p) {
      if (!core) return;
      const ph = (t % LOOP) / LOOP, bob = Math.round(Math.sin(ph * TAU) * 1.5);
      if (mv === "lock") {
        // 倒三角咒印 9×8：暗墨身、蓝描边（E2 紫），中间一个白字符；每圈开头白边一拍
        const flash = ph < 0.12, W = 6, H = 8;
        for (let y = 0; y < H; y++) { const hw = W * (1 - y / H); for (let x = -Math.ceil(hw); x <= Math.ceil(hw); x++) { if (Math.abs(x) > hw + 0.3) continue; const edge = Math.abs(x) > hw - 1 || y === 0; p.px(x, y - 6 + bob, edge ? (flash ? C[7] : el >= 2 ? ACC : C[4]) : C[y < 3 ? 1 : 0]); } }
        glyph(p, 4, -1, -5 + bob, C[flash ? 7 : 6]);
      }
      if (mv === "slow") {
        // 墨滴：头在原点（弹的位置），尾巴往左后方拖 10 像素、随相位摆动
        const sw = Math.sin(ph * TAU) * 2;
        for (let x = -11; x <= 2; x++) {
          const v = (x + 11) / 13, w = 0.6 + v * 2.4 - (x > 0 ? x * 0.9 : 0), y0 = sw * (1 - v);
          for (let y = -Math.ceil(w); y <= Math.ceil(w); y++) { if (Math.abs(y) > w + 0.2) continue; p.px(x, Math.round(y0 + y), Math.abs(y) > w - 0.8 || x > 1 ? C[4] : C[v > 0.6 ? 1 : 0]); }
        }
      }
      if (mv === "rune") {
        // 脚下压扁墨影
        for (let y = -2; y <= 2; y++) for (let x = -9; x <= 9; x++) if ((x * x) / 81 + (y * y) / 4 < 1 && noise2(x * 0.4, y, 3) > -0.6) p.px(x, 8 + y, C[0]);
        // 竖长六边形字符牌 12×18，浮在上方
        const cy = -8 + bob;
        for (let y = -9; y <= 9; y++) { const hw = 6 - Math.max(0, Math.abs(y) - 5) * 1.2; for (let x = -Math.ceil(hw); x <= Math.ceil(hw); x++) { if (Math.abs(x) > hw + 0.2) continue; const edge = Math.abs(x) > hw - 1 || Math.abs(y) === 9; p.px(x, cy + y, edge ? (el >= 2 ? ACC : C[4]) : C[1]); } }
        for (let i = 0; i < 3; i++) { const lit = Math.floor(ph * 3) === i; glyph(p, (i * 2 + 1) % GLY.length, -1, cy - 7 + i * 5, C[lit ? 7 : 5]); }
      }
    },
  };
}
