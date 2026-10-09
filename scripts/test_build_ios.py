"""Exercise release versioning and failure recovery with isolated fake build tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


FAKE_TOOL = r'''
import datetime, os, pathlib, plistlib, re, sys
name = pathlib.Path(sys.argv[0]).name
root = pathlib.Path.cwd()
mode = os.environ.get('PATROL_TEST_MODE', '')
if name == 'git':
    print('abc1234')
elif name == 'flutter':
    assert sys.argv[1] == '--device-id'
    assert sys.argv[3:6] == ['build', 'ios', '--release']
    device = sys.argv[2]
    pubspec = (root / 'pubspec.yaml').read_text()
    version, number = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)', pubspec, re.M).groups()
    assert '--dart-define=VERSION_NAME=' + version in sys.argv
    app = root / 'build/ios/iphoneos/Runner.app'
    app.mkdir(parents=True)
    (app / 'new-build').write_text(version)
    if mode == 'build_failure':
        sys.exit(9)
    if mode == 'concurrent_edit':
        (root / 'pubspec.yaml').write_text(pubspec + '# user edit\n')
    (app / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleShortVersionString': '0.0.0' if mode == 'wrong_version' else version,
        'CFBundleVersion': number, 'CFBundleIdentifier': 'com.example.gongdiApp',
    }))
    (app / 'embedded.mobileprovision').write_bytes(plistlib.dumps({
        'UUID': 'test-profile', 'TeamIdentifier': ['TESTTEAM01'],
        'ProvisionedDevices': ['other-phone'] if mode == 'wrong_device' else [device],
        'ExpirationDate': datetime.datetime.utcnow() + datetime.timedelta(days=-1 if mode == 'expired' else 7),
    }))
elif name == 'security':
    sys.stdout.buffer.write(pathlib.Path(sys.argv[-1]).read_bytes())
elif name == 'codesign':
    sys.exit(1 if mode == 'bad_signature' else 0)
elif name == 'xcrun':
    (root / 'install-called').write_text(' '.join(sys.argv[1:]))
    sys.exit(7 if mode == 'install_failure' else 0)
elif name == 'open':
    (root / 'finder-called').write_text(sys.argv[-1])
'''


class BuildIOSWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='patrol build test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy2(Path(__file__).with_name('build_ios.sh'), self.root / 'scripts/build_ios.sh')
        self.original = b'name: fixture\r\nversion: 1.1.0+173 # retained comment\r\n'
        (self.root / 'pubspec.yaml').write_bytes(self.original)
        self.app = self.root / 'build/ios/iphoneos/Runner.app'
        self.app.mkdir(parents=True)
        (self.app / 'old-build').write_text('1.1.0')
        (self.root / 'build/ios/BUILD_INFO.txt').write_text('old metadata')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ['flutter', 'codesign', 'security', 'git', 'xcrun', 'open']:
            tool = self.bin / name
            tool.write_text(f'#!{sys.executable}\n' + FAKE_TOOL)
            tool.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        PATROL_IOS_ENV_FILE='/dev/null', PATROL_IOS_DEVICE='test-iphone',
                        PATROL_IOS_TEAM='')

    def run_build(self, mode='', *args):
        result = subprocess.run(['/bin/bash', str(self.root / 'scripts/build_ios.sh'), *args],
                                cwd=self.root, env=dict(self.env, PATROL_TEST_MODE=mode),
                                capture_output=True, text=True, timeout=30)
        self.assertFalse((self.root / '.dart_tool/site-patrol-ios-build.lock').exists())
        return result

    def assert_rolled_back(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'pubspec.yaml').read_bytes(), self.original)
        self.assertTrue((self.app / 'old-build').exists())
        self.assertFalse((self.app / 'new-build').exists())
        self.assertEqual((self.root / 'build/ios/BUILD_INFO.txt').read_text(), 'old metadata')
        self.assertFalse((self.root / 'install-called').exists())

    def test_new_release_and_next_release(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(b'1.1.1+174 # retained comment\r\n', (self.root / 'pubspec.yaml').read_bytes())
        self.assertTrue((self.root / 'finder-called').exists())
        self.assertFalse((self.root / 'install-called').exists())
        self.assertEqual(list(self.root.rglob('*.ipa')), [])
        result = self.run_build('', '--no-open')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = json.loads((self.root / 'build/ios/BUILD_INFO.json').read_text())
        self.assertEqual((data['version'], data['build_number']), ('1.1.2', '175'))

    def test_keep_version_for_another_device(self):
        result = self.run_build('', '--keep-version', '--device', 'another-iphone', '--no-open')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / 'pubspec.yaml').read_bytes(), self.original)
        data = json.loads((self.root / 'build/ios/BUILD_INFO.json').read_text())
        self.assertEqual(data['target_device'], 'another-iphone')
        self.assertFalse((self.root / 'finder-called').exists())

    def test_build_failure_restores_previous_app_and_version(self):
        self.assert_rolled_back(self.run_build('build_failure'))

    def test_verification_failures_restore_previous_app_and_version(self):
        for mode in ['bad_signature', 'wrong_device', 'expired', 'wrong_version']:
            with self.subTest(mode=mode):
                self.assert_rolled_back(self.run_build(mode))

    def test_concurrent_user_edit_is_preserved(self):
        result = self.run_build('concurrent_edit')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('# user edit', (self.root / 'pubspec.yaml').read_text())
        self.assertTrue((self.app / 'old-build').exists())

    def test_install_failure_retains_successful_build(self):
        result = self.run_build('install_failure', '--install', '--no-open')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('1.1.1+174', (self.root / 'pubspec.yaml').read_text())
        self.assertTrue((self.app / 'new-build').exists())
        self.assertTrue((self.root / 'install-called').exists())

    def test_missing_device_argument_does_not_change_version(self):
        result = self.run_build('', '--device')
        self.assert_rolled_back(result)

    def test_existing_lock_is_not_removed(self):
        lock = self.root / '.dart_tool/site-patrol-ios-build.lock'
        lock.mkdir(parents=True)
        result = subprocess.run(['/bin/bash', str(self.root / 'scripts/build_ios.sh')],
                                cwd=self.root, env=self.env, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.exists())
        self.assertEqual((self.root / 'pubspec.yaml').read_bytes(), self.original)


if __name__ == '__main__':
    unittest.main()
