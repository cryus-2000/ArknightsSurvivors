# 维什戴尔白色粗椭圆圈复现（11-08 iPhone 截图）：维什戴尔当队长 + 1 名队员，中画质，--rtfrom 快进后每帧截一张（宽 1280），几个种子并行。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'bash tools/gcp/render_jobs/wd_ring_hunt.sh'
# 环境变量：SEEDS（缺省 "3 7 11"）、T0（缺省 100）、NF（缺省 450 帧）、EXTRA（附加参数，如 --bal=fx/xxx=0）、SQUAD（缺省 saria）
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
T0=${T0:-100}; NF=${NF:-450}; SQ=${SQUAD:-saria}
run() {
    d="$(realpath -m "$OUT/s$1")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=$1 --op=wisadel --squad=$SQ --prog=4 --bot=master --quality=medium \
        --shotdir="$d" --rtfrom=$T0 --flashrec=$T0,$NF,1280 --maxt=$((T0 + NF / 30 + 2)) $EXTRA > "$d/run.log" 2>&1
    echo "seed $1：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
for s in ${SEEDS:-3 7 11}; do run $s & done
wait
# 找圈：近白偏冷（r,g > 215、b > 235）像素多、且分布成大环的帧，挑前 12 张原图进 $MEDIA
python3 - "$OUT" "$MEDIA" <<'PY'
import sys, os, glob, shutil
from PIL import Image
out, media = sys.argv[1], sys.argv[2]
rows = []
for f in sorted(glob.glob(os.path.join(out, "s*", "fr_*.png"))):
    im = Image.open(f).convert("RGB"); w, h = im.size; px = im.load()
    n = 0; xs = []; ys = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if r > 215 and g > 215 and b > 235 and b >= r:
                n += 1; xs.append(x); ys.append(y)
    span = (max(xs) - min(xs)) if xs else 0
    rows.append((n, span, f))
rows.sort(reverse=True)
with open(os.path.join(media, "hunt.txt"), "w") as fo:
    for n, span, f in rows[:60]:
        fo.write("%d %d %s\n" % (n, span, os.path.relpath(f, out)))
for n, span, f in rows[:12]:
    shutil.copy(f, os.path.join(media, os.path.basename(os.path.dirname(f)) + "_" + os.path.basename(f)))
PY
exit 0
