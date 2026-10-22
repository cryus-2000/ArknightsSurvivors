"""Rasterise temporary reward readouts with the approved settlement font.
No source sprite or accepted image is edited.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
P=Path(__file__).resolve().parent
im=Image.new('RGBA',(180,1160))
d=ImageDraw.Draw(im);d.fontmode='1'
f=ImageFont.truetype('C:/Windows/Fonts/bahnschrift.ttf',32)
for n in range(29):d.text((0,n*40),'+'+str(n),font=f,fill=(244,246,246),anchor='lt')
for n in range(5):d.text((100,n*40),'×'+str(n),font=f,fill=(56,214,240),anchor='lt')
im.save(P/'counts.png')
# Original backdrop layers from render_desktop.py; used only under hidden data.
bg=Image.new('RGBA',(1280,720),(19,23,30));d=ImageDraw.Draw(bg)
d.polygon([(1068,44),(1184,44),(1044,648),(928,648)],fill=(23,28,36))
d.polygon([(726,44),(754,44),(614,648),(586,648)],fill=(23,28,36))
bg.alpha_composite(Image.open(P.parent/'settlement/decor/topography_sparse@2x.png').convert('RGBA'))
bg.save(P/'backdrop.png')
