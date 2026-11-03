// 乌尔比安「放开版」技能起手（claude/pixelfx-ul-ulpianus，开关 fx/px_unleashed）：原点 = 脚底（地面），往上为 -y，地面透视 y × SY。
// 原作参照（ulpia.ab，只作参照）：S2 skill_02_buff_01 = 身上一团靛光 + 脚下一圈锯齿状往上蹿的水焰（ulpia_05）；S2 / S3 start_01 = 抡锚弧 + 水往里收。
// move：
//   cast1  S1「必须促成的接触」：几缕水从脚边往锚上收（锚在身前上方），收到一点一闪
//   cast2  S2「必须维系的界限」：脚下一圈不规整的水焰往上蹿（高矮不一、有断口，不是整圈），身上一团靛光；E2 焰尖带暗酒红
//   cast3  S3「必须开辟的通路」：脚下先压暗，水从四周往脚下收（预兆），再一记爆亮 + 矮水焰
import { Particles, Lights, P, Rng, fit, clamp, smooth, ease, noise, TAU } from "../../core/index.js";
import { jitterAngles, OP } from "../house.js";

export const meta = {
  name: "Ulpianus skill cast unleashed",
  desc: "Deep-sea water gathered into the anchor, a ragged crown of water flames rising round the feet, or a darkening pull of water to the feet before a flash.",
  tags: ["water", "buff", "cast", "charge", "one-shot"],
  size: [200, 200],
  origin: [100, 150],
  duration: 1.0,
  loop: false,
  fps: 24,
  bg: "dark",
  options: {
    palette: OP.ulpianus,   // 色阶只认 house.js（§11.1 #12）
    blood: OP.ulpianus_blood,   // 色阶只认 house.js（§11.1 #12）
    move: "cast2",
    elite: 2,
    quick: 0,
    spray: 0,          // 1 = 画往外甩的水珠 / 火星 / 碎石（docs/242 §14.7 用户 11-04 取消，缺省 0；尘 / 水雾保留）
    layer: "all",
    seed: 3,
  },
};

const SY = 0.55;

export function create(o) {
  const C = fit(o.palette, 8), BL = fit(o.blood, 4), Rg = new Rng(o.seed), mv = o.move || "cast2", el = clamp(Math.round(+o.elite), 0, 2), quick = +o.quick > 0;
  const core = o.layer !== "deco", deco = o.layer !== "core", DL = (quick ? 0.55 : 1) * [0.6, 0.8, 1][el];
  const ps = new Particles({ rng: Rg, ground: () => 1e9, sparks: [C[7], C[6], C[6], C[5]], haze: C[4] }), lights = new Lights();
  if (!(+o.spray > 0)) { const sp0 = ps.spawn.bind(ps); ps.spawn = (k, ...a) => (k === P.DUST || k === P.VAPOUR || k === P.SMOKE ? sp0(k, ...a) : null); }   // §14.7：甩出物不画
  const TIP = [18, -34];                 // 锚尖（身前上方）
  const RF = mv === "cast3" ? 26 : 22;   // 水焰圈半径（地面）
  const T0 = mv === "cast3" ? 0.22 : mv === "cast2" ? 0.05 : 0.0;   // 水焰起来的时刻（S3 先压暗收水）
  // 水焰：不等距的若干簇，每簇几根高矮不一的焰舌；整圈约 60% 有焰
  const flames = [];
  if (mv !== "cast1") for (const a of jitterAngles(Rg, mv === "cast3" ? 8 : 9, -Math.PI, Math.PI, 0.48)) {
    if (Rg.chance(0.25)) continue;
    flames.push({ a, H: (mv === "cast3" ? 14 : 22 + 5 * el) * Rg.range(0.5, 1.05), w: Rg.range(2.4, 3.8), d0: Rg.range(0, 0.08), wob: Rg.range(0, 9), lean: Math.cos(a) * Rg.range(0.25, 0.5) });
  }
  // 往里收的水缕（cast1 收到锚尖，cast3 收到脚下）
  const wisps = mv === "cast2" ? [] : jitterAngles(Rg, mv === "cast3" ? 9 : 6, -Math.PI, Math.PI, 0.48).map((a) => ({ a, r0: Rg.range(30, 52), d0: Rg.range(0, 0.1), tw: Rg.range(-0.6, 0.6) }));
  const tgt = mv === "cast1" ? TIP : [0, 0];
  let t = 0, popped = false;
  const POP = mv === "cast1" ? 0.2 : mv === "cast3" ? 0.24 : 0.06;
  return {
    update(dt) {
      t += dt;
      if (!popped && t >= POP) {
        popped = true;
        lights.add(tgt[0], tgt[1] - (mv === "cast1" ? 0 : 14), mv === "cast3" ? 40 : 26, C[6], 0.5, 0.14);
        if (deco) for (let k = 0, n = mv === "cast2" ? 10 : 8; k < n; k++) {
          const a = Rg.range(-Math.PI, Math.PI), v = Rg.range(30, 100);
          ps.spawn(k % 3 ? P.MOTE : P.SPARK, tgt[0], tgt[1] - 6, Math.cos(a) * v, Math.sin(a) * v * 0.6 - Rg.range(30, 90), Rg.range(0.3, 0.6) * DL, C[6 + Rg.int(0, 1)], Rg.range(0.7, 1.2));
        }
      }
      if (deco && mv !== "cast1") for (const f of flames) {   // 焰尖飘起的水沫
        const u = t - T0 - f.d0;
        if (u > 0.05 && u < 0.4 && Rg.chance(0.12)) {
          const [x, y] = [Math.cos(f.a) * RF, Math.sin(f.a) * RF * SY - f.H * 0.8];
          ps.spawn(P.MOTE, x, y, Rg.range(-10, 10), -Rg.range(20, 50), Rg.range(0.3, 0.6) * DL, el >= 2 && mv === "cast2" && Rg.chance(0.3) ? BL[3] : C[6], Rg.range(0.7, 1.1));
        }
      }
      ps.update(dt);
      lights.update(dt);
    },
    drawBack(p) {
      if (core && mv === "cast3") {   // 压暗：脚下一片不规整暗影，越来越大，爆亮后退去
        const k = smooth(0, 0.18, t) * (1 - smooth(0.28, 0.5, t)) * 0.6, rr = 20 + 16 * ease.outCubic(clamp(t / 0.22));
        if (k > 0.02) p.each(-rr * 1.3, -rr * SY * 1.3, rr * 1.3, rr * SY * 1.3, (x, y, sx, sy) => {
          const a = Math.atan2(y / SY, x), r = Math.hypot(x, y / SY), e = rr * (0.75 + 0.3 * noise(a * 3, o.seed + 11));
          if (r < e) p.blendPx(sx, sy, C[0], k * (1 - Math.pow(r / e, 3) * 0.6));
        });
      }
      if (deco) ps.draw(p, "back");
    },
    draw(p) {
      // 往里收的水缕：细线从外往目标收，带一点旋，前端亮
      if (core) for (const w of wisps) {
        const u = t - w.d0, D = POP - w.d0;
        if (u < 0 || u > D + 0.04) continue;
        const k = clamp(u / D), head = w.r0 * (1 - ease.inCubic(k)), tail = w.r0 * (1 - ease.inCubic(clamp(k - 0.35)));
        for (let r = head; r < tail; r += 0.6) {
          const a = w.a + w.tw * (r / w.r0), x = tgt[0] + Math.cos(a) * r, y = tgt[1] + Math.sin(a) * r * (mv === "cast1" ? 0.8 : SY);
          p.px(x, y, r - head < 2 ? C[7] : C[clamp(Math.round(6 - 3 * (r - head) / Math.max(1, tail - head)), 3, 6)]);
        }
      }
      // 水焰：从地面往上蹿的焰舌，底宽尖细，边缘 noise 起伏，尖白；E2 尖上带暗酒红
      if (core) for (const f of flames) {
        const u = t - T0 - f.d0;
        if (u < 0 || u > 0.55 * DL + 0.15) continue;
        const H = f.H * ease.outCubic(clamp(u / 0.12)) * (1 - smooth(0.25 * DL + 0.08, 0.55 * DL + 0.15, u));
        const bx = Math.cos(f.a) * RF, by = Math.sin(f.a) * RF * SY;
        for (let d = 0; d < H; d += 0.6) {
          const v = d / Math.max(1, f.H), sway = noise(d * 0.18 + u * 6 + f.wob, o.seed + 3) * 2.2 * v + f.lean * d;   // 往外斜，焰身随 noise 摆
          const w = f.w * Math.pow(1 - d / Math.max(1, H), 1.4) * (0.8 + 0.35 * noise(d * 0.3 + f.wob, o.seed + 7)) + 0.3;
          for (let q = -w; q <= w; q += 0.6) {
            const tipz = d > H - 2.2;
            p.px(bx + q + sway, by - d, tipz ? (el >= 2 && mv === "cast2" ? BL[3] : C[7]) : Math.abs(q) > w - 0.7 ? C[6] : C[clamp(Math.round(2.5 + 3.5 * v), 2, 6)]);
          }
        }
      }
      // 爆亮一帧：不规整的白芯（锚尖 / 脚下）
      if (core && t >= POP && t < POP + 0.05) {
        const rr = mv === "cast3" ? 8 : 5;
        p.shade(tgt[0] - rr * 1.6, tgt[1] - rr * 1.6 - (mv === "cast1" ? 0 : 10), tgt[0] + rr * 1.6, tgt[1] + rr * 1.6 - (mv === "cast1" ? 0 : 10), (x, y, out) => {
          const dx = x - tgt[0], dy = y - tgt[1] + (mv === "cast1" ? 0 : 10), a = Math.atan2(dy, dx), r = Math.hypot(dx, dy * 1.2);
          const e = rr * (0.4 + 0.6 * Math.pow(Math.abs(noise(a * 2.7, o.seed + 21)), 0.6));
          if (r > e) return;
          out.c = r < e * 0.5 ? C[7] : C[6];
        });
      }
      if (deco) {
        if (mv === "cast2" && t < 0.6 * DL + 0.1) p.glow(0, -22, 20, C[4], 0.35 * (1 - smooth(0.2, 0.6 * DL + 0.1, t)));   // 身上一团靛光（贴着人，不是地上的圆）
        lights.draw(p);
        ps.draw(p, "front");
      }
    },
  };
}
