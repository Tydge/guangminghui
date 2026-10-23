"""Deploy the dedicated Linux host behind the existing HTTPS listener."""
from pathlib import Path
import argparse, hashlib, http.client, json, secrets, ssl, subprocess, zipfile
from deploy_updates import remote
from export_windows import ROOT

def deploy(args):
    source=Path(args.source).resolve()
    code=int(json.loads((ROOT/'data/release.json').read_text())['code'])
    bundle=ROOT/'work/online-server.zip'
    with zipfile.ZipFile(bundle,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for name in ['IlluminatiServer','IlluminatiServer.pck']:archive.write(source/name,name)
    digest=hashlib.file_digest(bundle.open('rb'),'sha256').hexdigest()
    token=secrets.token_hex(24)
    data={'code':code,'token':token,'sha256':digest,'bytes':bundle.stat().st_size}
    try:
        remote(args,r'''
from pathlib import Path
import os,subprocess,time,json
room_dir=Path('/var/lib/illuminati-online/rooms')
if room_dir.exists():
 for path in room_dir.glob('*.json'):
  state=json.loads(path.read_text())
  if state.get('started') and state['state']['phase']!='over' and time.time()-path.stat().st_mtime<95:
   raise RuntimeError('An online match is active. Wait for the room to finish before deployment.')
incoming=Path('/srv/illuminati/incoming');incoming.mkdir(exist_ok=True)
os.chown(incoming,33,33);os.chmod(incoming,0o700)
conf=Path('/etc/nginx/sites-available/illuminati-updates');text=conf.read_text()
text=text.replace('    location = /health','    include /etc/nginx/illuminati-upload.inc;\n    location = /health')
conf.write_text(text)
Path('/etc/nginx/illuminati-upload.inc').write_text('location = /deploy-'+cfg['token']+' { alias /srv/illuminati/incoming/online-server.zip; dav_methods PUT; client_max_body_size 128m; client_body_timeout 120s; access_log off; limit_except PUT { deny all; } }\n')
subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
''',data)
        connection=http.client.HTTPSConnection(args.host,context=ssl.create_default_context(),timeout=120)
        connection.putrequest('PUT','/deploy-'+token);connection.putheader('Content-Length',str(data['bytes']));connection.endheaders()
        with bundle.open('rb') as stream:
            while block:=stream.read(1024*1024):connection.send(block)
        response=connection.getresponse();response.read();connection.close()
        if response.status not in (201,204):raise RuntimeError('Upload failed: '+str(response.status))
        remote(args,r"""
from pathlib import Path
import hashlib,os,pwd,subprocess,zipfile,json
bundle=Path('/srv/illuminati/incoming/online-server.zip')
with bundle.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
if digest!=cfg['sha256'] or bundle.stat().st_size!=cfg['bytes']:raise RuntimeError('Server bundle integrity mismatch')
target=Path('/opt/illuminati/online/releases')/str(cfg['code'])
if target.exists():
 previous=target/'BUILD.json'
 published=Path('/srv/illuminati/www/releases')/str(cfg['code'])/'manifest.json'
 if published.exists() and (not previous.exists() or json.loads(previous.read_text())['sha256']!=digest):raise RuntimeError('Published server release already exists with different bytes; increase release code.')
target.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(bundle) as archive:
 if set(archive.namelist())!={'IlluminatiServer','IlluminatiServer.pck'}:raise RuntimeError('Unexpected server archive entries')
 # Replace inodes atomically; the old service may still map the executable.
 # Opening that running inode for writing fails with ETXTBSY on Linux.
 for name in ['IlluminatiServer','IlluminatiServer.pck']:
  temporary=target/(name+'.next')
  temporary.write_bytes(archive.read(name))
  os.replace(temporary,target/name)
os.chmod(target/'IlluminatiServer',0o755);os.chmod(target/'IlluminatiServer.pck',0o644)
(target/'BUILD.json').write_text(json.dumps({'code':cfg['code'],'sha256':digest})+'\n')
try:pwd.getpwnam('illuminati')
except KeyError:subprocess.run(['useradd','--system','--home','/var/lib/illuminati-online','--shell','/usr/sbin/nologin','illuminati'],check=True)
current=Path('/opt/illuminati/online/current');temporary=current.with_name('current.next')
if temporary.is_symlink():temporary.unlink()
temporary.symlink_to(target);os.replace(temporary,current)
service='''[Unit]
Description=Illuminati authoritative room server
After=network.target
[Service]
User=illuminati
Group=illuminati
WorkingDirectory=/opt/illuminati/online/current
ExecStart=/opt/illuminati/online/current/IlluminatiServer --headless -- --port=19081 --rooms=/var/lib/illuminati-online/rooms
Restart=on-failure
RestartSec=2
StateDirectory=illuminati-online
StateDirectoryMode=0700
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/illuminati-online
MemoryMax=768M
[Install]
WantedBy=multi-user.target
'''
Path('/etc/systemd/system/illuminati-online.service').write_text(service)
conf=Path('/etc/nginx/sites-available/illuminati-updates');text=conf.read_text()
if 'location = /play {' not in text:
 proxy='''    location = /play {
        proxy_pass http://127.0.0.1:19081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 75s;
        proxy_send_timeout 75s;
        proxy_buffering off;
    }
'''
 text=text.replace('    location = /health',proxy+'    location = /health');conf.write_text(text)
subprocess.run(['nginx','-t'],check=True)
subprocess.run(['systemctl','daemon-reload'],check=True)
subprocess.run(['systemctl','enable','--now','illuminati-online.service'],check=True)
subprocess.run(['systemctl','restart','illuminati-online.service'],check=True)
subprocess.run(['systemctl','reload','nginx'],check=True)
bundle.unlink()
print('Deployed online host '+str(cfg['code'])+' at wss://'+os.environ.get('HOSTNAME','server')+'/play')
""",data)
    finally:
        remote(args,r'''
from pathlib import Path
import subprocess
conf=Path('/etc/nginx/sites-available/illuminati-updates')
conf.write_text(conf.read_text().replace('    include /etc/nginx/illuminati-upload.inc;\n',''))
include=Path('/etc/nginx/illuminati-upload.inc')
if include.exists():include.unlink()
subprocess.run(['nginx','-t'],check=True);subprocess.run(['systemctl','reload','nginx'],check=True)
''')
    print('Online URL: wss://'+args.host+'/play')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host',required=True)
    parser.add_argument('--user',default='root')
    parser.add_argument('--key',required=True)
    parser.add_argument('--source',default=str(ROOT/'outputs/online-server'))
    deploy(parser.parse_args())
