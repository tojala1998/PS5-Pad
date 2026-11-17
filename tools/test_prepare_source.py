"""Release safety checks using copies of the already verified public IPA."""
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
import unittest
from prepare_source import ROOT, stage

class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp=TemporaryDirectory();self.root=Path(self.temp.name)
        self.ipa=ROOT/'releases/0.4.9/PS5-Pad-0.4.9-unsigned.ipa'
        self.report=ROOT/'releases/0.4.9/PS5-Pad-0.4.9-verification.json'
        (self.root/'docs').mkdir()
        shutil.copy2(ROOT/'docs/PS5-Pad-0.4.9-notes.txt',self.root/'docs')
    def tearDown(self):self.temp.cleanup()
    def test_idempotent_and_retains_release_date(self):
        stage(self.root,self.ipa,self.report,'2026-11-16')
        before=(self.root/'source.json').read_bytes()
        self.assertEqual(json.loads(before)["apps"][0]["versions"][0]["buildVersion"],"15")
        stage(self.root,self.ipa,self.report,'2026-11-17')
        self.assertEqual(before,(self.root/'source.json').read_bytes())
        stage(self.root,self.ipa,self.report,check=True)
    def test_rejects_corrupt_download_before_writing_source(self):
        bad=self.root/'bad.ipa';bad.write_bytes(self.ipa.read_bytes()+b'x')
        with self.assertRaisesRegex(ValueError,'verification report'):stage(self.root,bad,self.report)
        self.assertFalse((self.root/'source.json').exists())
    def test_does_not_replace_existing_version_or_source_identity(self):
        stage(self.root,self.ipa,self.report,'2026-11-16')
        staged=self.root/'releases/0.4.9'/self.ipa.name;staged.write_bytes(b'existing different bytes')
        with self.assertRaisesRegex(ValueError,'different bytes'):stage(self.root,self.ipa,self.report)
        self.assertEqual(staged.read_bytes(),b'existing different bytes')
        source=self.root/'source.json';s=json.loads(source.read_text());s['identifier']='different';source.write_text(json.dumps(s))
        with self.assertRaisesRegex(ValueError,'identity changed'):stage(self.root,self.ipa,self.report)
    def test_refuses_rollback(self):
        stage(self.root,self.ipa,self.report,'2026-11-16')
        source=self.root/'source.json';s=json.loads(source.read_text());s['apps'][0]['versions'][0]['version']='0.5.0';source.write_text(json.dumps(s))
        with self.assertRaisesRegex(ValueError,'older version'):stage(self.root,self.ipa,self.report)
if __name__=='__main__':unittest.main()
