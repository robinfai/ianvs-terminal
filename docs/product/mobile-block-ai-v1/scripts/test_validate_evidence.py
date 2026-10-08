"""Unit tests for the evidence validator, NOT tests of the terminal product.
Synthetic files exist only inside TemporaryDirectory and are not app evidence.
"""
from __future__ import annotations
import copy
import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path
from validate_evidence import validate, safe_file

ROOT=Path(__file__).resolve().parents[1]

class EvidenceValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.root=Path(self.temp.name)
        self.plan=json.loads((ROOT/'plan.json').read_text())
        self.manifest=json.loads((ROOT/'templates/manifest.template.json').read_text())
    def tearDown(self):
        self.temp.cleanup()
    def proof(self):
        m=self.manifest
        sha='a'*40
        m['implementation_commit']=sha
        m['environments']=[{'id':'synthetic-unit-environment','platform':'ios','capture_class':'app_simulator','device_model':'UNIT TEST ONLY','os_version':'test','flutter_version':'test','build_mode':'debug','build_id':'synthetic','build_commit':sha,'binary_sha256':'b'*64,'is_physical':False}]
        directory=self.root/'evidence/S1/S1-T01/unit-only'
        directory.mkdir(parents=True)
        # Only a PNG header is needed to test metadata parsing. This is not a real
        # screenshot; the validator intentionally cannot certify visual truth.
        image=directory/'synthetic-header.png'
        image.write_bytes(b'\x89PNG\r\n\x1a\n'+b'\0\0\0\rIHDR'+struct.pack('>II',1,1))
        log=directory/'synthetic.log';log.write_text('UNIT TEST ONLY: synthetic parser fixture\n')
        common={'implementation_commit':sha,'captured_at':'2026-10-08T00:00:00Z'}
        capture={**common,'kind':'screenshot','path':image.relative_to(self.root).as_posix(),'sha256':hashlib.sha256(image.read_bytes()).hexdigest(),'environment_id':'synthetic-unit-environment','role':'after','modified':False,'pixel_size':[1,1],'viewport_logical':[1,1],'pixel_ratio':1,'orientation':'portrait','locale':'zh-CN','theme':'light','font_policy':'phone_fixed','keyboard':'hidden','description':'UNIT TEST ONLY; not product evidence'}
        proof={**common,'kind':'log','path':log.relative_to(self.root).as_posix(),'sha256':hashlib.sha256(log.read_bytes()).hexdigest()}
        case=m['cases'][0]
        case.update(status='passed',steps=['synthetic validation test'],observed_result='synthetic test',artifacts=[capture,proof],assertions=[{'name':'synthetic assertion','expected':'test','actual':'test','passed':True,'proof_path':proof['path']}])
        return case
    def test_untouched_template_structure_valid(self):
        self.assertEqual(validate(self.manifest,self.plan,self.root)[0],[])
    def test_template_cannot_pass_final_gate(self):
        self.assertTrue(validate(self.manifest,self.plan,self.root,'S4')[0])
    def test_passed_case_format_valid_not_visual_certification(self):
        self.proof();self.assertEqual(validate(self.manifest,self.plan,self.root)[0],[])
    def test_missing_case_rejected(self):
        self.manifest['cases'].pop();self.assertTrue(validate(self.manifest,self.plan,self.root)[0])
    def test_duplicate_case_rejected(self):
        self.manifest['cases'].append(copy.deepcopy(self.manifest['cases'][0]))
        self.assertTrue(validate(self.manifest,self.plan,self.root)[0])
    def test_file_tampering_rejected(self):
        case=self.proof();path=self.root/case['artifacts'][1]['path'];path.write_text('changed')
        self.assertTrue(any('SHA-256' in e for e in validate(self.manifest,self.plan,self.root)[0]))
    def test_desktop_not_phone_capture(self):
        self.proof();self.manifest['environments'][0].update(platform='macos',capture_class='app_desktop')
        self.assertTrue(any('no qualified screenshot' in e for e in validate(self.manifest,self.plan,self.root)[0]))
    def test_edited_image_rejected(self):
        self.proof()['artifacts'][0]['modified']=True
        self.assertTrue(any('unmodified' in e for e in validate(self.manifest,self.plan,self.root)[0]))
    def test_design_cannot_count_as_evidence(self):
        case=self.proof();src=self.root/case['artifacts'][0]['path'];dst=self.root/'design/mock.png';dst.parent.mkdir();dst.write_bytes(src.read_bytes());case['artifacts'][0]['path']='design/mock.png'
        self.assertTrue(any('cannot count' in e for e in validate(self.manifest,self.plan,self.root)[0]))
    def test_old_commit_rejected(self):
        self.proof()['artifacts'][0]['implementation_commit']='c'*40
        self.assertTrue(any('not from final' in e for e in validate(self.manifest,self.plan,self.root)[0]))
    def test_physical_claim_requires_metadata(self):
        self.proof();self.manifest['environments'][0].update(capture_class='app_physical',is_physical=False)
        self.assertTrue(any('actual iPhone' in e for e in validate(self.manifest,self.plan,self.root)[0]))
    def test_path_escape_rejected(self):
        with self.assertRaises(ValueError):safe_file(self.root,'../outside.png')

if __name__=='__main__': unittest.main()
