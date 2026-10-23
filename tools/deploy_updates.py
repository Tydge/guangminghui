"""Upload a signed release over HTTPS, verify on host, then publish atomically.

SSH authorizes a temporary, unlisted PUT-only upload route. It is removed after
upload; player downloads remain public and require no login. No keys enter Git.
"""
from pathlib import Path
import argparse, base64, hashlib, http.client, ipaddress, json, secrets, ssl, subprocess, time


def remote(args, code, data=None):
    script='import json\ncfg=json.loads('+repr(json.dumps(data or {}))+')\n'+code
    return subprocess.run(['ssh','-i',str(Path(args.key).resolve()),'-o','BatchMode=yes','-o','IdentitiesOnly=yes',args.user+'@'+args.host,'python3 -'],input=script,text=True,check=True)


def release_files(site,payload,patch_only=False):
    directory=site/'releases'/str(payload['code']);files=[]
    if not patch_only:
        files.append({'name':'Illuminati-Windows-x64.zip','sha256':payload['full']['sha256'],'bytes':payload['full']['bytes'],'route':'full'})
    elif 'patch' not in payload:raise ValueError('Patch-only deployment requires a patch in the signed manifest.')
    if 'patch' in payload:files.append({'name':'update.pck','sha256':payload['patch']['sha256'],'bytes':payload['patch']['bytes'],'route':'patch'})
    for item in files:
        path=directory/item['name']
        with path.open('rb') as stream:
            if path.stat().st_size!=item['bytes'] or hashlib.file_digest(stream,'sha256').hexdigest()!=item['sha256']:raise ValueError('Local file hash/size mismatch: '+item['name'])
    return files


def deploy(args):
    ipaddress.ip_address(args.host)
    site=Path(args.site).resolve();manifest=(site/'windows/latest.json').read_text(encoding='utf-8')
    payload=json.loads(base64.b64decode(json.loads(manifest)['payload']))
    code=int(payload['code']);expected=payload['full']['sha256']
    directory=site/'releases'/str(code)
    patch_only=getattr(args,'patch_only',False);files=release_files(site,payload,patch_only)
    token=secrets.token_hex(24)
    data={'token':token,'code':code,'sha256':expected,'manifest':manifest,'files':files,'patch_only':patch_only,'full':payload['full'],'host':args.host}
    remote(args,r'''
from pathlib import Path
import base64,json,hashlib
from urllib.parse import urlsplit
root=Path('/srv/illuminati/www')
previous=root/'windows/latest.json'
if previous.exists():
 old=json.loads(base64.b64decode(json.loads(previous.read_text())['payload']))
 if int(old['code'])>cfg['code']:raise RuntimeError('Refusing to publish an older release.')
existing=root/'releases'/str(cfg['code'])/'manifest.json'
if existing.exists() and json.loads(existing.read_text())!=json.loads(cfg['manifest']):
 raise RuntimeError('Published release codes are immutable; increment code before publishing changes.')
if cfg['patch_only']:
 url=urlsplit(cfg['full']['url']);target=(root/url.path.lstrip('/')).resolve()
 if url.scheme!='https' or url.hostname!=cfg['host'] or not target.is_relative_to((root/'releases').resolve()) or not target.is_file():
  raise RuntimeError('Retained complete download is not an existing release on this host.')
 with target.open('rb') as stream:actual=hashlib.file_digest(stream,'sha256').hexdigest()
 if actual!=cfg['full']['sha256'] or target.stat().st_size!=cfg['full']['bytes'] or (root/'Illuminati-Windows.zip').resolve()!=target:
  raise RuntimeError('Retained complete download or stable link does not match the signed manifest.')
print('Release version preflight passed.')
''',data)
    remote(args,r'''
from pathlib import Path
import os,subprocess
incoming=Path('/srv/illuminati/incoming');incoming.mkdir(exist_ok=True)
os.chown(incoming,33,33);os.chmod(incoming,0o700)
conf=Path('/etc/nginx/sites-available/illuminati-updates')
text=conf.read_text();needle='    location = /health'
if 'include /etc/nginx/illuminati-upload.inc;' not in text:
 text=text.replace(needle,'    include /etc/nginx/illuminati-upload.inc;\n'+needle)
 conf.write_text(text)
routes=[]
for item in cfg['files']:
 routes.append('location = /deploy-'+cfg['token']+'-'+item['route']+' { alias /srv/illuminati/incoming/'+item['name']+'; dav_methods PUT; client_max_body_size 1024m; client_body_timeout 120s; access_log off; limit_except PUT { deny all; } }\n')
Path('/etc/nginx/illuminati-upload.inc').write_text(''.join(routes))
subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
print('Temporary HTTPS upload route enabled.')
''',data)
    try:
        for item in files:
            connection=http.client.HTTPSConnection(args.host,context=ssl.create_default_context(),timeout=120)
            connection.putrequest('PUT','/deploy-'+token+'-'+item['route'])
            connection.putheader('Content-Length',str(item['bytes']));connection.endheaders()
            started=time.monotonic();sent=0;last=0
            with (directory/item['name']).open('rb') as stream:
                while block:=stream.read(1024*1024):
                    connection.send(block);sent+=len(block)
                    if sent-last>=16*1024*1024:
                        print(f'Uploaded {sent/1048576:.0f}/{item["bytes"]/1048576:.0f} MiB ({sent/1048576/max(0.01,time.monotonic()-started):.1f} MiB/s)',flush=True);last=sent
            response=connection.getresponse();response.read();connection.close()
            if response.status not in (201,204):raise RuntimeError('HTTPS upload returned '+str(response.status))
        remote(args,r'''
from pathlib import Path
import os,hashlib
root=Path('/srv/illuminati/www');release=root/'releases'/str(cfg['code']);release.mkdir(parents=True,exist_ok=True)
for item in cfg['files']:
 incoming=Path('/srv/illuminati/incoming')/item['name']
 with incoming.open('rb') as stream:actual=hashlib.file_digest(stream,'sha256').hexdigest()
 if actual!=item['sha256'] or incoming.stat().st_size!=item['bytes']:raise RuntimeError('Server file verification failed: '+item['name'])
for item in cfg['files']:
 incoming=Path('/srv/illuminati/incoming')/item['name'];os.chmod(incoming,0o644);os.replace(incoming,release/item['name'])
target=release/'Illuminati-Windows-x64.zip';actual=cfg['sha256']
(release/'manifest.json').write_text(cfg['manifest'])
(release/'SHA256SUMS.txt').write_text(''.join(item['sha256']+'  '+item['name']+'\n' for item in cfg['files']))
windows=root/'windows';windows.mkdir(exist_ok=True)
(windows/'latest.json.tmp').write_text(cfg['manifest']);os.replace(windows/'latest.json.tmp',windows/'latest.json')
if not cfg['patch_only']:
 alias=root/'Illuminati-Windows.zip.tmp'
 if alias.is_symlink():alias.unlink()
 alias.symlink_to('releases/'+str(cfg['code'])+'/'+target.name);os.replace(alias,root/'Illuminati-Windows.zip')
print('Published verified release '+str(cfg['code'])+'; SHA256 '+actual)
''',data)
    finally:
        remote(args,r'''
from pathlib import Path
import subprocess
conf=Path('/etc/nginx/sites-available/illuminati-updates')
conf.write_text(conf.read_text().replace('    include /etc/nginx/illuminati-upload.inc;\n',''))
include=Path('/etc/nginx/illuminati-upload.inc')
if include.exists():include.unlink()
subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
print('Temporary upload route removed.')
''')
    print('Download: https://'+args.host+'/Illuminati-Windows.zip')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host',required=True)
    parser.add_argument('--user',default='root')
    parser.add_argument('--key',required=True)
    parser.add_argument('--site',default='outputs/update-site')
    parser.add_argument('--patch-only',action='store_true',help='Upload only the patch; retain and verify the existing complete download.')
    deploy(parser.parse_args())
