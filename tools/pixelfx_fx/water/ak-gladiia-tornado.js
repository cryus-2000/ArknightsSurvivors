// 歌蕾蒂娅 S3「怒潮漩涡」（替换 fx_gladiia_tornado_open / loop / close，旧条 scale 1.2 = 每 1x 像素 2.4 世界像素超标）：@2x，保留画布，游戏 scale 1.0。
// 原点 = 漩涡脚下地面点（画布水平正中、底边上方 12 px），JSON anchor = [55, 64]（1x 单位）。
// 一束深海水流绕成上宽下窄的漏斗：几条宽窄、高低、转速都不同的水带螺旋上升，前半圈亮、后半圈暗；顶上甩出水沫，脚下一圈不规整的白浪。
// mode：open 0.3 秒从地面卷起（首帧白闪）/ loop 0.5 秒无缝循环（每条水带整圈数转动）/ close 0.4 秒塌落散开。
import { Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP, FPS } from "../house.js";

export const meta = {
  name: "Gladiia tide vortex",
  desc: "A funnel of deep-sea water: uneven bands spiral upward, bright in front and dark behind, spray flung off the rim and a ragged foam ring at the base.",
  tags: ["water", "tornado", "vortex", "loop"],
  size: [116, 152],
  origin: [58, 140],
  duration: 0.5,
  loop: true,
  fps: FPS.skill,
  bg: "dark",
  options: {
    palette: ["#06142a", ...OP.gladiia],
    mode: "loop",
    height: 120,
    seed: 6,
  },
};

const DUR = { open: 0.3, loop: 0.5, close: 0.4 };

function bands(o) {
  const Rg = new Rng(o.seed), out = [];
  for (let i = 0; i < 7; i++)
    out.push({ ph: Rg.range(0, TAU), h0: Rg.range(0, 0.25), h1: Rg.range(0.65, 1), w: Rg.range(1.2, 3), twist: Rg.range(2.2, 3.4), turns: Rg.int(1, 2), lo: Rg.chance(0.4) });
  return out;
}

export function draw(p, t, o) {
  const C = fit(o.palette, 8), H = o.height, mode = o.mode, D = DUR[mode] || 0.5, u = clamp(t / D);
  if (mode !== "loop" && u >= 0.999) return;
  // 漏斗形：半径随高度，open 时从下往上长，close 时整体塌低、散开
  const grow = mode === "open" ? 0.25 + 0.75 * ease.outQuart(u) : 1, fall = mode === "close" ? ease.inQuad(u) : 0;
  const Hn = H * grow * (1 - fall * 0.7), loopPh = mode === "loop" ? u : mode === "open" ? u * 0.6 : 0.6 + u * 0.8;
  const rad = (v) => (9 + 40 * Math.pow(v, 1.4)) * (1 + fall * 0.8);
  const hot = mode === "open" && t < 0.03 ? 2 : 0;
  const seen = new Map();
  const put = (x, y, ci, a) => {
    const k = Math.round(x) * 1000 + Math.round(y), prev = seen.get(k);
    if (prev !== undefined && prev >= ci) return;
    seen.set(k, ci);
    p.blend(Math.round(x), Math.round(y), C[clamp(ci, 1, 7)], a);
  };
  // 漏斗水体：半透明的深海水，侧缘略亮（体积感），画在水带下面
  for (let y = 0; y >= -Hn; y -= 1) {
    const v = -y / Math.max(Hn, 1), R = rad(v) * (0.8 + 0.08 * Math.sin(y * 0.21 + loopPh * TAU) + 0.05 * Math.sin(y * 0.53 - loopPh * TAU * 2));   // 侧缘起伏，循环无缝
    const top = v > 0.7 ? (1 - v) / 0.3 : 1;                  // 顶上散开，不留平口
    for (let x = -R; x <= R; x += 1) {
      const q = Math.abs(x) / R;
      p.blend(Math.round(x), y, C[q > 0.8 ? 3 : 2], ((0.2 + 0.16 * q) * (1 - fall) + (hot ? 0.4 : 0)) * top);
    }
  }
  // 后半圈先画（暗），前半圈后画（亮）
  for (const pass of [0, 1]) {
    for (const b of bands(o)) {
      const N = Math.ceil(Hn * 1.6 + b.twist * 60);           // 按弧长采样，宽处不断成虚线
      for (let i = 0; i <= N; i++) {
        const v = b.h0 + (b.h1 - b.h0) * i / N, y = -v * Hn;
        const th = b.ph + v * b.twist * TAU / 2 + loopPh * TAU * b.turns;
        const r = rad(v) * (1 + 0.08 * noise(v * 6 + b.ph, o.seed)), front = Math.sin(th) > 0;
        if (front !== (pass === 1)) continue;
        const x = Math.cos(th) * r, yy = y + Math.sin(th) * r * 0.22;
        const edge = Math.abs(Math.cos(th)) > 0.85;           // 侧缘受光最亮
        const ci = Math.round((front ? (edge ? 6.5 : 4.5) : 2.5) + v * 1 - fall * 2.5 + hot + (b.lo ? -1 : 0));
        for (let d = 0; d < b.w * (0.6 + v * 0.8); d += 1) put(x, yy - d, ci, front ? 0.85 : 0.5);
      }
    }
  }
  // 脚下白浪：不规整的一圈，open / loop 有，close 时散开变淡
  const fr = 14 * (mode === "open" ? ease.outQuart(u) : 1) * (1 + fall * 1.2), fa = 1 - fall;
  for (let a = 0; a < TAU; a += 0.08) {
    const a2 = a - loopPh * TAU, w = 0.55 * Math.sin(3 * a2 + 1.3) + 0.35 * Math.sin(7 * a2 + 4.1) + 0.2 * Math.sin(11 * a2 + 2.2);   // 整数频率：随循环转一整圈，无缝
    if (w < -0.2) continue;                                    // 有缺口
    const rr = fr * (1 + 0.25 * w), x = Math.cos(a) * rr, y = Math.sin(a) * rr * 0.35;
    put(x, y, (Math.sin(a) > 0 ? 6 : 4) + hot, 0.8 * fa);
    if (w > 0.4) put(x, y - 1, 7, 0.7 * fa);
  }
}
