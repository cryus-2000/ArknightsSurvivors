# -*- coding: utf-8 -*-
"""pixelfx 放开版开录前门禁（协调人 11-04，用户批流程改造；docs/242 §14.24）。一条命令依次查：
  1. 当前 HEAD / 分支，和 --sha 对得上（防止录到旧提交；--sha 写前缀即可）
  2. 重建贴图索引 game/art/index.json、godot --import（经 godot_runner，无头、静音）
  3. tools/px_ul_lint.py <干员> 必须 0 条警告
  4. 无头跑图鉴演示（普攻 / S1 / S2 / S3 / 终结技，精二）：这名干员实际加载的放开版帧条数、演示里取用过的放开版帧条数，任一为 0 判 FAIL；
     同时看兜底路径有没有被触发（通用刀光弧 melee_arc、终结技公共灰褐烟尘 / 碎石 / 粒子 ult_*、静默去色 mark_zone），触发了判 FAIL 并列出来源
  5. 截一帧（图鉴演示 S3）存 <主仓库>/Claude outputs/pixelfx_prerecord/<干员>_<sha>.png
  6. 输出 PRERECORD PASS / FAIL，退出码 0 / 1
用法：python tools/px_prerecord.py <干员> [--sha <提交前缀>] [--skip-shot] [--modes 3,0,1,2,4]
tools/px_demo_rec.py 开录前强制调用；tools/px_trace_ab.py 复用第 2 步（prep_assets）。
"""
import argparse, glob, json, os, shutil, subprocess, sys, tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
GAME = os.path.join(ROOT, "game")
sys.path.insert(0, TOOLS)
import godot_runner as GR
import asset_index as AI

MODES = {3: "普攻", 0: "S1", 1: "S2", 2: "S3", 4: "终结技"}
SECS = {3: 4.0, 0: 6.5, 1: 7.0, 2: 7.5, 4: 10.0}


def prep_assets(log=print):
    """重建贴图索引（和磁盘不一致时）+ godot --import；返回索引名字数"""
    errs = AI.check()
    idx, _ = AI.build()
    if errs:
        with open(AI.INDEX, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(AI.dump(idx))
        log("贴图索引已重建（原来：%s）" % "；".join(errs[:2]))
    GR.run_godot([GR.find_godot(), "--headless", "--path", GAME, "--import"], 900)
    log("贴图索引 %d 个名字；已 --import" % len(idx))
    return len(idx)


def git(*a):
    return subprocess.run(["git"] + list(a), cwd=ROOT, capture_output=True, text=True).stdout.strip()


def demo(op, mode, out_dir="", n=None, start=1.0, k=1):
    args = [GR.find_godot()] + (["--headless"] if not out_dir else []) + ["--path", GAME, "--fixed-fps", "30", "--audio-driver", "Dummy", "res://tests/px_demo_rec.tscn", "--",
            "--rec_op=" + op, "--rec_stage=2", "--rec_mode=%d" % mode, "--rec_dir=" + out_dir.replace(os.sep, "/"), "--rec_start=%g" % start,
            "--rec_n=%d" % (n if n is not None else int(SECS[mode] * 30)), "--rec_w=%d" % (444 * k), "--rec_h=%d" % (388 * k), "--bal=gallery/demo_zoom=%g" % (0.68 * k), "--bal=fx/px_unleashed=1"]
    o, e, to = GR.run_godot(args, 600)
    st = None
    for ln in o.splitlines():
        if ln.startswith("PXSTATS "):
            st = json.loads(ln[8:])
    return st, GR.script_errors(o, e)[:3], to


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("op")
    ap.add_argument("--sha", default="")
    ap.add_argument("--modes", default="3,0,1,2,4")
    ap.add_argument("--skip-shot", action="store_true")
    a = ap.parse_args()
    fails = []
    head, br = git("rev-parse", "HEAD"), git("rev-parse", "--abbrev-ref", "HEAD")
    dirty = git("status", "--porcelain", "--untracked-files=no")
    print("1. HEAD %s（%s）%s" % (head[:9], br, "，有未提交改动" if dirty else ""))
    if a.sha and not head.startswith(a.sha):
        fails.append("HEAD %s 不是 --sha %s" % (head[:9], a.sha))
    print("2. ", end="")
    prep_assets()
    r = subprocess.run([sys.executable, os.path.join(TOOLS, "px_ul_lint.py"), a.op], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    print("3. px_ul_lint：" + (r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "无输出"))
    if r.returncode:
        fails.append("px_ul_lint 有警告：" + "；".join(r.stdout.strip().splitlines()[:-1][:4]))
    loaded, used, fb = 0, {}, {}
    for m in [int(x) for x in a.modes.split(",") if x != ""]:
        st, errs, to = demo(a.op, m)
        if st is None:
            fails.append("图鉴演示 %s 没跑完（%s%s）" % (MODES.get(m, m), "；".join(errs), " 超时" if to else ""))
            continue
        if errs:
            fails.append("图鉴演示 %s 脚本错误：%s" % (MODES.get(m, m), "；".join(errs)))
        loaded = max(loaded, int(st.get("loaded", 0)))
        for k, v in st.get("stats", {}).items():
            if k.startswith("used:") and a.op in k:
                used[k[5:]] = used.get(k[5:], 0) + int(v)
            elif k.startswith("fallback:") and k.endswith("@" + a.op):
                fb["%s（%s）" % (k[9:].split("@")[0], MODES.get(m, m))] = int(v)
    print("4. 放开版帧条已加载 %d 张；演示里取用过 %d 种" % (loaded, len(used)))
    if loaded == 0:
        fails.append("这名干员的放开版帧条一张都没加载（索引 / 导入 / V6_FRAMES 登记）")
    if not used:
        fails.append("演示里一次放开版帧条都没取用（注册表没接上）")
    if fb:
        fails.append("触发了兜底画面：" + "、".join("%s ×%d" % kv for kv in sorted(fb.items())))
    if not a.skip_shot:
        tmp = tempfile.mkdtemp(prefix="pxpre_")
        try:
            demo(a.op, 2, tmp, n=1, start=2.5, k=2)
            pngs = sorted(glob.glob(os.path.join(tmp, "rec_*.png")))
            dst_dir = os.path.join(GR.common_root(), "Claude outputs", "pixelfx_prerecord")
            os.makedirs(dst_dir, exist_ok=True)
            if pngs:
                dst = os.path.join(dst_dir, "%s_%s.png" % (a.op, head[:9]))
                shutil.copy2(pngs[0], dst)
                print("5. 截图 " + dst)
            else:
                fails.append("截图失败")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    for f in fails:
        print("  ✗ " + f)
    print("PRERECORD", "PASS" if not fails else "FAIL")
    sys.exit(0 if not fails else 1)


if __name__ == "__main__":
    main()
