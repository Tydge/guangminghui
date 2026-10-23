"""Create cumulative native PCK patches and signed update manifests.

Compare FINAL optimized packs, never recompress image pixels. Keep the original
base pack for a channel. Signing keys and deployment credentials stay outside Git.
"""
from pathlib import Path
import argparse, base64, hashlib, json, shutil, struct, subprocess, tempfile
from export_windows import ROOT, read_pack


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def contents(path):
    header, entries = read_pack(Path(path))
    with Path(path).open('rb') as stream:
        result = {}
        for item in entries:
            stream.seek(item['offset']); data = stream.read(item['size'])
            if hashlib.md5(data).digest() != item['digest']:
                raise ValueError('Corrupt source pack: '+item['name'])
            result[item['name']] = data
    return header, result


def write_pack(header, entries, output):
    """entries maps normalized paths to bytes, or None for native removals."""
    output=Path(output);output.parent.mkdir(parents=True,exist_ok=True);rows=[]
    with output.open('wb') as stream:
        stream.write(header);stream.write(b'\0'*(-stream.tell()%32));start=stream.tell()
        for name,value in sorted(entries.items()):
            data=value or b'';offset=stream.tell()-start
            stream.write(data);stream.write(b'\0'*(-stream.tell()%32))
            rows.append((name,offset,len(data),hashlib.md5(data).digest() if value is not None else b'\0'*16,0 if value is not None else 2))
        directory=stream.tell();stream.write(struct.pack('<I',len(rows)))
        for name,offset,size,digest,flags in rows:
            encoded=name.encode();encoded+=b'\0'*(-len(encoded)%4)
            stream.write(struct.pack('<I',len(encoded))+encoded+struct.pack('<QQ',offset,size)+digest+struct.pack('<I',flags))
        stream.seek(24);stream.write(struct.pack('<QQ',start,directory))


def patch(base, target, output):
    _, old = contents(base)
    header, new = contents(target)
    immutable = ['project.binary', '.godot/global_script_class_cache.cfg',
                 'data/update_channel.json', 'scripts/update_bootstrap.gdc',
                 'scripts/update_bootstrap.gd.remap']
    changed = [name for name in new if new[name] != old.get(name)]
    removed = sorted(set(old)-set(new))
    if any(old.get(name) != new.get(name) for name in immutable):
        raise ValueError('Bootstrap, global class registry or project settings changed: publish a new complete base/channel.')
    output=Path(output)
    write_pack(header,{name:new.get(name) for name in sorted(set(changed+removed))},output)
    return {'changed':changed,'removed':removed,'bytes':output.stat().st_size,'sha256':sha(output)}


def sign_payload(payload, key, openssl):
    raw=json.dumps(payload,ensure_ascii=False,separators=(',',':'),sort_keys=True).encode('utf-8')
    with tempfile.TemporaryDirectory(prefix='illuminati-sign-') as temporary:
        plain=Path(temporary)/'manifest'; plain.write_bytes(raw)
        signed=subprocess.check_output([str(openssl),'dgst','-sha256','-sign',str(key),str(plain)])
    return {'payload':base64.b64encode(raw).decode('ascii'),'signature':base64.b64encode(signed).decode('ascii')}


def publish(args):
    channel=json.loads((ROOT/'data/update_channel.json').read_text(encoding='utf-8'))
    release=json.loads((ROOT/'data/release.json').read_text(encoding='utf-8'))
    patch_only=getattr(args,'patch_only',False)
    if patch_only:
        if args.zip or not args.baseline or not args.pack or not args.previous_manifest:
            raise ValueError('Patch-only publishing requires --baseline, --pack and --previous-manifest, without --zip.')
        previous=json.loads(base64.b64decode(json.loads(Path(args.previous_manifest).read_text(encoding='utf-8'))['payload']))
        if any(previous.get(k)!=release.get(k) for k in ['base_id','engine','platform']) or previous.get('product')!=channel['product'] or int(previous['code'])>=int(release['code']):
            raise ValueError('Previous manifest must be an older compatible release on this channel.')
        full_info=previous['full'].copy()
    elif not args.zip:
        raise ValueError('A complete release requires --zip.')
    output=Path(args.output).resolve(); directory=output/'releases'/str(release['code']); directory.mkdir(parents=True,exist_ok=True)
    url=channel['origin']+'/releases/'+str(release['code'])
    if not patch_only:
        archive=Path(args.zip).resolve(); full=directory/'Illuminati-Windows-x64.zip'; shutil.copyfile(archive,full)
        full_info={'url':url+'/'+full.name,'bytes':full.stat().st_size,'sha256':sha(full)}
    payload=dict(release,schema=1,product=channel['product'],min_bootstrap=1,
                 notes={'zh':args.notes_zh,'en':args.notes_en},
                 full=full_info)
    if patch_only:payload['full_version']=previous.get('full_version',previous['version'])
    sums=[] if patch_only else [sha(full)+'  '+full.name+'\n']
    if args.baseline:
        result=patch(args.baseline,args.pack,directory/'update.pck')
        payload['patch']={k:result[k] for k in ['bytes','sha256']}
        payload['patch']['url']=url+'/update.pck'
        (directory/'patch-build.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        sums.append(result['sha256']+'  update.pck\n')
    manifest=sign_payload(payload,Path(args.key),args.openssl)
    (output/'windows').mkdir(exist_ok=True)
    for path in [directory/'manifest.json',output/'windows/latest.json']:
        path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    (directory/'SHA256SUMS.txt').write_text(''.join(sums),encoding='ascii')
    print(json.dumps({'version':release['version'],'patch_only':patch_only,'full':full_info,'manifest':str(output/'windows/latest.json')},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip')
    parser.add_argument('--patch-only',action='store_true')
    parser.add_argument('--previous-manifest',help='Previously published signed manifest whose complete download is retained.')
    parser.add_argument('--pack')
    parser.add_argument('--baseline')
    parser.add_argument('--key',required=True)
    parser.add_argument('--openssl',default='openssl')
    parser.add_argument('--output',default=str(ROOT/'outputs/update-site'))
    parser.add_argument('--notes-zh',default='新版AI、后台更新检查，以及中文卡文换行修复。')
    parser.add_argument('--notes-en',default='New AI, background update checks, and Chinese card text wrapping fixes.')
    publish(parser.parse_args())
