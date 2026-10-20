"""Synthetic parser tests ONLY. No screenshots are product acceptance evidence."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from validate_shotlist import validate_shots

ROOT=Path(__file__).resolve().parents[1]

class ShotlistTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.m=json.loads((ROOT/'templates/manifest.template.json').read_text())
        self.p=json.loads((ROOT/'shotlist.json').read_text())
    def tearDown(self):self.tmp.cleanup()
    def sample(self):
        case=self.m['cases'][0];case['status']='passed'
        self.m['environments']=[{'id':'unit-only','platform':'ios','capture_class':'app_simulator','is_physical':False}]
        directory=self.root/'evidence/S1/S1-T01/unit-only';directory.mkdir(parents=True)
        artifacts=[]
        for shot in [s for s in self.p['shots'] if s['case_id']=='S1-T01']:
            path=directory/shot['file_name'];path.write_bytes(b'SYNTHETIC PARSER TEST; NOT AN IMAGE')
            artifacts.append({'kind':'screenshot','path':path.relative_to(self.root).as_posix(),'environment_id':'unit-only','role':'after','modified':False,'shot_ids':[shot['id']]})
        case['artifacts']=artifacts
        (self.root/'results').mkdir()
        (self.root/'results/S1.md').write_text('### S1-T01 · Unit parser fixture\n'+''.join(f"![unit test](../{a['path']})\n" for a in artifacts))
        return case
    def test_unrun_template_valid_structure(self):self.assertEqual(validate_shots(self.m,self.p,self.root),[])
    def test_unrun_template_fails_gate(self):self.assertTrue(validate_shots(self.m,self.p,self.root,'S4',True))
    def test_declared_coverage_and_embeddings(self):self.sample();self.assertEqual(validate_shots(self.m,self.p,self.root,check_reports=True),[])
    def test_missing_checkpoint(self):self.sample()['artifacts'].pop();self.assertTrue(any('missing checkpoints' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_crosscase_id(self):self.sample()['artifacts'][0]['shot_ids']=['S1-T02-F01'];self.assertTrue(any('cross-case' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_report_omits_image(self):self.sample();(self.root/'results/S1.md').write_text('### S1-T01 · Unit\nNo image\n');self.assertTrue(any('not embedded' in e for e in validate_shots(self.m,self.p,self.root,check_reports=True)))
    def test_desktop_cannot_be_phone(self):self.sample();self.m['environments'][0].update(platform='macos',capture_class='app_desktop');self.assertTrue(any('incompatible' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_theme_requirement(self):self.sample();self.p['shots'][0]['theme']='dark';self.m['cases'][0]['artifacts'][0]['theme']='light';self.assertTrue(any('theme=dark' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_modified_capture(self):self.sample()['artifacts'][0]['modified']=True;self.assertTrue(any('unmodified' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_multiple_checkpoint_reuse_needs_reason(self):c=self.sample();c['artifacts'][0]['shot_ids']+=c['artifacts'][1]['shot_ids'];c['artifacts'].pop();self.assertTrue(any('reuse_reason' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_path_escape(self):self.sample()['artifacts'][0]['path']='../outside.png';self.assertTrue(any('parent paths' in e for e in validate_shots(self.m,self.p,self.root)))
    def test_duplicate_case_rejected(self):self.m['cases'].append(copy.deepcopy(self.m['cases'][0]));self.assertTrue(any('case coverage' in e for e in validate_shots(self.m,self.p,self.root)))

if __name__=='__main__':unittest.main()
