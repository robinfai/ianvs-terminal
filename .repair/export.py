import base64
import hashlib
import json
import os
from pathlib import Path
import urllib.request

paths=json.loads(Path('.repair/export-paths.json').read_text())
results=json.loads(Path('.repair/results.json').read_text())
manifest=[]
repo='robinfai/ianvs-terminal'
for name in paths:
    p=Path(name)
    if p.is_absolute() or '..' in p.parts or not name.startswith(('example/','tools/','test/','docs/')):raise SystemExit('Export path not allowed')
    data=p.read_bytes()
    if len(data)>1000000:raise SystemExit('Oversized candidate file')
    request=urllib.request.Request(f'https://api.github.com/repos/{repo}/git/blobs',
        data=json.dumps({'content':base64.b64encode(data).decode(),'encoding':'base64'}).encode(),
        headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json','Content-Type':'application/json'},method='POST')
    with urllib.request.urlopen(request,timeout=60) as response: value=json.load(response)
    expected=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
    if value['sha']!=expected:raise SystemExit('Uploaded blob does not match candidate')
    manifest.append({'path':name,'sha':value['sha'],'sha256':hashlib.sha256(data).hexdigest()})
print('CANDIDATE_MANIFEST_BEGIN')
print(json.dumps({'source_ref':os.environ.get('GITHUB_SHA'),'files':manifest,'checks':results},separators=(',',':')))
print('CANDIDATE_MANIFEST_END')
if any(check['exit_code'] for check in results):raise SystemExit(1)
