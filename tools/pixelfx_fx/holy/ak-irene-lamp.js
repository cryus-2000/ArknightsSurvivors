// 艾丽妮连携「提灯一照」的提灯（D 组）：@2x 密度，单张静态图（连携脚本负责举起、转动、淡出），原点 = 提手顶。替换 fx_lk_ir_lamp1–3。
// 铁框提灯：深色铁框 + 暖金灯火，火苗形状按 seed 变（三张变体），框上一点高光。灯火用我方灯火色，不发白。
import { Rng, fit, clamp, noise } from "../../core/index.js";
import { LAMP } from "../house.js";

export const meta = {
  name: "Irene lamp",
  desc: "Irene's iron cage lantern, a still image: dark iron frame, warm amber flame whose shape varies by seed, a small glint on the frame.",
  tags: ["holy", "prop", "lamp", "still"],
  size: [32, 68],
  origin: [16, 2],
  duration: 0.1,
  loop: false,
  fps: 10,
  bg: "dark",
  options: { palette: ["#0a0c14", "#1e2230", "#3a4052", "#6a5030", LAMP, "#ffc98a", "#fff0d0"], seed: 1 },
};

export function draw(p, t, o) {
  if (t >= 0.1) return;
  const C = fit(o.palette, 7), R = new Rng(o.seed);
  // 提手
  p.arc(0, 6, 5, 1, Math.PI, 2 * Math.PI, C[2]);
  p.line(0, 0, 0, 2, C[2]);
  // 顶盖
  p.poly([[-7, 12], [7, 12], [4, 8], [-4, 8]], C[1]);
  p.line(-6, 12, 6, 12, C[2]);
  // 玻璃罩里的光
  const lean = R.range(-1.2, 1.2), fh = R.range(16, 22);
  for (let y = 14; y < 50; y++)
    for (let x = -8; x <= 8; x++) {
      const u = (y - 14) / 36;
      p.blend(x, y, C[3], 0.35 * (1 - Math.abs(x) / 9));
      // 火苗：底宽顶尖，边缘按噪声抖
      const fy = 46 - y, w = fy > 0 && fy < fh ? (1 - fy / fh) * (4.5 + R.range(0, 0.01)) * (0.8 + 0.4 * noise(y * 0.4, o.seed)) : 0;
      const cx = lean * (fy / fh);
      if (Math.abs(x - cx) < w) p.px(x, y, C[Math.abs(x - cx) < w * 0.4 && fy < fh * 0.6 ? 6 : Math.abs(x - cx) < w * 0.75 ? 5 : 4]);
    }
  // 铁框：四根竖条 + 横箍，竖条位置略不对称
  for (const x of [-8, -3 + R.range(-0.5, 0.5), 3 + R.range(-0.5, 0.5), 8]) p.line(x, 13, x, 50, Math.abs(x) > 5 ? C[1] : C[2]);
  for (const y of [13, 31 + R.int(-1, 1), 50]) p.line(-8, y, 8, y, C[2]);
  // 底座
  p.poly([[-8, 51], [8, 51], [6, 56], [-6, 56]], C[1]);
  p.line(-5, 57, 5, 57, C[2]);
  p.px(-7, 15, C[5]); p.px(-7, 16, C[4]);
  p.glow(0, 36, 14, C[4], 0.25);
}
