import sys, json, subprocess, pathlib, datetime
root = pathlib.Path(__file__).resolve().parents[2] / 'docs/product/mobile-block-ai-v1/results/ui-polish-2026-10-13'
label = sys.argv[1]
subprocess.run(['xcrun', 'simctl', 'io', 'C5C8CE03-EBEE-4F71-A327-5F208D20B49C', 'screenshot', str(root / (label + '.png'))], check=True, capture_output=True, text=True)
records = [json.loads(line.split('SIMULATOR_UI_METRICS ', 1)[1]) for line in (root.parents[1] / 'evidence/shared/ui-polish-2026-10-13/after-run.log').read_text().splitlines() if 'SIMULATOR_UI_METRICS ' in line]
record = dict(records[-1], screenshot=label+'.png', captured_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
record['input_preparation'] = 'Draft fixture entered with Flutter Driver; emulation disabled before native software-keyboard open/dismiss checks.'
record['input_mode'] = 'Native software keyboard for open/dismiss states; fixture is synthetic'
(root / (label + '.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n')
print(json.dumps(record, ensure_ascii=False))
