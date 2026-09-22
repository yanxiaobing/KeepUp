"""Offline publication flow tests. Fake endpoints/tools; no uploads or notifications."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIR_STUB = r'''
require 'json'
File.open(ENV.fetch('PUBLISH_TEST_CALLS'), 'a') { |f| f.puts(JSON.generate(ARGV)) }
mode = ENV['PUBLISH_TEST_CASE']
if ARGV[0] == 'info'
  puts 'display_name: Keep打卡'
  puts "identifier: #{mode == 'wrong-id' ? 'wrong.bundle' : 'com.bestlife.keepup'}"
  puts 'version: 2.7.0'
  puts 'build: 2026090901'
elsif ARGV[0] == 'publish'
  raise 'missing release flag' unless ARGV.include?('--need-release-id')
  puts ENV['API_TOKEN'] # Deliberately noisy upstream output must stay private.
  exit 42 if mode == 'fir-fail'
  puts(mode == 'no-url' ? 'no confirmed result' : 'Published succeed: https://example.test/punch?release_id=abc123')
else
  exit 99
end
'''
CURL_STUB = r'''
import json, os, pathlib, sys
args=sys.argv[1:]
entry={'args':args,'config':sys.stdin.read()}
with open(os.environ['PUBLISH_TEST_CURL'],'a') as f: f.write(json.dumps(entry)+'\n')
mode=os.environ.get('PUBLISH_TEST_CASE','')
if mode=='curl-fail': sys.exit(28)
print('{}' if mode=='missing-code' else '{"code":1}' if mode=='rejected' else '{"code":0}')
'''
XCODE_STUB = r'''
import json, os, plistlib, sys
args=sys.argv[1:]
p=args[args.index('-exportOptionsPlist')+1]
with open(os.environ['PUBLISH_TEST_CALLS'],'a') as f:
 f.write(json.dumps({'args':args,'options':plistlib.load(open(p,'rb'))})+'\n')
sys.exit(43 if os.environ.get('PUBLISH_TEST_CASE')=='store-fail' else 0)
'''


class PublishTests(unittest.TestCase):
    def setUp(self):
        scratch=ROOT/'build/publish-skill-tests'; scratch.mkdir(parents=True,exist_ok=True)
        self.temp=Path(tempfile.mkdtemp(prefix='case with spaces ',dir=scratch))
        self.addCleanup(shutil.rmtree,self.temp)
        self.root=self.temp/'project'; self.root.mkdir()
        self.calls=self.temp/'calls.jsonl'; self.curls=self.temp/'curl.jsonl'
        self.fir=self.temp/'fir'; self.fir.write_text('#!/usr/bin/env ruby\n'+FIR_STUB); self.fir.chmod(0o755)
        self.curl=self.temp/'curl'; self.curl.write_text(f'#!{sys.executable}\n'+CURL_STUB); self.curl.chmod(0o755)
        self.xcode=self.temp/'xcode'; self.xcode.write_text(f'#!{sys.executable}\n'+XCODE_STUB); self.xcode.chmod(0o755)
        self.scripts={}
        for name in ['fir-publish','store-publish']:
            skill=self.temp/name
            shutil.copytree(ROOT/'.agents/skills'/name,skill,ignore=shutil.ignore_patterns('credentials.env'))
            config=(skill/'config.env').read_text().replace("PROJECT_ROOT='../../..'",f"PROJECT_ROOT='{self.root}'")
            config=config.replace("FIR_BIN='fir'",f"FIR_BIN='{self.fir}'")
            (skill/'config.env').write_text(config)
            script=skill/'scripts/publish.sh'
            script.write_text(script.read_text().replace('/usr/bin/curl ',f'"{self.curl}" ').replace('/usr/bin/xcodebuild ',f'"{self.xcode}" '))
            self.scripts[name]=script
        self.credentials=self.temp/'fir-publish/credentials.env'
        self.credentials.write_text("FIR_API_TOKEN='fixture-secret'\nFIR_LARK_WEBHOOK_URL='https://open.larksuite.com/open-apis/bot/v2/hook/fixture-webhook'\n")
        self.ipa=self.root/'Keep Test.ipa'; self.ipa.write_text('stub parser fixture')
        self.archive=self.root/'Keep Test.xcarchive'; self.archive.mkdir()
        self.info=dict(CFBundleIdentifier='com.bestlife.keepup',CFBundleShortVersionString='2.7.0',CFBundleVersion='2026090901')
        self.write_info()

    def write_info(self):
        (self.archive/'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties':self.info}))

    def run_tool(self,name,*args,case=''):
        env=dict(os.environ,PUBLISH_TEST_CALLS=str(self.calls),PUBLISH_TEST_CURL=str(self.curls),PUBLISH_TEST_CASE=case)
        r=subprocess.run([str(self.scripts[name]),*args],capture_output=True,text=True,env=env)
        self.assertNotIn('fixture-secret',r.stdout+r.stderr)
        self.assertNotIn('fixture-webhook',r.stdout+r.stderr)
        return r

    def read_calls(self,path=None):
        p=path or self.calls
        return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []

    def fir_run(self,*args,case=''):
        return self.run_tool('fir-publish','--artifact',str(self.ipa),*args,case=case)

    def test_fir_upload_then_notify(self):
        r=self.fir_run('--changelog','修复轨迹\n\n优化分享')
        self.assertEqual(r.returncode,0,r.stderr+r.stdout)
        self.assertEqual([v[0] for v in self.read_calls()],['info','publish'])
        self.assertIn('FIR_UPLOAD_SUCCEEDED=true',r.stdout)
        self.assertIn('LARK_NOTIFICATION_SUCCEEDED=true',r.stdout)
        req=self.read_calls(self.curls)[0]
        self.assertIn('https://open.larksuite.com/',req['config'])
        self.assertNotIn('fixture-webhook',' '.join(req['args']))
        payload=json.loads(req['args'][req['args'].index('--data-binary')+1])
        self.assertIn('1. 修复轨迹\n2. 优化分享',payload['content']['text'])
        self.assertIn('?release_id=abc123',payload['content']['text'])

    def test_fir_inspect_without_credentials(self):
        self.credentials.unlink()
        r=self.fir_run('--inspect-only')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual([v[0] for v in self.read_calls()],['info'])
        self.assertFalse((self.root/'build').exists()); self.assertFalse(self.curls.exists())

    def test_wrong_bundle_prevents_upload(self):
        r=self.fir_run('--no-changelog',case='wrong-id')
        self.assertNotEqual(r.returncode,0)
        self.assertEqual([v[0] for v in self.read_calls()],['info'])
        self.assertFalse(self.curls.exists())

    def test_uncertain_upload_never_notifies_or_retries(self):
        for mode in ['fir-fail','no-url']:
            with self.subTest(mode=mode):
                self.calls.unlink(missing_ok=True)
                r=self.fir_run('--no-changelog',case=mode)
                self.assertNotEqual(r.returncode,0)
                self.assertEqual([v[0] for v in self.read_calls()],['info','publish'])
                self.assertFalse(self.curls.exists())
                self.assertNotIn('FIR_UPLOAD_SUCCEEDED=true',r.stdout)

    def test_notify_failure_keeps_upload_result_and_notify_only_does_not_reupload(self):
        r=self.fir_run('--no-changelog',case='rejected')
        self.assertEqual(r.returncode,75)
        self.assertIn('FIR_UPLOAD_SUCCEEDED=true',r.stdout)
        self.assertIn('PACKAGE_URL=https://example.test/punch?release_id=abc123',r.stdout)
        r=self.fir_run('--no-changelog','--notify-only','--package-url','https://example.test/punch?release_id=abc123')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual([v[0] for v in self.read_calls()].count('publish'),1)
        self.assertIn('LARK_NOTIFICATION_SUCCEEDED=true',r.stdout)
        self.assertNotIn('FIR_UPLOAD_SUCCEEDED=true',r.stdout)

    def test_missing_code_and_transport_failure_not_success(self):
        for mode in ['missing-code','curl-fail']:
            with self.subTest(mode=mode):
                r=self.fir_run('--no-changelog',case=mode)
                self.assertEqual(r.returncode,75)
                self.assertNotIn('LARK_NOTIFICATION_SUCCEEDED=true',r.stdout)

    def test_store_inspection(self):
        r=self.run_tool('store-publish','--archive',str(self.archive),'--inspect-only')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.read_calls(),[])
        self.assertFalse((self.root/'build').exists())

    def test_store_upload_options_and_failed_exit(self):
        r=self.run_tool('store-publish','--archive',str(self.archive))
        self.assertEqual(r.returncode,0,r.stderr)
        req=self.read_calls()[0]
        self.assertEqual(req['args'][0],'-exportArchive')
        self.assertEqual(req['options']['destination'],'upload')
        self.assertEqual(req['options']['method'],'app-store-connect')
        self.assertFalse(req['options']['manageAppVersionAndBuildNumber'])
        self.assertIn('STORE_UPLOAD_SUCCEEDED=true',r.stdout)
        r=self.run_tool('store-publish','--archive',str(self.archive),case='store-fail')
        self.assertEqual(r.returncode,43)
        self.assertNotIn('STORE_UPLOAD_SUCCEEDED=true',r.stdout)
        self.assertEqual(len(self.read_calls()),2)

    def test_store_rejects_wrong_bundle(self):
        self.info['CFBundleIdentifier']='wrong.bundle';self.write_info()
        r=self.run_tool('store-publish','--archive',str(self.archive))
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.read_calls(),[])


if __name__=='__main__':
    unittest.main(verbosity=2)
