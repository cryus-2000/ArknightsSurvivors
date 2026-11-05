// 浊心斯卡蒂 S3「潮涌，潮枯」起手（docs/242 放开版代表招式，§11.1 第 6 条先交对照）：1x，俯视，原点 = 浊心脚底，地面透视 sy 0.55。
// 她是辅助：画面要读出「歌声 + 潮汐增益」，不是砍杀。核心层 = 胸前一点白热 + 绕身卷起的酒红潮冠（不等角、不等高的弧焰）+ 一道断续的歌声前沿推到歌域边缘（判定半径，judge 传入）；
// 装饰层 = 光晕、沿螺旋上飘的歌声光点（海蓝 / 白）、潮雾、余韵，以及歌域内部的潮纹 / 水雾 / 往中心汇聚的光点（E1 加音波短弧，E2 加触须影子）。
// 精英档（docs/91 §13），主形不变、逐档叠加、一档比一档高大：E0 只有主形、余韵短、光晕小；
// E1「余音」= 潮冠升高 ×1.2 + 潮水外圈一圈随机间距的浪花冠（涌起碎成水珠）+ 主前沿将散时外圈 2–3 段回声弧；
// E2「远古血亲」= 潮冠变血色浪柱（×1.45、停得更久）+ 三四条深海蓝海嗣触须从潮冠里大幅升起、绕身盘旋（锯齿、海蓝高光、青色光点），全量光晕与余韵。
// 颜色：她的设定红（PRTS 主服 #B83139）压暗成酒红 / 深绯，亮部给海蓝和白，不出大面积亮品红（敌方危险色 #ff2667）；青色只用原作袖口那档偏灰青，不用敌弹青 #33ceff。
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { OP } from "../house.js";

export const meta = {
  name: "Skalter tide elegy",
  desc: "Wine-dark tide curls up around her as a broken song-front rolls to the song field edge; sea-blue glints drift up. Higher ranks add a spray crown and rising seaborn tentacles.",
  tags: ["water", "song", "buff", "aura", "topdown", "one-shot"],
  size: [420, 300],
  origin: [210, 190],
  duration: 1.45,
  loop: false,
  fps: 20,
  bg: "dark",
  options: {
    palette: [...OP.skalter],   // house.js OP.skalter（11-03 改成 PRTS 主服 #B83139 压暗的酒红）
    sea: ["#0b1a2e", "#14324f", "#1f5468", "#3b8e89", "#7fc4bf", "#d6f0ec"],   // 海蓝 / 灰青（PRTS 帽 #3B8E89、袖口 #6ACCCA 压饱和），白
    R: 190,          // 歌域边缘（1x 像素）= judge: aura × s3_aura ÷ PX
    elite: 2,
    layer: "all",
    seed: 3,
  },
};

const SY = 0.55, FRONT = 0.36, CHEST = -26;

export function create(o) {
  const C = fit(o.palette, 8), S = fit(o.sea, 6), Rg = new Rng(o.seed), R = o.R, el = +o.elite;
  const core = o.layer !== "deco", deco = o.layer !== "core";
  const tail = [0.25, 0.4, 0.6][el], glowK = [0.25, 0.4, 0.6][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [S[5], S[4], C[6]], haze: S[2] }), lights = new Lights();

  // 潮冠：绕身卷起的弧焰，起点角不等距、高度和弯度各不相同
  const fa = [];   // 起点角：随机步长累加（步长差两倍以上），不按等分抖动，免得读成放射
  for (let a = Rg.range(0, 0.8); a < TAU - 0.3; a += Rg.range(0.45, 1.35)) fa.push(a);
  const flares = fa.map((a) => ({
    a, h: Rg.range(36, 74) * [1, 1.2, 1.45][el],   // 潮冠逐档升高；E2 是血色浪柱
    w: Rg.range(2.5, 5), r0: Rg.range(12, 30), twist: Rg.range(0.9, 1.7) * (Rg.chance(0.5) ? 1 : -1),
    d: Rg.range(0, 0.08), sd: Rg.range(0, 50),
  }));
  // 歌声前沿：断成几段的弧（缺口位置随机）
  const gaps = [];
  for (let a = Rg.range(0, 0.6); a < TAU; a += Rg.range(0.7, 1.6)) gaps.push({ a, w: Rg.range(0.12, 0.3) });
  const inGap = (a) => gaps.some((g) => { let d = a - g.a; d -= Math.round(d / TAU) * TAU; return Math.abs(d) < g.w; });
  // 回声（E1+）：只画 2–3 段长短不一的弧（合计不到半圈），不整圈留缺口——整圈等量缺口在角度频谱上会读成放射
  const echo = [];
  for (let i = 0, a0 = Rg.range(0, TAU), n = Rg.int(2, 3); i < n; i++) { echo.push({ a: a0, w: Rg.range(0.35, 0.9) }); a0 += Rg.range(1.4, 2.6); }
  const offEcho = (a) => !echo.some((g) => { let d = a - g.a; d -= Math.floor(d / TAU) * TAU; return d < g.w; });
  // 浪花冠（E1+，「余音」）：潮水外圈一圈涌起的水柱，间距和高矮都随机，涌到顶碎成水珠
  const spouts = [];
  if (el >= 1) for (let a = Rg.range(0, 0.5); a < TAU - 0.15; a += Rg.range(0.26, 0.72))
    spouts.push({ a, r: Rg.range(44, 60), h: Rg.range(20, 42) * (el >= 2 ? 1.25 : 1), w: Rg.range(2, 3.5), d: Rg.range(0.05, 0.16), sd: Rg.range(0, 60), popped: false });
  // 海嗣触须（E2，「远古血亲」）：三四条深海蓝触须从潮冠里大幅升起、绕着潮冠盘旋，锯齿外缘、海蓝高光、青色光点
  const tents = [];
  if (el >= 2) for (let a = Rg.range(0, 1); a < TAU - 0.4; a += Rg.range(1.2, 2.3))
    tents.push({ a, h: Rg.range(88, 118), dir: Rg.chance(0.5) ? 1 : -1, turn: Rg.range(1.6, 2.6), r0: Rg.range(22, 32), d: Rg.range(0.02, 0.08), sd: Rg.range(0, 40),
      spikes: Array.from({ length: Rg.int(5, 8) }, () => ({ v: Rg.range(0.12, 0.9), l: Rg.range(3, 7) })),
      dots: Array.from({ length: Rg.int(4, 7) }, () => Rg.range(0.1, 0.85)) });
  // 余韵光点：歌域里零星的海蓝闪点
  const res = [];
  for (let i = 0, n = [8, 12, 18][el]; i < n; i++) {
    const a = Rg.range(0, TAU), r = Math.sqrt(Rg.range(0.04, 1)) * R * 0.9;
    res.push({ x: Math.cos(a) * r, y: Math.sin(a) * r * SY, d: Rg.range(0, tail * 0.5), l: Rg.range(tail * 0.4, tail * 0.7), c: Rg.int(3, 5) });
  }
  // 歌域内部（装饰层，用户 11-03「环里面太空」）：歌声在场内流动——不规则潮纹、暗酒红水雾、往中心汇聚的海色光点 / 音符状小光斑；
  // E1 起加短音波弧（只是零散的短弧，半径各不相同，不成整圈），E2 加海嗣触须投在地上的影子和海蓝高光。全部压暗、半透明，让位给敌人和敌弹
  const inner = { strokes: [], mist: [], notes: [], waves: [], shadows: [] };
  const rin = () => R * (0.22 + 0.7 * Math.sqrt(Rg.range(0, 1)));   // 环内随机半径（面积均匀，避开中心潮冠）
  for (let i = 0, n = [10, 20, 28][el]; i < n; i++)
    inner.strokes.push({ a: Rg.range(0, TAU), r: rin(), L: Rg.range(6, 16), tilt: Rg.range(-0.6, 0.6), d: Rg.range(0.06, 0.3), sd: Rg.range(0, 90) });
  for (let i = 0, n = [4, 6, 8][el]; i < n; i++)
    inner.mist.push({ a: Rg.range(0, TAU), r: rin(), s: Rg.range(10, 20), d: Rg.range(0.05, 0.25), sd: Rg.range(0, 90) });
  for (let i = 0, n = [8, 16, 24][el]; i < n; i++)
    inner.notes.push({ a: Rg.range(0, TAU), r: rin(), d: Rg.range(0.08, 0.4), l: Rg.range(0.45, 0.8), spin: Rg.range(-0.5, 0.5), note: Rg.chance(0.35), hi: Rg.chance(0.3), fl: Rg.chance(0.22) ? Rg.range(0.3, 0.7) : 0 });
  if (el >= 1) for (let i = 0, n = [0, 5, 8][el]; i < n; i++)
    inner.waves.push({ a: Rg.range(0, TAU), r: R * Rg.range(0.3, 0.85), w: Rg.range(0.25, 0.55), d: Rg.range(0.12, 0.4), sd: Rg.range(0, 90) });
  if (el >= 2) for (let i = 0, n = Rg.int(3, 4); i < n; i++)
    inner.shadows.push({ a: Rg.range(0, TAU), r: R * Rg.range(0.35, 0.75), L: Rg.range(30, 52), bend: Rg.range(-0.8, 0.8), d: Rg.range(0.1, 0.25), sd: Rg.range(0, 90) });

  let t = 0, burst = false;

  const front = (tt) => R * ease.outCubic(clamp(tt / FRONT));
  const jag = (a) => 1 + 0.035 * noise(a * 3.3, o.seed) + 0.02 * noise(a * 9.1, o.seed + 7);

  function ring(p, rr, k, thin, far, skip = inGap) {   // 一道地面环带（远半圈 / 近半圈分开画）；k = 亮度 0–1，thin = 线宽，skip = 哪些角度不画
    if (k <= 0.02 || rr < 2) return;
    const step = 0.7 / rr;
    for (let a = 0; a < TAU; a += step) {
      if ((Math.sin(a) < 0) !== far || skip(a)) continue;
      const r = rr * jag(a), x = Math.cos(a) * r, y = Math.sin(a) * r * SY;
      const hi = 0.5 + 0.5 * noise(a * 5 + t * 6, o.seed + 3);
      p.blend(Math.round(x), Math.round(y), hi > 0.7 ? S[4] : C[clamp(Math.round(3 + 3 * k), 2, 6)], (far ? 0.6 : 0.9) * k);
      if (thin > 1) p.blend(Math.round(x * 0.985), Math.round(y * 0.985), C[clamp(Math.round(2 + 2 * k), 1, 5)], 0.6 * k);
    }
  }

  function flare(p, f) {
    const u = t - f.d;
    if (u < 0) return;
    const grow = ease.outQuart(clamp(u / 0.16)), fade = 1 - (el >= 2 ? smooth(0.4, 0.75, u) : smooth(0.28, 0.55, u));
    if (fade <= 0) return;
    const N = Math.ceil(f.h * 1.5), seen = new Set();
    for (let i = 0; i <= N * grow; i++) {
      const v = i / N, ang = f.a + f.twist * v * 1.4, rr = f.r0 + v * 10;
      const x = Math.cos(ang) * rr + 2 * noise(v * 4, f.sd), y = Math.sin(ang) * rr * SY - v * f.h;
      const w = f.w * Math.sin(Math.PI * Math.min(1, v * 1.15)) * (0.75 + 0.5 * (0.5 + 0.5 * noise(v * 7, f.sd + 1)));
      for (let d = -w; d <= w; d += 0.5) {
        const q = Math.abs(d) / Math.max(w, 0.5), px = Math.round(x + d), py = Math.round(y), key = px * 1000 + py;
        if (seen.has(key)) continue;
        seen.add(key);
        const hot = u < 0.05 ? 2 : u < 0.1 ? 1 : 0;   // 首帧外缘白热，第 2 帧余热，之后回到色阶中段
        const edge = q > 0.6;
        const ci = clamp(Math.round((edge ? 5.5 : 3) + v * 0.8 - (1 - fade) * 2 + hot), 1, 7);
        p.blend(px, py, edge && v > 0.7 && u > 0.1 ? S[3] : C[ci], (edge ? 0.95 : 0.7) * Math.min(1, fade * 1.3));   // 弧焰尖端转海蓝
      }
    }
  }

  function spout(p, sp, far) {
    if ((Math.sin(sp.a) < 0) !== far) return;
    const u = t - sp.d;
    if (u < 0) return;
    const rise = ease.outQuart(clamp(u / 0.12)), fall = smooth(0.26, 0.55, u);
    if (fall >= 1) return;
    const r = sp.r * jag(sp.a), bx = Math.cos(sp.a) * r, by = Math.sin(sp.a) * r * SY, H = sp.h * rise * (1 - fall * 0.85);
    for (let d = 0; d <= H; d += 1) {
      const v = d / Math.max(H, 1), w = sp.w * (1 - v * 0.6) * (0.8 + 0.4 * (0.5 + 0.5 * noise(d * 0.4, sp.sd)));
      for (let k = -w; k <= w; k += 1) {
        const crest = v > 0.72, lit = k < -w + 1.2;   // 浪头一截亮白 / 海蓝，左侧受光
        p.blend(Math.round(bx + k + 1.5 * noise(d * 0.2, sp.sd + 1)), Math.round(by - d), crest ? (u < 0.2 ? C[6] : S[4]) : lit ? S[3] : C[clamp(Math.round(2 + v * 3), 2, 5)], (crest || lit ? 0.95 : 0.75) * (far ? 0.75 : 1) * (1 - fall * 0.6));
      }
    }
  }

  function tent(p, f, far) {   // 海嗣触须：从潮冠边缘升起，绕身盘旋上升，梢头往里卷
    const u = t - f.d;
    if (u < 0) return;
    const grow = ease.outQuart(clamp(u / 0.22)), fade = 1 - smooth(0.55, 0.9, u);
    if (fade <= 0) return;
    const N = Math.ceil(f.h * 2), seen = new Set();
    for (let i = 0; i <= N * grow; i++) {
      const v = i / N, ang = f.a + f.dir * f.turn * v, rr = f.r0 * (1 - 0.35 * v) + 6 * Math.sin(Math.PI * v);
      if ((Math.sin(ang) < 0) !== far) continue;
      const x = Math.cos(ang) * rr + 1.5 * noise(v * 5, f.sd), y = Math.sin(ang) * rr * SY - v * f.h;
      const w = 5.5 * Math.pow(1 - v, 0.8) + 0.7;
      let sp = 0;
      for (const s2 of f.spikes) if (Math.abs(v - s2.v) < 0.03) sp = s2.l * (1 - Math.abs(v - s2.v) / 0.03);
      const out = Math.cos(ang) >= 0 ? 1 : -1;   // 锯齿长在外侧
      for (let d = -w - (out < 0 ? sp : 0); d <= w + (out > 0 ? sp : 0); d += 0.5) {
        const px = Math.round(x + d), py = Math.round(y), key = px * 1000 + py;
        if (seen.has(key)) continue;
        seen.add(key);
        const lit = d < -w + 1.2, rim = Math.abs(d) > w - 1;   // 左侧受光一线海蓝
        p.blend(px, py, lit ? S[4] : rim ? S[3] : S[v > 0.5 ? 1 : 0], (rim || lit ? 0.95 : 0.9) * fade * (far ? 0.85 : 1));
      }
      if (deco && f.dots.some((q) => Math.abs(q - v) < 0.008)) p.px(Math.round(x), Math.round(y), S[5]);   // 青色光点：位置随机
    }
  }

  // 脚下潮水：不规则地铺开的一摊酒红水面（外缘噪声起伏），把潮冠和地面连成一体，不是孤立圆
  function wash(p) {
    const u = clamp(t / 0.2), fade = 1 - smooth(0.35, 0.75, t), Rw = 44 * (0.4 + 0.6 * ease.outQuart(u));
    if (fade <= 0) return;
    p.shade(-Rw * 1.4, -Rw * SY * 1.4, Rw * 1.4, Rw * SY * 1.4, (x, y) => {
      const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY) / (Rw * (1 + 0.28 * noise(a * 2.2, o.seed + 11) + 0.1 * noise(a * 7, o.seed + 4)));
      if (r > 1) return;
      p.blend(x, y, C[r > 0.82 ? 4 : r > 0.5 ? 2 : 1], (r > 0.82 ? 0.75 : 0.45) * fade);
    });
  }
  // 歌声前沿后面拖的一层半透明水幕（装饰）：只在前沿内侧 0.78–1.0 之间，越往里越淡，跟着前沿走
  function sheet(p, far) {
    const rf = front(t), k = 1 - smooth(FRONT * 0.6, FRONT + 0.15, t);
    if (k <= 0.02 || rf < 8) return;
    const B = rf * 1.06;
    p.shade(-B, -B * SY, B, B * SY, (x, y) => {
      if ((y < 0) !== far) return;
      const a = Math.atan2(y / SY, x);
      if (inGap(a)) return;
      const q = Math.hypot(x, y / SY) / (rf * jag(a));
      if (q > 1 || q < 0.78) return;
      p.blend(x, y, (0.5 + 0.5 * noise(a * 6 + q * 9, o.seed + 5)) > 0.75 ? S[2] : C[2], 0.32 * k * (q - 0.78) / 0.22);
    });
  }

  // 歌域内部的装饰（画在地面，潮冠之下）：一切随时间慢慢往中心汇聚
  function field(p) {
    const env = smooth(0.05, 0.2, t) * (1 - smooth(0.7, 1.1, t));   // 起、落
    if (env <= 0.01) return;
    const pull = (u) => 1 - 0.35 * ease.inQuad(clamp(u));            // 半径随时间收拢
    for (const m of inner.mist) {   // 暗酒红水雾：噪声形的一团，半透明、很淡
      const u = (t - m.d) / 0.8;
      if (u < 0) continue;
      const rr = m.r * pull(u), cx = Math.cos(m.a) * rr, cy = Math.sin(m.a) * rr * SY;
      for (let y = -m.s * SY; y <= m.s * SY; y++) for (let x = -m.s; x <= m.s; x++) {
        const q = Math.hypot(x / m.s, y / (m.s * SY)) / (1 + 0.45 * noise(Math.atan2(y, x) * 1.7 + x * 0.05, m.sd));
        if (q > 1) continue;
        p.blend(Math.round(cx + x), Math.round(cy + y), C[3], 0.26 * env * (1 - q));
      }
    }
    for (const s2 of inner.shadows) {   // E2：海嗣触须投在地上的影子（深色、弯、拉长）
      const u = t - s2.d;
      if (u < 0) continue;
      const k = smooth(0, 0.2, u) * env;
      for (let i = 0; i <= s2.L; i++) {
        const v = i / s2.L, ang = s2.a + s2.bend * v * 0.6, rr = s2.r * pull(u / 0.8) - v * 10;
        const x = Math.cos(ang) * rr + Math.cos(ang + 1.57) * v * s2.L * 0.6, y = (Math.sin(ang) * rr + Math.sin(ang + 1.57) * v * s2.L * 0.6) * SY;
        const w = 3 * (1 - v) + 0.6;
        for (let d = -w; d <= w; d += 1) p.blend(Math.round(x), Math.round(y + d * 0.6), S[0], 0.42 * k);
        if (i % 9 === 4) p.blend(Math.round(x), Math.round(y - w * 0.6), S[3], 0.45 * k);   // 影子边上一点海蓝反光
      }
    }
    for (const st of inner.strokes) {   // 潮纹：短而弯的水纹，朝中心流
      const u = (t - st.d) / 0.8;
      if (u < 0) continue;
      const rr = st.r * pull(u), base = st.a + st.tilt;
      for (let i = 0; i <= st.L; i++) {
        const v = i / st.L, ang = st.a + (v - 0.5) * st.L / Math.max(rr, 20), r2 = rr + 1.6 * noise(v * 3 + st.sd, st.sd);
        const x = Math.cos(ang) * r2, y = Math.sin(ang) * r2 * SY;
        const hi = el >= 2 && v > 0.4 && v < 0.6;
        p.blend(Math.round(x), Math.round(y), hi ? S[4] : C[4], (hi ? 0.65 : 0.55) * env * Math.sin(Math.PI * v));
      }
    }
    for (const w of inner.waves) {   // E1+：音波短弧——零散、半径各不相同，起伏按噪声，慢慢往里挪
      const u = t - w.d;
      if (u < 0 || u > 0.55) continue;
      const k = Math.sin(Math.PI * u / 0.55) * env, rr = w.r * (1 - 0.25 * u);
      for (let a = w.a; a < w.a + w.w; a += 0.6 / rr) {
        const r2 = rr + 2.2 * noise(a * 9 + u * 4, w.sd);
        p.blend(Math.round(Math.cos(a) * r2), Math.round(Math.sin(a) * r2 * SY), S[4], 0.6 * k);
      }
    }
    for (const n of inner.notes) {   // 海色光点 / 音符状小光斑：往中心飘、各自一闪
      const u = (t - n.d) / n.l;
      if (u < 0 || u >= 1) continue;
      const rr = n.r * (1 - 0.6 * ease.inQuad(u)), ang = n.a + n.spin * u;
      const x = Math.round(Math.cos(ang) * rr), y = Math.round(Math.sin(ang) * rr * SY - 2 - u * 6);
      const flash = n.fl > 0 && Math.abs(u - n.fl) < 0.06;   // 偶尔一闪：只有少数光点、只亮一两帧，仍低于敌弹芯（不出纯白）
      const k = Math.sin(Math.PI * u) * env, c = flash ? C[6] : n.hi && el >= 2 ? S[5] : S[4];
      p.blend(x, y, c, flash ? 0.95 : 0.8 * k);
      if (flash) { p.blend(x - 1, y, c, 0.5); p.blend(x + 1, y, c, 0.5); p.blend(x, y - 1, c, 0.5); }
      if (n.note) { p.blend(x + 1, y - 1, c, 0.55 * k); p.blend(x + 1, y - 2, c, 0.5 * k); p.blend(x + 1, y - 3, c, 0.45 * k); }   // 音符：一点加一根短杆
    }
  }

  return {
    update(dt) {
      t += dt;
      if (!burst) {
        burst = true;
        if (deco) lights.add(0, CHEST, 16 + 5 * el, C[5], glowK, 0.12);   // 首帧白热只留一下（§1：第 2 帧余热降档）
      }
      if (deco) for (const sp of spouts) if (!sp.popped && t - sp.d >= 0.24) {   // 浪花冠碎开：水珠往外落
        sp.popped = true;
        const r = sp.r * jag(sp.a), x = Math.cos(sp.a) * r, y = Math.sin(sp.a) * r * SY - sp.h;
        for (let i = 0, n = Rg.int(1, 3); i < n; i++) ps.spawn(P.FLAKE, x, y, Math.cos(sp.a) * Rg.range(20, 60), -Rg.range(0, 40), Rg.range(0.2, 0.2 + tail * 0.6), Rg.chance(0.5) ? S[4] : C[5], Rg.range(1, 1.8));
      }
      if (deco && t < 0.45) {   // 歌声光点：沿螺旋往上飘，起点、速度、寿命都随机
        const n = Rg.chance(0.5 + 0.2 * el) ? Rg.int(1, 1 + el) : 0;
        for (let i = 0; i < n; i++) {
          const a = Rg.range(0, TAU), r = Rg.range(8, 30), x = Math.cos(a) * r, y = Math.sin(a) * r * SY - Rg.range(0, 20);
          ps.spawn(Rg.chance(0.6) ? P.MOTE : P.FLAKE, x, y, -Math.sin(a) * Rg.range(20, 50), -Rg.range(40, 90), Rg.range(0.3, 0.3 + tail), Rg.chance(0.7) ? S[Rg.int(3, 5)] : C[6], Rg.range(1, 2));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (deco) field(p);
      if (deco) sheet(p, true);
      if (core) wash(p);
      if (core) {
        const k = 1 - smooth(FRONT * 0.7, FRONT + 0.12, t);
        ring(p, front(t), k, 2, true);
        if (el >= 1) { const u = t - FRONT - 0.04; if (u > 0) ring(p, R * (0.8 + 0.2 * ease.outQuad(clamp(u / 0.3))), 0.8 * (1 - smooth(0.2, 0.42, u)), 2, true, offEcho); }   // 余音：主前沿将散时外圈起几段更细的回声弧
      }
      if (core) { for (const sp of spouts) spout(p, sp, true); for (const f of tents) tent(p, f, true); }
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      if (deco) sheet(p, false);
      if (deco) {
        lights.draw(p);
        const k = 1 - smooth(0, 0.25, t);
        if (k > 0) p.glow(0, CHEST, 12 + 4 * el, C[5], glowK * 0.8 * k);   // 光晕压小：大光团量化后会出一圈圈色带，读成同心圈
        if (el >= 1) {   // 余音弧上的海蓝光点：沿弧随机撒、各自一闪
          const u = t - FRONT - 0.04;
          if (u > 0 && u < 0.45) for (const g of echo) for (let k = 0; k < 6; k++) {
            const a = g.a + g.w * ((k * 0.618 + g.a) % 1), rr = R * (0.8 + 0.2 * ease.outQuad(clamp(u / 0.3))) * jag(a);
            const tw = Math.sin(Math.PI * clamp((u - k * 0.03) / 0.25));
            if (tw > 0.05) p.blend(Math.round(Math.cos(a) * rr), Math.round(Math.sin(a) * rr * SY) - 1, S[5], 0.4 * tw);
          }
        }
        for (const r of res) {   // 余韵：歌域里零星闪点，alpha ≤ 0.4
          const u = (t - FRONT - r.d) / r.l;
          if (u < 0 || u >= 1) continue;
          p.blend(Math.round(r.x), Math.round(r.y - u * 3), S[r.c], 0.4 * Math.sin(Math.PI * u));
        }
      }
      if (core) {
        const k = 1 - smooth(FRONT * 0.7, FRONT + 0.12, t);
        ring(p, front(t), k, 2, false);
        if (el >= 1) { const u = t - FRONT - 0.04; if (u > 0) ring(p, R * (0.8 + 0.2 * ease.outQuad(clamp(u / 0.3))), 0.8 * (1 - smooth(0.2, 0.42, u)), 2, false, offEcho); }   // 余音：主前沿将散时外圈起几段更细的回声弧
        for (const f of flares) flare(p, f);
        for (const sp of spouts) spout(p, sp, false);
        for (const f of tents) tent(p, f, false);
        if (t < 0.1) {   // 胸前一点白热（不是圆盘：不规整的小星芒，臂长不等）
          const k2 = t < 0.05 ? 1 : 0.5, arms = [[1, -0.3, 7], [-1, 0.2, 5], [0.2, -1, 9], [-0.3, 1, 4]];
          p.px(0, CHEST, C[7]);
          for (const [dx, dy, L] of arms) for (let i = 1; i <= L * k2 * (el >= 2 ? 1.4 : 1); i++) p.px(Math.round(dx * i), Math.round(CHEST + dy * i), C[clamp(7 - Math.floor(i / 2), 4, 7)]);
        }
      }
      if (deco) ps.draw(p);
    },
  };
}
