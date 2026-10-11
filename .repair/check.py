import json
from pathlib import Path
import subprocess

paths=json.loads(Path('.repair/export-paths.json').read_text())
plan=json.loads(Path('.repair/plan.json').read_text())
checks=[('format',['dart','format',*[p for p in paths if p.endswith('.dart')]],'.'),
        ('metadata',['python3','test/test_mobile_image_metadata.py'],'.'),
        ('analyze',['flutter','analyze','--fatal-infos'],'example')]
checks += [(f'tests-{i+1}',command,'example') for i,command in enumerate(plan['tests'])]
checks += [('diff',['git','diff','--check'],'.')]
results=[]
for name,command,cwd in checks:
    print(f'CHECK_BEGIN {name}',flush=True)
    try:
        run=subprocess.run(command,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=900)
        output=run.stdout
        code=run.returncode
    except subprocess.TimeoutExpired as error:
        output=(error.stdout or b'')
        if isinstance(output,bytes):output=output.decode(errors='replace')
        output+='\nCHECK TIMEOUT\n'
        code=124
    Path(f'.repair/{name}.log').write_text(output)
    lines=output.splitlines()
    important=[line for line in lines if any(word in line for word in ['Error:', 'Expected:', 'Actual:', '[E]', 'error •','warning •','info •','FAIL','Some tests failed','Exception:'])]
    print('\n'.join(important[-140:]),flush=True)
    print('\n'.join(lines[-35:]),flush=True)
    print(f'CHECK_END {name} exit={code}',flush=True)
    results.append({'check':name,'command':command,'cwd':cwd,'exit_code':code})
Path('.repair/results.json').write_text(json.dumps(results,indent=2))
