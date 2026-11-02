// 艾雅法拉精二熔池（docs/229，循环地面件）：@2x，1 贴图像素 = 1 世界像素，原点 = 池心，地面透视 sy 0.55，池半径 radius。
// 暗色熔岩壳一块块浮在池面，壳缝里透出发亮的熔岩纹，纹的明暗随噪声缓缓起伏；
// 池面上不时鼓起一个气泡、白热一闪后破开（位置、大小、时刻都随机）。外缘按噪声起伏，不画同心圈，不用棋盘格。
import { Rng, fit, clamp, noise, noise2, loopNoise, cycle, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Eyjafjalla lava pool",
  desc: "A looping lava pool on the floor: dark crust plates drift on glowing seams that slowly pulse, bubbles swell white-hot and pop at random spots.",
  tags: ["fire", "lava", "pool", "floor", "loop"],
  size: [104, 60],
  origin: [52, 30],
  duration: 0.8,
  loop: true,
  fps: 10,
  bg: "dark",
  options: { palette: OP.eyjafjalla, radius: 46, seed: 13 },
};

const SY = 0.55;

function body(p, t, o, far) {
  const C = fit(o.palette, 7), R = o.radius, S = o.seed, ph = t / meta.duration;
  p.shade(-R * 1.15, -R * SY * 1.15, R * 1.15, R * SY * 1.15, (x, y) => {
    if ((y < 0) !== far) return;
    const a = Math.atan2(y / SY, x), d = Math.hypot(x, y / SY) / (R * (1 + 0.1 * noise(a * 3.1, S) + 0.05 * noise(a * 7.7, S + 1)));
    if (d > 1) return;
    // 熔岩纹：两层噪声的「零线」附近是缝，随循环相位缓缓起伏
    const n = noise2(x * 0.09, y * 0.16, S + 3) + 0.35 * noise2(x * 0.21, y * 0.38, S + 5);
    const pulse = 0.5 + 0.5 * loopNoise(ph + x * 0.004, 0.9, S + 7);
    const seam = 1 - clamp(Math.abs(n) / (0.1 + 0.08 * pulse));
    let ci;
    if (seam > 0.6) ci = 3 + (seam > 0.85 && pulse > 0.5 ? 1 : 0);   // 发亮的缝
    else if (seam > 0.25) ci = 2;
    else ci = n > 0.25 ? 0 : 1;                                        // 浮壳：两种暗色
    if (d > 0.93) ci = Math.max(ci, 2);                                 // 外缘一道熔边
    p.blend(x, y, C[ci], ci <= 1 ? 0.88 : 0.95);
  });
}

export function drawBack(p, t, o) { body(p, t, o, true); }

export function draw(p, t, o) {
  const C = fit(o.palette, 7), R = o.radius;
  body(p, t, o, false);
  // 气泡：鼓起 → 白热一闪 → 破开成两三点
  cycle(t, meta.duration, 5, o.seed, 0.32, (age, L, g) => {
    const a = g.range(0, TAU), d = Math.sqrt(g.next()) * 0.75 * R, x = Math.cos(a) * d, y = Math.sin(a) * d * SY, s = g.range(1.5, 3.2), u = age / L;
    if (u < 0.6) p.disc(x, y - u * 1.5, s * (0.4 + u), C[u > 0.45 ? 6 : 5], 0.95);
    else for (let k = 0; k < 3; k++) p.px(x + (k - 1) * s * (0.6 + u), y - 1 - (u - 0.6) * 8 * (k === 1 ? 1.4 : 1), C[4]);
  });
  p.glow(0, 0, R * 0.6, C[4], 0.12);
}
