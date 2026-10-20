"""Verify original PNG borders against independent Flutter render-box telemetry."""
import hashlib, json, sys
from pathlib import Path
from PIL import Image
root=Path(sys.argv[1]).resolve()
results=[]
expected_draft='中文草稿\n第二行'
for record_path in sorted(root.glob('native-2[0-7]-*.json')):
    data=json.loads(record_path.read_text())
    path=root/data['screenshot']
    im=Image.open(path).convert('RGB')
    dpr=data['dpr']
    assert im.size == (round(data['logical_width']*dpr),round(data['logical_height']*dpr))
    assert data['draft']==expected_draft
    assert data['requests']==data['terminal_writes']==0
    collapsed='collapsed' in path.stem
    assert data['keyboard_inset']==0 if collapsed else data['keyboard_inset']>0
    assert data['focused']==(not collapsed)
    if collapsed:
        x,y=round(data['composer_x']*dpr),round(data['composer_y']*dpr)
        w,h=round(data['composer_width']*dpr),round(data['composer_height']*dpr)
        scans=[x+round(w*f) for f in (0.2,0.35,0.5,0.65,0.8)]
        border=im.getpixel((scans[2],y))
        background=im.getpixel((scans[2],y-1))
        assert border!=background
        for scan in scans:
            for depth in (*range(y,y+3),*range(y+h-3,y+h)):
                assert im.getpixel((scan,depth))==border,(path.name,scan,depth)
            for depth in (y-1,y+h):
                assert im.getpixel((scan,depth))==background,(path.name,scan,depth)
            for depth in (y+3,y+h-4):
                assert im.getpixel((scan,depth))!=border,(path.name,scan,depth)
        assert h/dpr==data['composer_height']<=56
        data.update(border_rgb=border,background_rgb=background,scan_x_pixels=scans,top_pixel_inclusive=y,bottom_pixel_exclusive=y+h,outer_height_pixels=h,verified_height_logical=h/dpr)
    data.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),original_size_pixels=im.size,collapsed_required=collapsed)
    results.append(data)
assert len(results)==8
assert {(r['theme'],r['orientation']) for r in results if r['collapsed_required']}=={('light','portrait'),('dark','portrait'),('light','landscape'),('dark','landscape')}
result=json.loads((root/'native-measurements.json').read_text())
result.update(result='PASS',measurements=results)
(root/'native-measurements.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'result':'PASS','states':[{k:r[k] for k in ('theme','orientation','outer_height_pixels','verified_height_logical')} for r in results if r['collapsed_required']]},ensure_ascii=False,indent=2))
