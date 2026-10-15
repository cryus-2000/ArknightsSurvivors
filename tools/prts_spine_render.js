// PRTS Spine 3.8 参照帧渲染（tools/prts_spine.py 调用，docs/36 §9.1）：官方 spine-ts 3.8 运行时（spine-canvas.js，SkeletonBinary 读二进制 .skel）
// + @napi-rs/canvas 无头 Canvas，三角形渲染（网格附件也画）。只渲染、不下载：素材由 Python 侧下好放在 _raw/<id>/。
// 用法：node prts_spine_render.js <spine-canvas-3.8.js> <job.json>
//   job = {skel, atlas, out_dir, size: 1000, flip: false, frames: [{name, anim, t}]}（t：秒）
// 输出 <out_dir>/<name>.png（size × size 透明底），并在标准输出打印 JSON：动画清单、各动画时长与事件时刻、实际出的帧
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { createCanvas, loadImage } = require("@napi-rs/canvas");

const [runtimePath, jobPath] = process.argv.slice(2);
const job = JSON.parse(fs.readFileSync(jobPath, "utf8"));

// spine-ts 3.8 是浏览器 UMD 脚本（顶层 var spine）：放进沙箱跑，取出 spine 命名空间
const sandbox = { console, Math, Float32Array, Int16Array, Uint16Array, Int32Array, Uint8Array, ArrayBuffer, DataView, setTimeout, clearTimeout };
sandbox.window = undefined;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(runtimePath, "utf8") + "\n;this.__spine = spine;", sandbox);
const spine = sandbox.__spine;

async function main() {
  // 贴图集：页图按名字在 .atlas 同目录找。@napi-rs/canvas 的 Image 同步赋 src 不会真正解码（画出来全透明），先用 loadImage 异步预载
  const atlasDir = path.dirname(job.atlas);
  const atlasText = fs.readFileSync(job.atlas, "utf8");
  const pages = {};
  for (const line of atlasText.split(/\r?\n/)) {
    const t = line.trim();
    if (t.endsWith(".png") && !t.includes(":")) pages[t] = await loadImage(fs.readFileSync(path.join(atlasDir, t)));
  }
  const atlas = new spine.TextureAtlas(atlasText, (p) => new spine.canvas.CanvasTexture(pages[p]));
  const binary = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas));
  binary.scale = 1;
  const data = binary.readSkeletonData(new Uint8Array(fs.readFileSync(job.skel)));

  const anims = {};
  for (const a of data.animations) {
    const evs = [];
    for (const tl of a.timelines) {
      if (tl instanceof spine.EventTimeline) {
        for (let k = 0; k < tl.frames.length; k++) evs.push({ name: tl.events[k].data.name, t: tl.frames[k] });
      }
    }
    anims[a.name] = { dur: a.duration, events: evs };
  }

  function pose(anim, t) {
    const sk = new spine.Skeleton(data);
    sk.setToSetupPose();
    if (anim) {
      const a = data.findAnimation(anim);
      a.apply(sk, 0, t, false, null, 1, spine.MixBlend.setup, spine.MixDirection.mixIn);
    }
    sk.updateWorldTransform();
    return sk;
  }

  // 统一缩放：所有要出的帧的包围盒并起来，按 size 留 6% 边距放下；脚底（骨架原点）放在横向正中、最低点贴近底边 6%
  const frames = (job.frames || []).filter((f) => !f.anim || anims[f.anim]);
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  const off = new spine.Vector2(), sz = new spine.Vector2();
  for (const f of frames) {
    const sk = pose(f.anim, f.t);
    sk.getBounds(off, sz, []);
    minX = Math.min(minX, off.x); minY = Math.min(minY, off.y);
    maxX = Math.max(maxX, off.x + sz.x); maxY = Math.max(maxY, off.y + sz.y);
  }
  const S = job.size || 1000;
  const halfW = Math.max(Math.abs(minX), Math.abs(maxX));
  const scale = frames.length ? Math.min((S * 0.88) / (2 * halfW), (S * 0.88) / (maxY - minY)) : 1;
  const out = [];
  fs.mkdirSync(job.out_dir, { recursive: true });
  for (const f of frames) {
    const sk = pose(f.anim, f.t);
    const cv = createCanvas(S, S);
    const ctx = cv.getContext("2d");
    ctx.translate(S / 2, S * 0.94 + minY * scale);
    ctx.scale(job.flip ? -scale : scale, -scale);   // spine 是 Y 向上
    const r = new spine.canvas.SkeletonRenderer(ctx);
    r.triangleRendering = true;
    r.draw(sk);
    const p = path.join(job.out_dir, f.name + ".png");
    fs.writeFileSync(p, cv.toBuffer("image/png"));
    out.push({ name: f.name, anim: f.anim, t: f.t, file: p });
  }
  process.stdout.write(JSON.stringify({ anims, scale, frames: out }) + "\n");
}

main().catch((e) => { console.error((e && e.stack) || e); process.exit(1); });
