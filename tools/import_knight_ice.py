"""Pack user-supplied ice VFX into runtime strips; originals stay in ignored third_party."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import asset_paths
LIB = next(p for p in [ROOT / 'art/third_party/ice_20261027', ROOT.parents[1] / 'art/third_party/ice_20261027'] if p.exists())
P1 = 'pimen_01/Ice Effect 01/'
P2 = 'pimen_02/Ice Effect 02/'
SPECS = {
    'fx_knight_ice_wall': ('creativekind/ice_prison-Sheet.png', 64, list(range(36))),
    'prop_knight_frost_stake': ('rt:prop_ice_pillar', 64, list(range(4))),
    'prop_knight_frost_stake_rise': ('rt:prop_ice_pillar_rise', 64, list(range(3))),
    'prop_knight_frost_stake_break': ('rt:prop_ice_pillar_break', 64, list(range(6))),
    'fx_knight_crystal_rise': ('creativekind/ice crystal-Sheet.png', 64, list(range(7))),
    'fx_knight_crystal_hold': ('creativekind/ice crystal-Sheet.png', 64, [7, 8, 9]),
    'fx_knight_crystal_break': ('creativekind/ice crystal-Sheet.png', 64, list(range(10, 20))),
    'fx_knight_ice_crest': (P2+'Ice VFX 5/Ice VFX 5(48x32).png', 48, list(range(11))),
    'proj_knight_ice': (P1+'Ice VFX 1/IceVFX 1 Repeatable.png', 48, list(range(10))),
    'fx_knight_ice_hit': (P1+'Ice VFX 1/Ice VFX 1 Hit.png', 32, list(range(12))),
}
RAMP = [(12,27,40),(25,49,65),(40,72,92),(63,101,121),
        (94,137,151),(143,181,189),(196,218,218),(228,238,229)]

def main():
    records = {}
    for name, (source, fw, indices) in SPECS.items():
        path = Path(asset_paths.runtime_png(source.removeprefix('rt:'))) if source.startswith('rt:') else LIB / source
        im = Image.open(path).convert('RGBA')
        assert im.width % fw == 0 and max(indices) < im.width // fw
        strip = Image.new('RGBA', (fw * len(indices), im.height))
        for j, i in enumerate(indices):
            strip.paste(im.crop((i*fw, 0, (i+1)*fw, im.height)), (j*fw, 0))
        # Quantized steel/sea-ice ramp: shared with the Knight's dark environment,
        # with narrow warm-white highlights instead of saturated cyan bloom.
        pixels = strip.load()
        for y in range(strip.height):
            for x in range(strip.width):
                r,g,b,a = pixels[x,y]
                luminance = (r*.299 + g*.587 + b*.114)/255
                color = RAMP[min(7,int(luminance*7.99))]
                pixels[x,y] = (*color,a)
        out = Path(asset_paths.out_png(name))
        strip.save(out)
        records[name] = {'source':source, 'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'frames':len(indices), 'frame_size':[fw,im.height], 'indices':indices, 'palette':RAMP, 'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
        print(name, strip.size)
    (ROOT/'art/incoming/knight_ice_manifest.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
    import asset_index
    idx, _ = asset_index.build()
    open(asset_index.INDEX, 'w', encoding='utf-8', newline='\n').write(asset_index.dump(idx))

if __name__ == '__main__':
    main()
