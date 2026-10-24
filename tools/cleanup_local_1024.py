# 10-24 用户授权的本地清理：① 旧美术存档一份到仓库外 ② 删已合入 / 已废弃的工作树（跳过在用会话、有未提交改动的）③ 清 build/ 旧包、旧日志、旧截图
import os, sys, shutil, subprocess, time

ROOT = r"E:\ArknightsSurvivors"
ARCHIVE = r"E:\ArknightsSurvivors_archive\art_incoming_20261024"
APPLY = "--apply" in sys.argv

def git(*a, cwd=ROOT):
    return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")

def size_mb(p):
    t = 0
    for dp, dn, fn in os.walk(p):
        for f in fn:
            try: t += os.path.getsize(os.path.join(dp, f))
            except OSError: pass
    return t / 1048576

# ① 旧美术存档（整个 art/incoming 快照，仓库外，纪念用）
if not os.path.exists(ARCHIVE):
    print("archive art/incoming ->", ARCHIVE)
    if APPLY:
        shutil.copytree(os.path.join(ROOT, "art", "incoming"), ARCHIVE)

# ② 工作树
KEEP = {  # 在用会话 / 未定分支
    "interesting-kilby-98da4d", "confident-hopper-080e16", "jovial-franklin-5e6711", "ecstatic-lichterman-f81c72",
    "suspicious-aryabhata-40115b", "quirky-turing-39a39f", "blissful-keller-3f9eaa", "competent-colden-ad5406",
    "infallible-visvesvaraya-634c79", "ulp-glad", "codex-art", "codex-fx-unified", "codex-ui-shell", "codex-mizuki-canvas",
}
FORCE_DEL = {"hh-render", "vibrant-sinoussi-e0174e", "agent-a99d3bb17ce82f2c5"}  # 用户点名：未合提交已被取代
wl = git("worktree", "list", "--porcelain").stdout.split("\n\n")
freed = 0.0
for blk in wl:
    lines = dict(l.split(" ", 1) for l in blk.strip().splitlines() if " " in l)
    w = lines.get("worktree", "")
    br = lines.get("branch", "").replace("refs/heads/", "")
    name = os.path.basename(w)
    if not w or os.path.normcase(w) == os.path.normcase(ROOT) or name in KEEP:
        continue
    if not (".claude/worktrees" in w.replace("\\", "/") or ".worktrees" in w.replace("\\", "/")):
        continue
    merged = br and git("merge-base", "--is-ancestor", br, "main").returncode == 0
    if name.startswith("codex-"):
        print("skip (codex, ask first)", name); continue
    if not (merged or name in FORCE_DEL):
        print("skip (unmerged)", name, br); continue
    dirty = git("status", "--porcelain", "--untracked-files=no", cwd=w).stdout.strip() if os.path.isdir(w) else ""
    if dirty:
        print("skip (uncommitted changes)", name); continue
    mb = size_mb(w) if os.path.isdir(w) else 0
    freed += mb
    print("remove worktree %-40s %-36s %7.0f MB" % (name, br, mb))
    if APPLY:
        r = git("worktree", "remove", "--force", w)
        if r.returncode != 0:
            print("   worktree remove failed:", r.stderr.strip()[:200]); shutil.rmtree(w, ignore_errors=True)
if APPLY:
    git("worktree", "prune")

# ③ build/
B = os.path.join(ROOT, "build")
KEEP_B = {"release", "trace_cache", "check_cache", "prts_ref", "ref", "ui_ref", "spine_run_trial", "_export", "_web",
          "check", "look_proto", "ta_review", "op_ui_shots", "old_art_cleanup_1024", "op_1x", "lg_src", "move_attack_gif",
          "command_rec", "hud_prompts", "toy", "latest-spine-inventory.json", "toy_cover_notext.png", "toy_cover_preview.png"}
KEEP_TAGS = ("2da84ab26", "b2253df8", "e97b4a2")  # 最新对内包与 EA 冻结的验证日志
cut = time.time() - 2 * 86400
for e in sorted(os.listdir(B)):
    p = os.path.join(B, e)
    if e in KEEP_B or any(t in e for t in KEEP_TAGS):
        continue
    old = os.path.getmtime(p) < cut
    is_verify = e.startswith("encrypted_") or e.startswith("check_") or e.endswith(".log")
    if not (old or is_verify):
        continue
    mb = size_mb(p) if os.path.isdir(p) else os.path.getsize(p) / 1048576
    freed += mb
    print("delete build/%-48s %7.0f MB" % (e, mb))
    if APPLY:
        shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else os.remove(p)
# build/check：只留最近 5 个 quick_*
qs = sorted([d for d in os.listdir(os.path.join(B, "check")) if d.startswith("quick_")], key=lambda d: os.path.getmtime(os.path.join(B, "check", d)))
for d in qs[:-5]:
    p = os.path.join(B, "check", d)
    mb = size_mb(p); freed += mb
    if APPLY: shutil.rmtree(p, ignore_errors=True)
print("check/: delete %d old quick_* dirs" % max(0, len(qs) - 5))
print("TOTAL %.1f GB %s" % (freed / 1024, "freed" if APPLY else "(dry run)"))
