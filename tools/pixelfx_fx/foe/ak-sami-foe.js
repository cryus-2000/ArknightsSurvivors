// 萨米敌人攻击特效主形（docs/401）：照原作 enemy_sm* 特效预制体的配色与结构（F:/sami_enemy_fx_ref/prefabs/summary.txt），只画主形；
// 火花 / 烟 / 余烬 / 雪块这类颗粒在游戏里用运行时像素粒子做（themes/sami/mech/mech_fx.gd），帧条里不重复画。
// 原点 = 命中点 / 出手点，俯视，朝 +x 的件游戏按方向旋转。1 纹素 = 2 世界像素（house.PX）。
// part：
//   slash  爪击 / 斩击命中：一道月牙刀光（白 → 主色 → 黑）+ 背后一片暗影；原作 smsbr_attack_01_hit / smgrd_attack_02_hit（slash01 / hit01 贴片 + 暗 bg）
//   pop    法术弹命中：不规则亮团（白芯）→ 冷却成主色，外面一圈暗边；原作 smwiz_attack_01_hit（bao_dm 亮团 + bg 暗底）
//   star   出手星闪：四芒星（细长、白芯、主色边）+ 暗底一闪；原作 smwiz_attack_01_start_02（star01 / bg01 / ray01）、smgrd 十字星 shizixing
//   nova   冰爆：白闪 → 冰蓝冲击环外扩（不等宽、有断口）→ 地面留一片冷白霜渍；原作 snslime_die_01_start（baoshan / huan / dimian）
//   charge 蓄能：暗红能量团呼吸 + 三圈环向内收拢，末段一记十字星；原作 smgrd_attack_01_start（ball / huan / shizixing）
// ramp：7 阶暗 → 亮（[0] 最暗、[6] 白）；不传按 part 用原作色。
import { Rng, clamp, ease, TAU, WHITE, hex, mix } from "../../core/index.js";

// 原作色（prefabs.json 起始色 / 颜色曲线）
export const RAMPS = {
  steel: ["#050608", "#0c1015", "#1f2732", "#333f4f", "#5d6c80", "#b8c4d2", "#ffffff"],   // 坍缩系：白 → 钢蓝灰 (0.2,0.25,0.31) → 黑
  ice: ["#030c22", "#06204f", "#1a4f8f", "#3d82c9", "#8ec0ff", "#d4e8ff", "#ffffff"],      // 施法者法术：冰蓝 (0.56,0.78,1.0)，暗底黑
  frost: ["#00122e", "#003a7a", "#0b6fc0", "#30b8e6", "#8ae4f5", "#ddf8ff", "#ffffff"],    // 冰爆虫：青 (0.18,0.73,1.0) → 深蓝 (0,0.13,1.0)
  blood: ["#0a0000", "#2b0000", "#6e0000", "#c80d0d", "#ff4a26", "#ffb08a", "#ffffff"],    // 利刃：黑 + 深红 (0.82,0,0)，火花红橙 (1,0.58,0.26)
};

export const meta = {
  name: "AK Sami foe fx",
  desc: "Sami enemy attack shapes from above: a crescent claw slash, a ragged spell pop, a four-point flash star, an ice nova ring and a dark red charge with converging rings.",
  tags: ["enemy", "hit", "one-shot"],
  size: [96, 96],
  origin: [48, 48],
  duration: 1.0,   // 各 part 自己的时长见 DUR，之后是空帧（烘焙时裁掉）
  loop: false,
  fps: 15,
  bg: "ground",
  options: { part: "slash", R: 16, ramp: "", seed: 1 },
};

const DUR = { slash: 0.4, pop: 0.34, star: 0.34, nova: 0.6, charge: 0.94 };

export function create(o) {
  const P = o.part, R = o.R, Rn = new Rng(o.seed);
  const RAMP = (Array.isArray(o.ramp) ? o.ramp : RAMPS[o.ramp] || RAMPS[{ slash: "steel", pop: "ice", star: "ice", nova: "frost", charge: "blood" }[P]]).map(hex);
  const D = DUR[P] || 0.5;
  const BLACK = RAMP[0];
  // 月牙刀光的外缘起伏（不规整）
  const jag = Array.from({ length: 9 }, () => Rn.range(0.95, 1.05));
  const blob = Array.from({ length: 8 }, (_, i) => ({ a: (i / 8) * TAU + Rn.range(-0.3, 0.3), r: Rn.range(0.55, 1.3) }));
  const gaps = [Rn.range(0, TAU), Rn.range(0, TAU)];
  const chunks = Array.from({ length: 7 }, (_, i) => ({ a: (i / 7) * TAU + Rn.range(-0.35, 0.35), d: Rn.range(0.45, 1.0), s: Rn.range(1, 2.2) }));
  let t = 0;

  // 月牙：中心在 (-R*0.35, 0)，扫过 -half..half，厚度在中段最厚、两端尖
  function crescent(p, rr, half, thick, col, a = 1, sweep = 1) {
    const N = 14, pts = [], inner = [];
    const a1 = -half + 2 * half * sweep;
    for (let i = 0; i <= N; i++) {
      const u = i / N, ang = -half + (a1 + half) * u;
      const jj = jag[Math.floor(u * 8)] * (1 - (u * 8 % 1)) + jag[Math.min(8, Math.floor(u * 8) + 1)] * (u * 8 % 1);
      const th = thick * Math.sin(Math.PI * u) ** 0.8;
      pts.push([Math.cos(ang) * rr * jj - R * 0.75, Math.sin(ang) * rr * jj]);
      inner.push([Math.cos(ang) * (rr * jj - th) - R * 0.75, Math.sin(ang) * (rr * jj - th)]);
    }
    p.poly(pts.concat(inner.reverse()), col, a);
  }

  return {
    update(dt) { t += dt; },
    draw(p) {
      if (t >= D) return;
      if (P === "slash") {
        // 暗影先铺（原作 bg01 暗底 + slash02 黑影），刀光压在上面：白（1 帧）→ 主色 → 黑，向外略扩、变薄
        const u = clamp(t / D), grow = 1 + 0.18 * ease.outCubic(u);
        const sw = clamp(t / 0.07);
        const c = t < 0.07 ? WHITE : t < 0.14 ? RAMP[5] : t < 0.21 ? RAMP[4] : t < 0.28 ? RAMP[3] : RAMP[2];
        const th = R * (t < 0.14 ? 0.62 : 0.62 * (1 - (t - 0.14) / (D - 0.14)) + 0.1);
        const rr = R * 1.25 * grow;
        if (t < D - 0.04) crescent(p, rr, 1.05, th, c, 1, Math.max(0.4, sw));
        if (t < 0.14) crescent(p, rr, 0.85, th * 0.4, WHITE, 1, Math.max(0.4, sw));
        // 刃口外侧一条细亮边（只前 3 帧）
        if (t < 0.2) crescent(p, rr + 1, 1.0, 1.4, t < 0.07 ? WHITE : RAMP[5], 0.9, Math.max(0.4, sw));
        if (t < 0.1) p.glow(R * 0.4, 0, R * 0.9, RAMP[4], 0.35 * (1 - t / 0.1));
      } else if (P === "pop") {
        const u = clamp(t / D), rr = R * (0.45 + 0.75 * ease.outQuart(u));
        const pts = blob.map((b) => [Math.cos(b.a) * rr * b.r, Math.sin(b.a) * rr * b.r * 0.85]);
        // 暗边（原作 bg：黑 35%）比亮团大一圈，往外淡
        if (t < 0.24) {
          const c = t < 0.07 ? WHITE : t < 0.14 ? RAMP[5] : RAMP[4];
          p.poly(pts, t < 0.07 ? RAMP[4] : RAMP[3], t < 0.17 ? 1 : 0.7);
          p.poly(pts.map(([x, y]) => [x * 0.55, y * 0.55]), c);
        } else {
          // 冷却：只剩一圈不连续的主色碎边
          for (const b of blob) {
            const x = Math.cos(b.a) * rr * b.r, y = Math.sin(b.a) * rr * b.r * 0.85;
            p.disc(x, y, 1.4, RAMP[2], 1 - u);
          }
        }
        if (t < 0.1) p.glow(0, 0, R * 1.1, RAMP[4], 0.45 * (1 - t / 0.1));
      } else if (P === "star") {
        // 四芒星：0–0.07 白芯闪亮、尖刺最长；之后收缩冷却；斜 45° 一对短刺
        const u = clamp(t / D), L = R * (t < 0.07 ? 1.15 : 1.15 * (1 - ease.inQuad(clamp((t - 0.07) / (D - 0.07)))));
        const w = Math.max(1, R * 0.16 * (1 - u * 0.6));
        const c = t < 0.07 ? WHITE : t < 0.14 ? RAMP[5] : RAMP[4];
        for (const [dx, dy, k] of [[1, 0, 1], [-1, 0, 1], [0, 1, 0.75], [0, -1, 0.75], [0.7, 0.7, 0.4], [-0.7, 0.7, 0.4], [0.7, -0.7, 0.4], [-0.7, -0.7, 0.4]]) {
          const l = L * k;
          if (l < 1) continue;
          p.poly([[dx * l, dy * l], [-dy * w, dx * w], [-dx * w * 1.5, -dy * w * 1.5], [dy * w, -dx * w]], k < 0.5 ? RAMP[3] : c);
        }
        p.disc(0, 0, Math.max(1, w * 1.2), t < 0.14 ? WHITE : RAMP[5], 1);
        if (t < 0.12) p.glow(0, 0, R * 1.2, RAMP[4], 0.5 * (1 - t / 0.12));
      } else if (P === "nova") {
        const u = clamp(t / D);
        // 地面霜渍：0.08 起铺开，冷白、透出地面（原作 dimian 白 + andi 深蓝）
        if (t > 0.05) {
          const fr = R * 0.9 * ease.outCubic(clamp((t - 0.05) / 0.2));
          for (const ch of chunks) for (let k = 0; k < 3; k++) p.dot(Math.cos(ch.a + k * 0.12) * fr * (ch.d * 0.7 + k * 0.08), Math.sin(ch.a + k * 0.12) * fr * (ch.d * 0.7 + k * 0.08), RAMP[5], 0.8 * (1 - u));
        }
        // 白闪
        if (t < 0.1) {
          // 白闪：实心不规则核 + 6 根冰刺（原作 baoshan + baoci），不画半透明外圈
          p.poly(blob.map((b) => [Math.cos(b.a) * R * 0.42 * b.r, Math.sin(b.a) * R * 0.36 * b.r]), t < 0.05 ? WHITE : RAMP[5]);
          for (const ch of chunks.slice(0, 6)) {
            const L = R * (t < 0.05 ? 0.75 : 0.95) * ch.d;
            p.beam(Math.cos(ch.a) * R * 0.25, Math.sin(ch.a) * R * 0.22, Math.cos(ch.a) * L, Math.sin(ch.a) * L * 0.85, 1.5, t < 0.05 ? RAMP[6] : RAMP[4]);
          }
        }
        // 冲击环：碎冰环（原作 huan），粗、不等宽、5 处断口，外扩到 R，0.32 秒内碎完；不画细环
        const ru = ease.outQuart(clamp(t / 0.3)), rr = R * (0.25 + 0.8 * ru);
        if (t < 0.32) {
          const c = t < 0.07 ? RAMP[5] : t < 0.14 ? RAMP[4] : t < 0.21 ? RAMP[3] : RAMP[2];   // 浅雪地：环用中深阶，白只给第 0 帧的核
          const segs = 15;
          for (let i = 0; i < segs; i++) {
            if (i % 3 === 2) continue;                          // 断口
            const a0 = (i / segs) * TAU + gaps[0], a1 = a0 + TAU / segs * 0.85;
            const w = Math.max(2, R * (0.3 - 0.15 * ru) * (0.7 + 0.6 * chunks[i % 7].d));
            p.arc(0, 0, rr, w, a0, a1, c, 1);
          }
        }
        if (t < 0.14) p.glow(0, 0, R * 1.2, RAMP[4], 0.55 * (1 - t / 0.14));
      } else if (P === "charge") {
        // 0–0.8 蓄：暗红团呼吸放大（原作 ball 0.48,0,0 + spin 0.82,0,0），三圈环从 2.2R 向内收（huan：黑 → 红 → 白，收到中心消失）
        // 0.8–0.94 十字星爆闪（shizixing：黑 → 红 → 白 → 红 → 黑）
        const ct = Math.min(t, 0.8) / 0.8;
        if (t < 0.84) {
          const br = R * (0.28 + 0.16 * ct + 0.04 * Math.sin(t * 40));
          p.disc(0, 0, br, RAMP[2], 1);
          p.disc(0, 0, br * 0.6, RAMP[3], 1);
          if (ct > 0.6) p.disc(0, 0, br * 0.3, RAMP[5], 1);
          for (let k = 0; k < 2; k++) {
            const ph = (ct * 1.6 + k / 2) % 1;
            if (t > 0.78 && ph > 0.5) continue;
            const rr = R * 2.1 * (1 - ease.inQuad(ph));
            if (rr < br) continue;
            const c = ph < 0.4 ? RAMP[1] : ph < 0.75 ? RAMP[3] : RAMP[5];
            if (ph > 0.15) p.ring(0, 0, rr, ph < 0.5 ? 2 : 3, c, 1);   // 实心粗环（不用半透明抖点的细环）
          }
          p.glow(0, 0, R * 1.1, RAMP[3], 0.25 + 0.3 * ct);
        }
        if (t >= 0.78) {
          const st = (t - 0.78) / 0.16, L = R * 1.6 * (st < 0.4 ? 1 : 1 - (st - 0.4) / 0.6), w = Math.max(1, R * 0.12);
          const c = st < 0.25 ? RAMP[3] : st < 0.5 ? WHITE : st < 0.8 ? RAMP[3] : RAMP[1];
          for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) p.poly([[dx * L, dy * L], [-dy * w, dx * w], [-dx * w, -dy * w], [dy * w, -dx * w]], c);
          p.glow(0, 0, R * 1.4, RAMP[4], 0.6 * (1 - st));
        }
      }
    },
  };
}
