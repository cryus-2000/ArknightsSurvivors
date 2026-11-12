# -*- coding: utf-8 -*-
"""PV 实机素材第三批（11-12）：在 GCP 虚拟机上跑一局真实对局、按窗口录帧，编成 mp4 + 逐帧指标 json。

  python3 tools/promo/pv_runs_late.py <名> <输出目录> --res=2560x1440 -- <传给游戏的参数…>

录帧脚本是 tools/promo/pv_rec_late.gd（11-08 的 pv_rec.gd 加：逐帧指标 pos、--pv_finalkill 击破段、--pv_q 存帧质量、
--forceending 指定的结局在最终 Boss 登场后连结局名 / 结局色一起对上、--pv_winsize）。
每段：<名>_<段>.mp4（缩放到 --res，避免奇数高度 x264 编不了）+ <名>_<段>.json（ts / sfx / pos），放进 $MEDIA。
本机发起（每局一台，并行）：
  python tools/gcp_render.py --branch <提交> --job custom --split --name pv1112 --dest F:/ArknightsSurvivors_pv/gcp \\
      --cmd 'bash tools/gcp/render_jobs/pv_rec_late.sh M01_skadi 1920x1080 --op=skadi --squad=… --pv_win=596-800 …'
"""
import glob, json, os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMMON = ['--balance', '--realtime', '--nodeath', '--nohints', '--bot=master', '--diff=4', '--quality=high', '--pickframes=3', '--slot4', '--bossdeath=pv']


def ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return 'ffmpeg'


def main():
    a = sys.argv[1:]
    name, out = a[0], a[1]
    res = next((x[6:] for x in a if x.startswith('--res=')), '1920x1080')
    game_args = a[a.index('--')+1:] if '--' in a else []
    media = os.environ.get('MEDIA', out)
    os.makedirs(out, exist_ok=True); os.makedirs(media, exist_ok=True)
    raw = os.path.join(out, name+'_raw'); shutil.rmtree(raw, ignore_errors=True); os.makedirs(raw)
    godot = os.environ.get('GODOT', 'godot')
    cmd = [godot, '--path', os.path.join(ROOT, 'game'), '--fixed-fps', '60', '--resolution', res, '--audio-driver', 'Dummy',
           '-s', os.path.join(ROOT, 'tools/promo/pv_rec_late.gd'), '--']+COMMON+game_args+['--pv_out='+raw]
    print('RUN', ' '.join(cmd), flush=True)
    with open(os.path.join(out, name+'.log'), 'w', encoding='utf8') as lf:
        rc = subprocess.call(cmd, stdout=lf, stderr=subprocess.STDOUT, timeout=float(os.environ.get('PV_TIMEOUT', '6600')))
    if os.path.exists(os.path.join(raw, 'pv.log')): shutil.copy2(os.path.join(raw, 'pv.log'), os.path.join(media, name+'_pv.log'))
    ok = []
    for sd in sorted(glob.glob(os.path.join(raw, 'seg_*'))):
        sj = os.path.join(sd, 'sfx.json')
        if not os.path.exists(sj) or not glob.glob(os.path.join(sd, 'f*.jpg')): continue
        seg = os.path.basename(sd)[4:].split('_t')[0]
        nj = int(json.load(open(sj, encoding='utf8'))['n'])
        dst = os.path.join(media, '%s_%s.mp4' % (name, seg))
        subprocess.check_call([ffmpeg(), '-y', '-v', 'error', '-framerate', '60', '-i', os.path.join(sd, 'f%05d.jpg'), '-frames:v', str(nj),
                               '-vf', 'scale=%s:flags=bicubic' % res.replace('x', ':'), '-an', '-c:v', 'libx264', '-crf', '23', '-preset', 'medium', '-pix_fmt', 'yuv420p', dst])
        shutil.copy2(sj, os.path.join(media, '%s_%s.json' % (name, seg)))
        ok.append(seg)
    shutil.rmtree(raw, ignore_errors=True)
    print('%s rc=%s segs=%s' % (name, rc, ','.join(ok)), flush=True)


if __name__ == '__main__':
    main()
