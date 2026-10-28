"""Animate original background pixels, with no additional visual layers."""
from pathlib import Path
import xml.etree.ElementTree as E
P=Path(__file__).resolve().parent
N='http://www.w3.org/2000/svg'
E.register_namespace('',N)
def t(s): return '{'+N+'}'+s
tr=E.parse(P/'packed_layout_v16.svg'); r=tr.getroot()
for c in list(r):
    if c.get('id') in ('ocean-motion','ocean-motion-style'): r.remove(c)
d=E.Element(t('defs'),{'id':'ocean-motion'})
f=E.SubElement(d,t('filter'),{'id':'ocean-image-flow','x':'-3%','y':'-3%','width':'106%','height':'106%','color-interpolation-filters':'sRGB'})
n=E.SubElement(f,t('feTurbulence'),{'type':'fractalNoise','baseFrequency':'.003 .005','numOctaves':'1','seed':'7','result':'flow'})
E.SubElement(n,t('animate'),{'attributeName':'baseFrequency','values':'.003 .005;.004 .006;.003 .005','dur':'24s','repeatCount':'indefinite'})
E.SubElement(f,t('feDisplacementMap'),{'in':'SourceGraphic','in2':'flow','scale':'24','xChannelSelector':'R','yChannelSelector':'G'})
for c in r:
    if c.tag==t('image') and c.get('href')=='ocean_backdrop_v7.png':
        c.attrib.update({'class':'sea-texture','filter':'url(#ocean-image-flow)','x':'-20','y':'-12','width':'1712','height':'965'})
r.insert(0,d)
tr.write(P/'packed_layout_v16.svg',encoding='unicode')
print('Original image flow; no added rays, haze or dust.')
