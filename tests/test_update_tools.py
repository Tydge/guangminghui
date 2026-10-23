"""Check cumulative pack delivery, immutable bootstrap, and native deletion semantics."""
from pathlib import Path
import argparse
import base64
import contextlib
import hashlib
import io
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from release_updates import contents, patch, write_pack
from release_updates import publish
from deploy_updates import release_files

GODOT = None


class PatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='illuminati-patch-')
        self.folder = Path(self.temporary.name)
        self.header = struct.pack('<6I2Q', 0x43504447, 3, 4, 6, 2, 2, 0, 0) + bytes(64)
        self.old = {'update-qa/changed.txt': b'old', 'update-qa/deleted.txt': b'remove',
                    'update-qa/untouched.bin': bytes(range(256)) * 100,
                    'data/update_channel.json': b'fixed public key'}
        self.new = dict(self.old)
        self.new['update-qa/changed.txt'] = b'new'
        self.new['update-qa/added.txt'] = b'added'
        del self.new['update-qa/deleted.txt']
        self.base = self.folder / 'base.pck'
        self.target = self.folder / 'target.pck'
        self.output = self.folder / 'update.pck'
        write_pack(self.header, self.old, self.base)
        write_pack(self.header, self.new, self.target)

    def tearDown(self):
        self.temporary.cleanup()

    def test_cumulative_changes_and_image_bytes(self):
        report = patch(self.base, self.target, self.output)
        self.assertEqual(set(report['changed']), {'update-qa/changed.txt', 'update-qa/added.txt'})
        self.assertEqual(report['removed'], ['update-qa/deleted.txt'])
        self.assertLess(report['bytes'], self.target.stat().st_size / 10)
        self.assertEqual(contents(self.target)[1]['update-qa/untouched.bin'], self.old['update-qa/untouched.bin'])
        # A second release still includes first-release changes when diffed from baseline.
        self.new['update-qa/another.txt'] = b'later'
        write_pack(self.header, self.new, self.target)
        report = patch(self.base, self.target, self.output)
        self.assertEqual(set(report['changed']), {'update-qa/changed.txt', 'update-qa/added.txt', 'update-qa/another.txt'})

    def test_bootstrap_requires_new_baseline(self):
        for name in ['project.binary', '.godot/global_script_class_cache.cfg',
                     'data/update_channel.json', 'scripts/update_bootstrap.gdc',
                     'scripts/update_bootstrap.gd.remap']:
            with self.subTest(path=name):
                candidate = dict(self.new)
                candidate[name] = b'changed bootstrap'
                write_pack(self.header, candidate, self.target)
                with self.assertRaisesRegex(ValueError, 'new complete base'):
                    patch(self.base, self.target, self.output)

    def patch_only_fixture(self):
        data=self.folder/'data';data.mkdir()
        release={'version':'0.3.3','code':2026102305,'base_id':'base','engine':'4.6.2','platform':'windows-x86_64'}
        channel={'origin':'https://127.0.0.1','product':'illuminati'}
        (data/'release.json').write_text(json.dumps(release));(data/'update_channel.json').write_text(json.dumps(channel))
        previous=dict(release,version='0.3.2',code=2026102304,product=channel['product'],full_version='0.3.1',full={'url':channel['origin']+'/releases/2026102303/Illuminati-Windows-x64.zip','bytes':1234,'sha256':'a'*64})
        manifest=self.folder/'previous.json';manifest.write_text(json.dumps({'payload':base64.b64encode(json.dumps(previous).encode()).decode(),'signature':'fixture'}))
        args=argparse.Namespace(zip=None,patch_only=True,pack=self.target,baseline=self.base,previous_manifest=manifest,output=self.folder/'site',key='fixture',openssl='fixture',notes_zh='修复',notes_en='Fix')
        return args,previous

    def test_patch_only_manifest_retains_complete_download(self):
        args,previous=self.patch_only_fixture()
        def signed(payload,*_args):return {'payload':base64.b64encode(json.dumps(payload).encode()).decode(),'signature':'fixture'}
        with mock.patch('release_updates.ROOT',self.folder),mock.patch('release_updates.sign_payload',side_effect=signed),contextlib.redirect_stdout(io.StringIO()):publish(args)
        manifest=json.loads((args.output/'windows/latest.json').read_text());payload=json.loads(base64.b64decode(manifest['payload']))
        self.assertEqual(payload['full'],previous['full'])
        self.assertEqual(payload['full_version'],'0.3.1')
        directory=args.output/'releases/2026102305'
        self.assertTrue((directory/'update.pck').is_file())
        self.assertFalse((directory/'Illuminati-Windows-x64.zip').exists())
        self.assertNotIn('Illuminati-Windows-x64.zip',(directory/'SHA256SUMS.txt').read_text())
        self.assertEqual([item['name'] for item in release_files(args.output,payload,True)],['update.pck'])

    def test_patch_only_requires_compatible_older_manifest_and_base(self):
        args,previous=self.patch_only_fixture()
        for field,value in [('baseline',None),('zip','unexpected.zip'),('previous_manifest',None)]:
            with self.subTest(field=field),mock.patch('release_updates.ROOT',self.folder):
                changed=argparse.Namespace(**vars(args));setattr(changed,field,value)
                with self.assertRaises(ValueError):publish(changed)
        previous['code']=2026102305
        args.previous_manifest.write_text(json.dumps({'payload':base64.b64encode(json.dumps(previous).encode()).decode()}))
        with mock.patch('release_updates.ROOT',self.folder),self.assertRaisesRegex(ValueError,'older compatible'):publish(args)

    def test_patch_only_upload_checks_content_without_complete_archive(self):
        directory=self.folder/'releases/5';directory.mkdir(parents=True);data=b'patch contents';(directory/'update.pck').write_bytes(data)
        payload={'code':5,'full':{},'patch':{'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}}
        self.assertEqual(release_files(self.folder,payload,True)[0]['route'],'patch')
        (directory/'update.pck').write_bytes(b'wrong contents')
        with self.assertRaises(ValueError):release_files(self.folder,payload,True)
        with self.assertRaisesRegex(ValueError,'requires a patch'):release_files(self.folder,{'code':5,'full':{}},True)

    def test_native_mount_changed_added_removed_and_unchanged(self):
        if not GODOT:
            self.skipTest('Pass --godot for native pack mount verification')
        patch(self.base, self.target, self.output)
        script = self.folder / 'verify.gd'
        paths = [self.base.as_posix(), self.output.as_posix()]
        script.write_text('''extends SceneTree
func _initialize():
 var base=ProjectSettings.load_resource_pack("%s")
 var before=FileAccess.file_exists("res://update-qa/deleted.txt")
 var mounted=ProjectSettings.load_resource_pack("%s")
 var valid=base and before and mounted
 valid=valid and FileAccess.get_file_as_string("res://update-qa/changed.txt")=="new"
 valid=valid and FileAccess.get_file_as_string("res://update-qa/added.txt")=="added"
 valid=valid and not FileAccess.file_exists("res://update-qa/deleted.txt")
 valid=valid and FileAccess.get_file_as_bytes("res://update-qa/untouched.bin").size()==25600
 if not valid:push_error("Native cumulative patch verification failed")
 quit(0 if valid else 1)
''' % tuple(paths), encoding='utf-8')
        result = subprocess.run([GODOT, '--headless', '--path', str(ROOT), '--script', str(script),
                                 '--', '--test-defaults'], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('ERROR:', result.stdout + result.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot')
    args, remaining = parser.parse_known_args()
    GODOT = args.godot
    unittest.main(argv=[sys.argv[0], *remaining])
