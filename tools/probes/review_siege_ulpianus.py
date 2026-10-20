"""Assemble actual Godot viewport captures; never overlay character art or effects."""
from pathlib import Path
import json
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/siege_ulpianus_runtime'
sections = []
summary = {}
for op, label in [('siege', '推进之王'), ('ulpianus', '乌尔比安')]:
    evidence = json.loads((OUT / op / 'evidence.json').read_text())
    assert not evidence['missing']
    log = (OUT / (op + '_capture.log')).read_text(encoding='utf-8')
    assert 'failures=0' in log and 'SCRIPT ERROR' not in log and 'Parse Error' not in log
    cards = []
    clips = [('idle', '待机', 0, 16), ('run', '跑步', 16, 40),
             ('attack', '普通攻击', 40, 100), ('s1', 'S1', 155, 190),
             ('s2', 'S2', 235, 275), ('s3', 'S3 开启与攻击', 315, 370),
             ('s3_end', 'S3 末段与结束', 480, 540)]
    for key, title, start, end in clips:
        images = []
        for i in range(start, end):
            with Image.open(OUT / op / f'f_{i:04d}.png') as im:
                images.append(im.convert('RGB').crop((350, 145, 750, 350)).resize((800, 410), Image.Resampling.NEAREST))
        board = Image.new('RGB', (1600, 820))
        for k, i in enumerate([0, len(images)//3, 2*len(images)//3, len(images)-1]):
            board.paste(images[i], (k%2*800, k//2*410))
        palette = board.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        encoded = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in images]
        file = f'{op}_{key}.gif'
        encoded[0].save(OUT / file, save_all=True, append_images=encoded[1:], duration=50, loop=0, disposal=1)
        cards.append(f'<article><h3>{title}</h3><p>录制时间 {start/20:.2f}–{end/20:.2f} 秒，常速。<a href="{file}">单独打开</a></p><img loading="lazy" src="{file}"></article>')
    sections.append(f'<section id="{op}"><h2>{label}</h2>'+''.join(cards)+'</section>')
    summary[op] = {'frames_simulated': 540, 'seconds': 27, 'body_slots_observed': evidence['kinds'],
                   'missing_slots': [], 'script_errors': 0, 'exit_resource_warning': 'leaked' in log}
    Image.open(OUT / op / 'f_0030.png').save(OUT / f'{op}_gameplay.png')
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>推进之王、乌尔比安 · 实机接入</title><style>body{max-width:1250px;margin:24px auto;padding:0 18px;background:#1f2b38;color:#edf3f8;font:17px/1.7 system-ui}img{max-width:100%;image-rendering:pixelated}a{color:#a8d9ff}article{width:590px;max-width:100%;display:inline-block;vertical-align:top;margin:0 14px 24px 0}.note{background:#344252;padding:16px}section{border-top:1px solid #6b7e92;margin:30px 0}</style><h1>推进之王、乌尔比安 · 实机接入</h1><p class="note">换手号令已取消，S1 / S3 开启保持正常持锤姿态；两人最新素材已接入此测试分支。下列片段来自真实 Godot 游戏视口，各模拟 27 秒；只截取阶段片段，没有加速或后贴特效。</p><p>原有伤害事件、冷却、技能持续时间与位移保持不变；每人 61 行同种子 TRACE 对照一致。纯视觉收势不延长玩法窗口，新动作可以打断未完成的视觉收势。乌尔比安阶段姿势已绑定实际投出、回拉、停顿与弹射时间，原生四刃锚跟随真实落点与手部连接点。</p><p>录制夹具关闭自动技能充能，手动触发各技能；在非位移阶段将高生命测试敌人放回攻击范围，以便连续观察攻击。不是自然对局或平衡测试。</p><nav><a href="#siege">推进之王</a> · <a href="#ulpianus">乌尔比安</a> · <a href="capture_summary.json">记录</a></nav>'''
page += ''.join(sections) + '<p>此为独立本地测试分支，尚未合入 main 或公开发布。截图进程退出时有既有资源清理警告，日志未发现脚本或解析错误。</p></html>'
(OUT / 'review.html').write_text(page, encoding='utf-8')
(OUT / 'capture_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
print(OUT / 'review.html')
