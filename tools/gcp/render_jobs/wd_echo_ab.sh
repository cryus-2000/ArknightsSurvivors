# 维什戴尔余响收缩环修前 / 修后同帧（11-08 iPhone「粗白椭圆圈」）：同 wd_ring_hunt 的局（队长维什戴尔 + 安洁莉娜，中画质，100 秒起逐帧），
# old = --bal=fx/wd_echo_v=0，new = 1；保留 KEEP 指定种子:帧 前后各 2 帧，另把同局两边逐帧求差、列出不同的帧号（只该是余响那几帧）。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'bash tools/gcp/render_jobs/wd_echo_ab.sh'
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
T0=${T0:-100}; NF=${NF:-210}
KEEP=${KEEP:-"3:148 19:190"}
run() {   # $1 种子 $2 old|new
    d="$(realpath -m "$OUT/s$1_$2")"; mkdir -p "$d"
    v=1; [ "$2" = old ] && v=0
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=$1 --op=wisadel --squad=angelina --prog=4 --bot=master --quality=medium \
        --shotdir="$d" --rtfrom=$T0 --flashrec=$T0,$NF,1920 --maxt=$((T0 + NF / 30 + 2)) --bal=fx/wd_echo_v=$v > "$d/run.log" 2>&1
    echo "s$1 $2：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
for k in $KEEP; do s=${k%%:*}; run $s old & run $s new & done
wait
python3 - "$OUT" "$MEDIA" "$KEEP" <<'PY'
import sys, os, glob, shutil
from PIL import Image, ImageChops
out, media, keep = sys.argv[1], sys.argv[2], sys.argv[3].split()
rep = open(os.path.join(media, "diff.txt"), "w")
for k in keep:
    s, f0 = k.split(":"); f0 = int(f0)
    a = sorted(glob.glob(os.path.join(out, "s%s_old" % s, "fr_*.png")))
    diffs = []
    for fa in a:
        fb = fa.replace("_old", "_new")
        if not os.path.exists(fb):
            continue
        bb = ImageChops.difference(Image.open(fa).convert("RGB"), Image.open(fb).convert("RGB")).getbbox()
        if bb:
            diffs.append(os.path.basename(fa)[3:-4])
    rep.write("seed %s：%d 帧对比，%d 帧不同：%s\n" % (s, len(a), len(diffs), " ".join(diffs)))
    for f in range(f0 - 2, f0 + 3):
        for side in ("old", "new"):
            src = os.path.join(out, "s%s_%s" % (s, side), "fr_%05d.png" % f)
            if os.path.exists(src):
                shutil.copy(src, os.path.join(media, "s%s_%05d_%s.png" % (s, f, side)))
rep.close()
PY
cat "$MEDIA/diff.txt" | tee -a "$OUT/runs.txt"
exit 0
