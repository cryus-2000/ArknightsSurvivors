# Boss 弹幕第二版新旧对照录像（docs/306 §8）：同一提交、同 seed，render/danmaku_v2 = 0（旧）/ 1（新）各录一遍（30 帧原速）。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --split --cmd 'SPEC=carmen MOVES=环射,环射,环射 bash tools/gcp/render_jobs/danmaku_ab.sh' …
#   SPEC = --bossmoves 参数（二阶段加 2）；MOVES = --bossonly（重复几次，录满 SECS 秒）；SECS 缺省 7
#   --nocross --norecruit：2:30 的翻卡 / 商人 / 招募面板会把画面停住，录像里关掉
# 结果：$MEDIA/frames/<SPEC>_<old|new>/fr_*.jpg（画面中央 1280×720 原像素，不缩放）；本机 tools/danmaku_ab_mp4.py 拼成左旧右新的 mp4
#   （渲染镜像没有 ffmpeg，帧在虚拟机上用 Python 裁切转 jpg）
set +e
SECS="${SECS:-7}"
N=$((SECS * 30))
python3 tools/asset_index.py >/dev/null 2>&1
for v in old new; do
    d="/work/frames/${SPEC}_$v"; mkdir -p "$d"   # 原始帧放 /work，不进 $OUT（$OUT 会提交进结果分支）
    k=1; [ "$v" = old ] && k=0
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --nocross --norecruit --seed=3 --op=mizuki --bossmoves="$SPEC" --bossonly="$MOVES" --flashrec=151.0,$N,1920 \
        --bal=render/danmaku_v2=$k --shotdir="$d" > "$OUT/${SPEC}_$v.log" 2>&1
    echo "$SPEC $v：$(ls $d/fr_*.png 2>/dev/null | wc -l) 帧；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/${SPEC}_$v.log) 处脚本错误"
    mkdir -p "$MEDIA/frames/${SPEC}_$v"
    python3 - "$d" "$MEDIA/frames/${SPEC}_$v" <<'PYEOF'
import sys, glob, os
src, dst = sys.argv[1], sys.argv[2]
try:
    from PIL import Image
except ImportError:
    import shutil
    for f in glob.glob(os.path.join(src, "fr_*.png")):
        shutil.copy(f, dst)
    sys.exit(0)
for f in sorted(glob.glob(os.path.join(src, "fr_*.png"))):
    im = Image.open(f).convert("RGB")
    w, h = im.size
    im.crop(((w - 1280) // 2, (h - 720) // 2, (w + 1280) // 2, (h + 720) // 2)).save(os.path.join(dst, os.path.basename(f)[:-4] + ".jpg"), quality=93)
PYEOF
done
du -sh "$MEDIA"
exit 0
