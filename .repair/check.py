import json
import os
from pathlib import Path
import signal
import subprocess

paths=json.loads(Path('.repair/export-paths.json').read_text())
checks=[('format',['dart','format',*[p for p in paths if p.endswith('.dart')]],'.',60),
        ('metadata',['python3','test/test_mobile_image_metadata.py'],'.',30),
        ('analyze',['flutter','analyze','--fatal-infos'],'example',180)]
for name,path in [('transport','ai/ai_chat_stream_test.dart'),('stream-controller','ai/terminal_ai_streaming_test.dart'),('compact-mobile','ai/terminal_ai_compact_mobile_test.dart'),('session-recovery','sessions/session_unavailable_recovery_test.dart')]:
    checks.append((name,['flutter','test','test/'+path,'--reporter','expanded','--timeout','30s'],'example',150))
checks += [('existing-ai',['flutter','test','test/ai','--reporter','expanded','--timeout','30s'],'example',420),('diff',['git','diff','--check'],'.',30)]
results=[]
for name,command,cwd,timeout in checks:
    if name=='existing-ai' and any(r['exit_code'] for r in results):
        results.append({'check':name,'command':command,'cwd':cwd,'exit_code':None,'status':'not_run_prior_failure'})
        continue
    print(f'CHECK_BEGIN {name}',flush=True)
    process=subprocess.Popen(command,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',start_new_session=True)
    try:
        output,_=process.communicate(timeout=timeout)
        code=process.returncode
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL)
        output,_=process.communicate()
        output+='\nCHECK TIMEOUT\n';code=124
    Path(f'.repair/{name}.log').write_text(output)
    lines=output.splitlines()
    important=[line for line in lines if any(word in line for word in ['Error:', 'Expected:', 'Actual:', '[E]', 'error •','warning •','info •','FAIL','Some tests failed','Exception:'])]
    print('\n'.join(important[-120:]),flush=True)
    print('\n'.join(lines[-45:]),flush=True)
    print(f'::notice title={name}::exit={code}',flush=True)
    print(f'CHECK_END {name} exit={code}',flush=True)
    results.append({'check':name,'command':command,'cwd':cwd,'exit_code':code})
    Path('.repair/results.json').write_text(json.dumps(results,indent=2))
Path('.repair/results.json').write_text(json.dumps(results,indent=2))
