# 技能期间滑步排查（11-08 维什戴尔 S2 移动时不播跑步）：图鉴演示 E2，--shot_walk=1 让主控放技能期间也上下来回走，
# --shot_log=1 每帧打印动画状态；汇总「在走（mv > 40）却播着非跑步帧条、也没换移动版贴图」的帧数，按 干员 / 招式 / 帧条 列表。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'bash tools/gcp/render_jobs/skill_run_scan.sh scan [干员…]'
#       录像：--cmd 'bash tools/gcp/render_jobs/skill_run_scan.sh rec wisadel 1'（干员 招式号，E2，30 帧原速 mp4 进 $MEDIA）
set +e
pgrep Xvfb >/dev/null || { Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 2; }
export DISPLAY=:99
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA" "$OUT"
MODE=$1; shift
one() {   # $1 干员 $2 招式 $3 目录（空 = 不存图） $4 张数
    timeout -k 30 600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game res://tests/elite_demo_shot.tscn -- \
        --shot_op=$1 --shot_stage=2 --shot_mode=$2 --shot_dir="$3" --shot_start=0.6 --shot_every=1 --shot_n=$4 --shot_w=1280 --shot_h=720 --quality=high \
        --shot_walk=1 --shot_log=1 $EXTRA
}
if [ "$MODE" = rec ]; then
    op=$1; m=$2; tag=${TAG:-new}
    FF="$(command -v ffmpeg)"
    if [ -z "$FF" ]; then
        pip3 install -q imageio-ffmpeg >/dev/null 2>&1 || python3 -m pip install -q --break-system-packages imageio-ffmpeg >/dev/null 2>&1
        FF="$(python3 -c 'import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null)"
    fi
    d="$(realpath -m "$OUT/rec_${op}_$m")"; rm -rf "$d"; mkdir -p "$d"
    one $op $m "$d" ${NF:-360} > "$d.log" 2>&1
    echo "rec $op $m：$(ls $d/f_*.png | wc -l) 张；$(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
    grep '^ANIM' "$d.log" > "$MEDIA/rec_${op}_${m}_anim.txt"
    "$FF" -y -loglevel error -framerate 30 -pattern_type glob -i "$d/f_*.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "$MEDIA/${op}_s$((m + 1))_move_${tag}.mp4" 2>>"$OUT/runs.txt"
    exit 0
fi
OPS="$*"; [ -z "$OPS" ] && OPS=$(ls game/data/characters/ | sed 's/\.json$//')
J=$(nproc); [ "$J" -gt 6 ] && J=6
for op in $OPS; do for m in 0 1 2; do
    while [ "$(jobs -rp | wc -l)" -ge "$J" ]; do sleep 1; done
    ( one $op $m "" ${NF:-480} > "$OUT/scan_${op}_$m.log" 2>&1 ) &
done; done
wait
python3 - "$OUT" "$MEDIA" <<'PY'
import sys, os, glob, re, collections
out, media = sys.argv[1], sys.argv[2]
RUNLIKE = re.compile(r'(^|_)run($|_)')
rows = []
for f in sorted(glob.glob(os.path.join(out, "scan_*.log"))):
    op, m = re.match(r'scan_(.+)_(\d)\.log', os.path.basename(f)).groups()
    moving = 0; bad = collections.Counter(); err = 0
    last = None; same = 0   # 跑步类帧条连续同一帧（定格滑步，11-08 维什戴尔 s2_run 卡在第 5 帧）
    for ln in open(f, errors="replace"):
        if "SCRIPT ERROR" in ln: err += 1
        if not ln.startswith("ANIM"): continue
        kv = dict(x.split("=", 1) for x in ln.split()[1:] if "=" in x)
        if float(kv["mv"]) <= 40:
            last = None; continue
        moving += 1
        k = kv["kind"]
        if kv.get("swap") == "1":
            last = None; continue
        if RUNLIKE.search(k):
            key = (k, kv["fr"])
            same = same + 1 if key == last else 0
            last = key
            if same >= 6:   # 走着 6 帧（0.2 秒）以上同一张跑步帧
                bad[k + "(定格)"] += 1
            continue
        last = None
        if k in ("idle", "hurt", ""):
            continue
        bad[k] += 1
    rows.append((op, int(m), moving, sum(bad.values()), bad, err))
with open(os.path.join(media, "skill_run_scan.txt"), "w") as fo:
    fo.write("干员 招式 走动帧 滑步帧 帧条明细（走动中播的非跑步帧条，未换移动版贴图） 脚本错误\n")
    for op, m, mv, nb, bad, err in rows:
        fo.write("%s %s %d %d %s %d\n" % (op, ["S1", "S2", "S3"][m], mv, nb, " ".join("%s:%d" % kv for kv in bad.most_common()), err))
print(open(os.path.join(media, "skill_run_scan.txt")).read())
PY
exit 0
