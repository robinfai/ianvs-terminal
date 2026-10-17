"""Verify original PNG borders against independent Flutter render-box telemetry."""
import hashlib, json
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[2] / 'docs/product/mobile-block-ai-v1/results/ui-polish-2026-10-13'
results=[]
expected_draft='中文草稿\n第二行'
for record_path in sorted(root.glob('2[0-7]-*.json')):
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
result={'result':'PASS','source_base':'e1296bbf973065145a6f533d30c766284769aa60', 'source_state':'UI polish patch documented in design-qa.md','device':'iPhone 17 Pro simulator','os':'iOS 26.3.1 (23D8133)','font_policy':'fixed; TextScaler.noScaling','scope':'Production TerminalAiWorkspace(compactMobile:true) inside temporary local native-iOS harness; memory backend ports. Not full production authentication/session flow. Composer outer border includes its padding; excludes outside margin and OS safe area.','input':'Two-line fixture seeded via Flutter Driver, then text emulation disabled. Native iOS software keyboard opened/dismissed in each state, CUA controls rotated simulator. No physical-phone or composing-input claim.','runtime_errors':'None reported by Flutter MCP','measurements':results}
(root/'measurements.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'result':'PASS','states':[{k:r[k] for k in ('theme','orientation','outer_height_pixels','verified_height_logical')} for r in results if r['collapsed_required']]},ensure_ascii=False,indent=2))
