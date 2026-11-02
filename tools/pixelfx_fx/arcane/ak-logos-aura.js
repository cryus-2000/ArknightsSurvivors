// 逻各斯 S3 咒域期间绕身的符咒（6 帧 @10 循环，@2x 96×112，原点 = 中心 = 脚上 36 像素；layer: back 只画身后半圈 / front 只画身前半圈 / both 两半都画）：
// 五个大小不一的小字在一道倾斜椭圆轨道上绕身转，起角不等距；转到身后变暗。一个循环正好转一圈。
import { glyph } from "./_ak-logos-script.js";
import { TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Logos curse orbit",
  desc: "Curse glyphs of uneven size orbit Logos on a tilted ellipse during his curse field, dimming as they pass behind him.",
  tags: ["arcane", "ink", "glyph", "orbit", "loop"],
  size: [96, 112],
  origin: [48, 56],
  duration: 0.6,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.logos, layer: "both", seed: 60 },
};

const G = [[0.0, 10], [1.1, 7], [2.5, 9], [3.6, 6], [5.0, 8]];

export function draw(p, t, o) {
  const ph = t / meta.duration;
  G.forEach(([a0, s], i) => {
    const a = a0 + ph * TAU, z = Math.sin(a), back = z < 0;
    if ((o.layer === "back" && !back) || (o.layer === "front" && back)) return;
    const x = Math.cos(a) * 34, y = 14 + z * 12 - Math.cos(a) * 6;
    glyph(p, o.palette, x, y, s, s + 3, o.seed + i, 1, back ? 2 : 4);
  });
}
