import hashlib
import json
from pathlib import Path
import runpy
import subprocess

plan=runpy.run_path('.repair/plan.py')['plan']
Path('.repair/plan.json').write_text(json.dumps(plan))
def git_blob(data):return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
for name,sha in plan['expected_blobs'].items():
    actual=git_blob(Path(name).read_bytes())
    if actual!=sha:raise SystemExit(f'Base blob mismatch {name}: {actual} != {sha}')
for change in plan['edits']:
    path=Path(change['path'])
    data=path.read_text()
    found=data.count(change['old'])
    if found!=change['count']:raise SystemExit(f'Anchor mismatch {path}: {found} != {change["count"]}: {change["old"][:100]}')
    path.write_text(data.replace(change['old'],change['new']))
names=sorted(set(plan['expected_blobs'])|set(plan['new_files']))
for name in names:
    if not Path(name).is_file():raise SystemExit(f'Missing new file {name}')
record='docs/product/mobile-block-ai-v1/evidence/shared/20261011T022419Z-c2d88f7b/result.json'
corrected=record.replace('result.json','result-metadata-corrected.json')
subprocess.run(['python3','tools/check_mobile_image_metadata.py',record,'--root','docs/product/mobile-block-ai-v1','--corrected',corrected],check=True)
names.append(corrected)
Path('.repair/export-paths.json').write_text(json.dumps(names))
Path('.repair/applied').write_text('applied to '+plan['base'])
print('APPLIED',len(plan['edits']),'anchored changes;',len(names),'files')
