"""Synthetic validator self-tests. All fixtures live in TemporaryDirectory.
They are NOT screenshots, recordings, or test results of the terminal app.
"""
import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from validate_evidence import validate, sha256_file, safe_path, timestamp

C='a'*40
E='b'*40

def png() -> bytes:
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\x00\x00\x00'))+chunk(b'IEND',b'')

class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        plan={'product':'test-desktop','stages':[]}
        shots=[]; cases=[]; stages=[]
        for n in range(1,5):
            sid=f'D{n}'; cid=f'{sid}-T01'; rid=f'{sid}-R01'
            case={'id':cid,'requirement_ids':[rid],'platform':'macos','minimum_capture_class':'app_desktop','video_required':n==1}
            plan['stages'].append({'id':sid,'cases':[case]})
            shots.extend([{'id':cid+'-F01','case_id':cid,'required_view':'full_app_window','theme':'light'}, {'id':cid+'-F02','case_id':cid,'required_view':'window_or_detail_with_anchor','theme':None}])
            cases.append({'id':cid,'requirement_ids':[rid],'status':'not_run','artifact_ids':[]})
            stages.append({'id':sid,'status':'planned','implementation_commit':None})
        (self.root/'plan.json').write_text(json.dumps(plan))
        (self.root/'shotlist.json').write_text(json.dumps({'shots':shots}))
        self.m={'schema_version':'1.0','product':'test-desktop','implementation_commit':C,'stages':stages,'cases':cases,'artifacts':[],'environments':[]}
    def passed(self,n=1):
        sid=f'D{n}';cid=sid+'-T01'
        self.m['stages'][n-1].update(status='verified',implementation_commit=C)
        if not self.m['environments']:
            self.m['environments']=[{'id':'native','platform':'macos','os_version':'synthetic','device':'validator-only','architecture':'arm64','flutter_version':'test','dart_version':'test','build_mode':'profile','bundle_id':'test.validator','capture_method':'synthetic unit fixture','capture_class':'app_desktop','is_native_app':True,'is_vm':False,'build_commit':C,'binary_sha256':'c'*64}]
        arts=[]
        for num in (1,2):
            path=f'evidence/{sid}/{cid}/after/{num}.png'
            f=self.root/path;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(png())
            arts.append({'id':cid+f'-img{num}','kind':'screenshot','path':path,'sha256':sha256_file(f),'environment_id':'native','implementation_commit':C,'captured_at':'2026-10-08T10:00:00+08:00','role':'after','modified':False,'pixel_size':[1,1],'viewport_logical':[1,1],'pixel_ratio':1,'font_scale':1,'theme':'light','locale':'zh-CN','window_state':'foreground','active_pane':'A','capture_scope':'full_app_window','description':'VALIDATOR TEST ONLY','shot_ids':[cid+f'-F0{num}']})
        for kind in ('log','video'):
            path=f'evidence/{sid}/{cid}/{kind}/proof.'+('txt' if kind=='log' else 'mp4')
            f=self.root/path;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b'validator test only; not terminal product evidence')
            arts.append({'id':cid+'-'+kind,'kind':kind,'path':path,'sha256':sha256_file(f),'environment_id':'native','implementation_commit':C,'captured_at':'2026-10-08T10:00:00+08:00','continuous':True,'modified':False})
        self.m['artifacts'].extend(arts)
        report=self.root/f'results/{sid}.md';report.parent.mkdir(exist_ok=True)
        report.write_text(f'# {sid}\n\n### {cid} · Synthetic\n\n'+''.join(f'![test](../{a["path"]})\n' for a in arts if a['kind']=='screenshot'))
        self.m['cases'][n-1].update(status='passed',implementation_commit=C,implementation_paths=['example/lib/test.dart'],actual_steps='synthetic validator test',observed_result='synthetic fixture only',artifact_ids=[a['id'] for a in arts],assertions=[{'name':'test','expected':'1','actual':'1','passed':True,'proof_artifact_id':cid+'-log'}],result_path=f'results/{sid}.md')
        return self.m['cases'][n-1], arts
    def fail(self,needle,gate='D1'):
        errors=validate(self.root,self.m,gate)
        self.assertTrue(any(needle in x for x in errors), f'{needle!r} missing from {errors}')
    def test_01_template_structure_is_not_product_certification(self):
        self.assertEqual(validate(self.root,self.m),[])
    def test_02_template_cannot_pass_gate(self): self.fail('not verified')
    def test_03_complete_stage_contract(self):
        self.passed();self.assertEqual(validate(self.root,self.m,'D1'),[])
    def test_04_complete_final_contract(self):
        for n in range(1,5):self.passed(n)
        self.assertEqual(validate(self.root,self.m,'final'),[])
    def test_05_missing_case(self):
        self.m['cases'].pop(); self.fail('coverage')
    def test_06_duplicate_case(self):
        self.m['cases'].append(copy.deepcopy(self.m['cases'][0]));self.fail('duplicate id')
    def test_07_unknown_stage(self):
        self.m['stages'][0]['id']='S1';self.fail('stage coverage')
    def test_08_invalid_case_status(self):
        self.m['cases'][0]['status']='done';self.fail('invalid case status')
    def test_09_requirement_mapping(self):
        self.m['cases'][0]['requirement_ids']=[];self.fail('requirement mapping')
    def test_10_missing_screenshot_file(self):
        c,a=self.passed();(self.root/a[0]['path']).unlink();self.fail('does not exist')
    def test_11_wrong_hash(self):
        c,a=self.passed();a[0]['sha256']='0'*64;self.fail('sha256 mismatch')
    def test_12_parent_path(self):
        c,a=self.passed();a[0]['path']='evidence/../../oops';self.fail('traversal')
    def test_13_absolute_path(self):
        c,a=self.passed();a[0]['path']='/tmp/no.png';self.fail('absolute paths')
    def test_14_design_path(self):
        c,a=self.passed();a[0]['path']='design/test.png';self.fail('under evidence')
    def test_15_symlink_outside_evidence(self):
        c,a=self.passed();f=self.root/a[0]['path'];f.unlink();g=self.root/'design.png';g.write_bytes(png());f.symlink_to(g);self.fail('symlink leaves evidence')
    def test_16_missing_log(self):
        c,a=self.passed();c['artifact_ids'].remove('D1-T01-log');self.fail('behavioral log')
    def test_17_missing_video(self):
        c,a=self.passed();c['artifact_ids'].remove('D1-T01-video');self.fail('continuous unmodified video')
    def test_18_cut_video(self):
        c,a=self.passed();a[-1]['continuous']=False;self.fail('continuous unmodified video')
    def test_19_timezone(self):
        c,a=self.passed();a[0]['captured_at']='2026-10-08T10:00:00';self.fail('timezone')
    def test_20_widget_not_native(self):
        self.passed();self.m['environments'][0]['capture_class']='widget_golden';self.fail('native macOS App')
    def test_21_not_native(self):
        self.passed();self.m['environments'][0]['is_native_app']=False;self.fail('native macOS App')
    def test_22_wrong_platform(self):
        self.passed();self.m['environments'][0]['platform']='linux';self.fail('native macOS App')
    def test_23_wrong_build(self):
        self.passed();self.m['environments'][0]['build_commit']=E;self.fail('build commit mismatch')
    def test_24_final_rejects_old_commit(self):
        for n in range(1,5):self.passed(n)
        self.m['implementation_commit']=E;self.fail('required implementation commit','final')
    def test_25_modified_screenshot(self):
        c,a=self.passed();a[0]['modified']=True;self.fail('must be unmodified')
    def test_26_missing_shot(self):
        c,a=self.passed();a[1]['shot_ids']=[];self.fail('incomplete screenshot')
    def test_27_duplicate_shot(self):
        c,a=self.passed();a[1]['shot_ids']=a[0]['shot_ids'][:];self.fail('duplicate canonical shot')
    def test_28_unknown_shot(self):
        c,a=self.passed();a[0]['shot_ids']=['S1-T01-F01'];self.fail('unknown shot')
    def test_29_multiple_shots_need_reason(self):
        c,a=self.passed();a[0]['shot_ids']+=a[1]['shot_ids'];self.fail('reuse_reason')
    def test_30_theme_mismatch(self):
        c,a=self.passed();a[0]['theme']='dark';self.fail('shot theme mismatch')
    def test_31_full_window_required(self):
        c,a=self.passed();a[0]['capture_scope']='detail';self.fail('full App window')
    def test_32_detail_anchor(self):
        c,a=self.passed();a[1]['capture_scope']='detail';self.fail('anchor')
    def test_33_valid_detail_anchor(self):
        c,a=self.passed();a[1]['capture_scope']='detail';a[1]['anchor_artifact_id']=a[0]['id'];self.assertEqual(validate(self.root,self.m,'D1'),[])
    def test_34_png_size(self):
        c,a=self.passed();a[0]['pixel_size']=[100,200];self.fail('dimensions mismatch')
    def test_35_invalid_png(self):
        c,a=self.passed();f=self.root/a[0]['path'];f.write_bytes(b'not png');a[0]['sha256']=sha256_file(f);self.fail('not a PNG')
    def test_36_nan_ratio(self):
        c,a=self.passed();a[0]['pixel_ratio']=float('nan');self.fail('invalid pixel_ratio')
    def test_37_assertion_proof(self):
        c,a=self.passed();c['assertions'][0]['proof_artifact_id']=a[0]['id'];self.fail('assertion proof')
    def test_38_unpassed_assertion(self):
        c,a=self.passed();c['assertions'][0]['passed']=False;self.fail('unpassed assertion')
    def test_39_no_embedded_image(self):
        c,a=self.passed();(self.root/c['result_path']).write_text('### D1-T01 · x\nNo images\n');self.fail('not embedded')
    def test_40_fenced_image_is_not_embed(self):
        c,a=self.passed();f=self.root/c['result_path'];s=f.read_text();s=s.replace('![test]','```markdown\n![test]',1)+'\n```\n';f.write_text(s);self.fail('not embedded')
    def test_41_report_heading(self):
        c,a=self.passed();f=self.root/c['result_path'];f.write_text(f.read_text().replace('### D1-T01','## D1-T01'));self.fail('level-3 heading')
    def test_42_blocked_reason(self):
        self.m['cases'][0]['status']='blocked';self.fail('needs reason')
    def test_43_unknown_gate(self): self.fail('unknown gate','S1')
    def test_44_all_actual_template_cases_not_run(self):
        root=Path(__file__).resolve().parents[1]
        if not (root/'templates/manifest.template.json').exists(): self.skipTest('standalone unit file')
        m=json.loads((root/'templates/manifest.template.json').read_text())
        self.assertEqual(len(m['cases']),64)
        self.assertTrue(all(c['status']=='not_run' for c in m['cases']))
        self.assertEqual(validate(root,m),[])
    def test_45_safe_path_rejects_url_and_backslash(self):
        for path in ('https://example.com/a','evidence\\a.png'):
            with self.assertRaises(ValueError):safe_path(self.root,path,True)
    def test_46_verified_stage_cannot_hide_failed_case(self):
        self.passed();self.m['cases'][0]['status']='failed';self.m['cases'][0]['reason']='test';self.fail('contains unpassed cases')

if __name__=='__main__': unittest.main()
