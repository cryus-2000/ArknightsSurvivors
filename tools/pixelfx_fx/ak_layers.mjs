#!/usr/bin/env node
// 方舟幸存者分层导出（docs/229 §2.7）：tools/pixelfx_export.py 把本文件拷进 pixelfx 库的 tools/ 再调用。
// 一个特效导出两张单行横向帧条：<out>/color.png（color 层，直通 alpha，不含光晕）和 <out>/light.png（light 加色层，黑底 RGB），
// 外加 <out>/meta.json（fps、帧数、帧尺寸、原点）。库自带的 render.mjs --sheet 只出合成图（光晕烤成带 alpha 的颜色、且是预乘色），量化后光晕会被吃掉。
//
//   node tools/ak_layers.mjs <id> --out DIR [--fps N] [--seed N] [--opts JSON]

import { join } from "node:path";
import { loadEffect, renderFrames, canvas, save } from "./lib/fxlib.mjs";

const args = process.argv.slice(2), flags = {}, ids = [];
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith("--")) flags[args[i].slice(2)] = args[++i];
  else ids.push(args[i]);
}
const fx = await loadEffect(ids[0]);
const r = renderFrames(fx, {
  fps: flags.fps ? +flags.fps : undefined,
  seed: flags.seed ? +flags.seed : undefined,
  actor: false,
  options: flags.opts ? JSON.parse(flags.opts) : undefined,
});
const { w, h, n, frames } = r;
const col = canvas(w * n, h, [0, 0, 0, 0]), lit = canvas(w * n, h, [0, 0, 0, 255]);
let peak = 0;
frames.forEach((f, i) => {
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const s = y * w + x, d = (y * w * n + i * w + x) * 4, c = f.raw[s], l = f.light[s];
      col.data[d] = c & 255; col.data[d + 1] = (c >>> 8) & 255; col.data[d + 2] = (c >>> 16) & 255; col.data[d + 3] = c >>> 24;
      const lr = l & 255, lg = (l >>> 8) & 255, lb = (l >>> 16) & 255;
      lit.data[d] = lr; lit.data[d + 1] = lg; lit.data[d + 2] = lb;
      peak = Math.max(peak, lr, lg, lb);
    }
});
const out = flags.out;
save(join(out, "color.png"), col.png());
save(join(out, "light.png"), lit.png());
save(join(out, "meta.json"), JSON.stringify({ id: fx.id, fps: r.fps, frames: n, frameSize: [w, h], pivot: fx.meta.origin, lightPeak: peak }));
console.log(`${fx.id}  ${n} frames  light peak ${peak}`);
