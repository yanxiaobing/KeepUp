"""Exercise the real shell flow with a fake xcodebuild; never signs or publishes."""
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
SOURCE = ROOT / '.agents/skills/app-archive/scripts/archive.sh'
STUB = r'''
import json, os, pathlib, plistlib, sys, zipfile
args = sys.argv[1:]
log = pathlib.Path(os.environ['ARCHIVE_TEST_CALLS'])
with log.open('a') as stream:
    stream.write(json.dumps(args) + '\n')
case = os.environ.get('ARCHIVE_TEST_CASE', '')
def value(name): return args[args.index(name) + 1]
def setting(name, default):
    return next((a.split('=', 1)[1] for a in args if a.startswith(name + '=')), default)
if args[0] == 'archive':
    if case == 'archive-fail': sys.exit(42)
    path = pathlib.Path(value('-archivePath'))
    path.mkdir(parents=True)
    props = dict(CFBundleIdentifier='com.bestlife.keepup',
                 CFBundleShortVersionString=setting('MARKETING_VERSION', '2.7.0'),
                 CFBundleVersion=setting('CURRENT_PROJECT_VERSION', '2026050101'))
    if case == 'archive-id': props['CFBundleIdentifier'] = 'wrong.app'
    (path / 'Info.plist').write_bytes(plistlib.dumps({'ApplicationProperties': props}))
elif args[0] == '-exportArchive':
    if case == 'export-fail': sys.exit(43)
    out = pathlib.Path(value('-exportPath')); out.mkdir(parents=True)
    props = plistlib.loads((pathlib.Path(value('-archivePath')) / 'Info.plist').read_bytes())['ApplicationProperties']
    if case == 'ipa-id': props['CFBundleIdentifier'] = 'wrong.ipa'
    if case == 'ipa-build': props['CFBundleVersion'] = '1'
    if case == 'zip-fail':
        (out / 'KeepUp.ipa').write_text('not a zip')
    else:
        with zipfile.ZipFile(out / 'KeepUp.ipa', 'w') as archive:
            archive.writestr('Payload/KeepUp.app/Info.plist', plistlib.dumps(props))
else: sys.exit(99)
'''


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / 'build/archive-skill-tests'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = Path(tempfile.mkdtemp(prefix='case with spaces ', dir=scratch))
        self.addCleanup(shutil.rmtree, self.temp)
        self.project = self.temp / 'project'
        workspace = self.project / 'KeepUp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm'
        workspace.mkdir(parents=True)
        (workspace / 'Package.resolved').write_text('{}')
        (self.project / 'KeepUp.xcodeproj/project.pbxproj').write_text('// fixture')
        skill = self.temp / 'skill'; (skill / 'scripts').mkdir(parents=True)
        config = (ROOT / '.agents/skills/app-archive/config.env').read_text()
        config = config.replace("PROJECT_ROOT='../../..'", f"PROJECT_ROOT='{self.project}'")
        (skill / 'config.env').write_text(config)
        self.calls = self.temp / 'calls.jsonl'
        self.stub = self.temp / 'fake-xcodebuild'
        self.stub.write_text(f'#!{sys.executable}\n' + STUB)
        self.stub.chmod(0o755)
        self.script = skill / 'scripts/archive.sh'
        # Substitute only the tool executable; all production parsing, pipes,
        # plist/ZIP checks, flags and output logic run unchanged.
        self.script.write_text(SOURCE.read_text().replace('/usr/bin/xcodebuild "', f'"{self.stub}" "'))
        self.script.chmod(0o755)

    def run_script(self, *args, case=''):
        env = dict(os.environ, ARCHIVE_TEST_CALLS=str(self.calls), ARCHIVE_TEST_CASE=case)
        return subprocess.run([str(self.script), *args], text=True, capture_output=True, env=env)

    def commands(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_export_with_versions_and_spaces(self):
        result = self.run_script('--marketing-version', '2.7.1', '--build-number', '2026090901',
                                 '--output-root', 'build/output with spaces')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        props = dict(line.split('=', 1) for line in result.stdout.splitlines() if line.startswith('APP_'))
        self.assertEqual(props['APP_VERSION'], '2.7.1')
        self.assertEqual(props['APP_BUILD'], '2026090901')
        self.assertTrue(Path(props['APP_IPA_PATH']).is_file())
        commands = self.commands()
        self.assertEqual([c[0] for c in commands], ['archive', '-exportArchive'])
        self.assertIn('-onlyUsePackageVersionsFromResolvedFile', commands[0])
        self.assertIn('-project', commands[0])
        self.assertNotIn('-workspace', commands[0])
        self.assertIn('-clonedSourcePackagesDirPath', commands[0])
        self.assertNotIn('-skipMacroValidation', commands[0])
        export = plistlib.loads((Path(props['APP_LOG_DIR']) / 'ExportOptions.plist').read_bytes())
        self.assertEqual(export['destination'], 'export')
        self.assertEqual(export['method'], 'release-testing')
        self.assertFalse(export['manageAppVersionAndBuildNumber'])

    def test_archive_only(self):
        result = self.run_script('--archive-only', '--skip-macro-validation')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.commands()), 1)
        self.assertIn('-skipMacroValidation', self.commands()[0])
        self.assertNotIn('APP_IPA_PATH=', result.stdout)

    def test_dry_run_has_no_build_or_output(self):
        result = self.run_script('--dry-run', '--output-root', 'build/no writes')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commands(), [])
        self.assertFalse((self.project / 'build').exists())

    def test_daily_sequence_and_preview(self):
        # Fix the build date without changing the production clock or signing.
        self.script.write_text(self.script.read_text().replace(
            'TZ=Asia/Shanghai /bin/date +%Y%m%d', 'print -r -- 20260909'))
        for suffix in ['01', '02']:
            preview = self.run_script('--dry-run')
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertIn('CURRENT_PROJECT_VERSION=20260909' + suffix, preview.stdout)
            result = self.run_script('--archive-only', '--output-root', 'build/alternate')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('APP_BUILD=20260909' + suffix, result.stdout)
        self.assertIn('CURRENT_PROJECT_VERSION=2026090903', self.run_script('--dry-run').stdout)

    def test_existing_archive_and_daily_limit(self):
        self.script.write_text(self.script.read_text().replace(
            'TZ=Asia/Shanghai /bin/date +%Y%m%d', 'print -r -- 20260909'))
        archive = self.project / 'build/releases/old/Keep.xcarchive'
        archive.mkdir(parents=True)
        info = archive / 'Info.plist'
        info.write_bytes(plistlib.dumps({'ApplicationProperties': {'CFBundleVersion': '2026090908'}}))
        self.assertIn('CURRENT_PROJECT_VERSION=2026090909', self.run_script('--dry-run').stdout)
        info.write_bytes(plistlib.dumps({'ApplicationProperties': {'CFBundleVersion': '2026090999'}}))
        result = self.run_script('--archive-only')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exhausted', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_existing_archive_refused(self):
        archive = self.project / 'keep.xcarchive'; archive.mkdir()
        marker = archive / 'keep'; marker.write_text('original')
        result = self.run_script('--archive-path', str(archive))
        self.assertEqual(result.returncode, 73)
        self.assertEqual(marker.read_text(), 'original')
        self.assertEqual(self.commands(), [])

    def test_missing_argument(self):
        result = self.run_script('--build-number')
        self.assertEqual(result.returncode, 64)
        self.assertIn('requires a value', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_archive_failures_stop_before_export(self):
        for case in ['archive-fail', 'archive-id']:
            with self.subTest(case=case):
                self.calls.unlink(missing_ok=True)
                result = self.run_script(case=case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.commands()), 1)
                self.assertNotIn('APP_IPA_PATH=', result.stdout)
                if case == 'archive-fail':
                    self.assertEqual(result.returncode, 42)
                else:
                    self.assertIn('Archive bundle identifier mismatch', result.stderr)

    def test_export_and_ipa_failures(self):
        for case in ['export-fail', 'zip-fail', 'ipa-id', 'ipa-build']:
            with self.subTest(case=case):
                self.calls.unlink(missing_ok=True)
                result = self.run_script(case=case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.commands()), 2)
                self.assertNotIn('APP_IPA_PATH=', result.stdout)
                if case == 'export-fail':
                    self.assertEqual(result.returncode, 43)
                elif case == 'ipa-id':
                    self.assertIn('IPA bundle identifier mismatch', result.stderr)
                elif case == 'ipa-build':
                    self.assertIn('IPA build mismatch', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
