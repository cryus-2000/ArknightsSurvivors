"""标题页·深海水母（方向二 青光航标）游戏素材烘焙：
- scene.png      640×360 场景底图（Codex 43 版原图，不改像素）
- glow.png       640×360 灰度柔光遮罩（高亮像素 → 高斯模糊；着色器里按青色加亮，水母与暗部分层）
- logo_mark.png  Logo 主体：像素徽记（塔 + 三角）与像素中文；拉丁小字（ARKNIGHTS / RHODES ISLAND / SURVIVORS）
                 原素材里 SURVIVORS 有错形，改由游戏内矢量字画
运行：D:/Anaconda/python.exe -B art/incoming/title_jelly_1024/bake_game_assets.py
"""
from pathlib import Path
from PIL import Image, ImageFilter

P = Path(__file__).resolve().parent
ROOT = P.parents[2]
OUT = ROOT / 'game/art/ui/title_deep'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bg = Image.open(P / 'src/background_native.png').convert('RGB')
    bg.save(OUT / 'scene.png', optimize=True)
    # 1920 上 28px 模糊 = 原图 9.3px；阈值 150 同对照图
    mask = bg.convert('L').point(lambda v: 255 if v > 150 else 0)
    mask.filter(ImageFilter.GaussianBlur(9.3)).save(OUT / 'glow.png', optimize=True)
    src = Image.open(P / 'src/logo.png').convert('RGBA')
    mark = Image.new('RGBA', (src.width, 86), (0, 0, 0, 0))
    mark.alpha_composite(src.crop((0, 0, 124, 86)), (0, 0))
    mark.alpha_composite(src.crop((124, 18, src.width, 86)), (124, 18))
    mark.save(OUT / 'logo_mark.png', optimize=True)
    for f in ('scene.png', 'glow.png', 'logo_mark.png'):
        print(f, (OUT / f).stat().st_size)


if __name__ == '__main__':
    main()
