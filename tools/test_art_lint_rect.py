from pathlib import Path
import tempfile
from PIL import Image
import art_lint

def check():
    roster=art_lint.roster()
    result=art_lint.lint_op('wisadel',roster['wisadel'])
    size=next(r for r in result if r['check']=='size')
    assert size['level']=='PASS',size['detail']
    with tempfile.TemporaryDirectory(dir=Path(art_lint.ROOT)/'build') as tmp:
        for hi,scale in [(False,1),(True,2)]:
            Image.new('RGBA',(40*6*scale,56*scale),(30,40,50,255)).save(Path(tmp)/('rect'+('@2x' if hi else '')+'.png'))
        acts={'idle':{'tex':'rect','frames':6,'frame_size':[40,56],'foot':[20,54]}}
        bad=next(r for r in art_lint.lint_op('fixture',acts,art=tmp) if r['check']=='size')
        assert bad['level']=='FAIL','main bodies still require their square canvas'
    print('PASS real rectangular soul slots and strict main-body canvas')
if __name__=='__main__':check()
