"""Build the Windows share preset without resampling or re-encoding any artwork.

Uses official Godot 4.6.2 templates and the version-3 PCK / GST2 formats.
See Godot's pck_packer.cpp and resource_importer_texture.cpp at 4.6.2-stable.
Native pixel verification, PCK checks and release EXE snapshots run before zipping.
"""
from pathlib import Path
import argparse, hashlib, json, os, shutil, struct, subprocess, urllib.request, zlib, zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.6.2"
TEMPLATE_URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
TEMPLATE_BYTES = 1251900388

def fetch_range(start, end):
    request = urllib.request.Request(TEMPLATE_URL, headers={"Range": f"bytes={start}-{end}", "User-Agent": "Illuminati-Windows-build", "Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=90) as response:
        expected = f"bytes {start}-{end}/{TEMPLATE_BYTES}"
        if response.status != 206 or response.headers.get("Content-Range") != expected:
            raise RuntimeError(f"Server did not return requested range: {response.status} {response.headers.get('Content-Range')}")
        data = response.read()
    if len(data) != end-start+1:
        raise RuntimeError("Incomplete template download")
    return data

def templates():
    destination = Path(os.environ['APPDATA']) / 'Godot/export_templates/4.6.2.stable'
    expected = {'windows_release_x86_64.exe': 104653312, 'windows_release_x86_64_console.exe': 188928, 'version.txt': 13}
    if all((destination/name).exists() and (destination/name).stat().st_size == size for name,size in expected.items()):
        return
    tail_start = TEMPLATE_BYTES-131072
    tail = fetch_range(tail_start, TEMPLATE_BYTES-1)
    end = struct.unpack_from('<4s4H2IH', tail, tail.rfind(b'PK\x05\x06'))
    directory = tail[end[6]-tail_start:end[6]-tail_start+end[5]]
    position = 0
    destination.mkdir(parents=True, exist_ok=True)
    while position < len(directory):
        fields = struct.unpack_from('<4s6H3I5H2I', directory, position)
        name_length, extra, comment = fields[10:13]
        name = directory[position+46:position+46+name_length].decode('utf-8')
        position += 46+name_length+extra+comment
        if name.removeprefix('templates/') not in expected:
            continue
        offset, compressed_size = fields[16], fields[8]
        header = fetch_range(offset, offset+29)
        local = struct.unpack('<4s5H3I2H', header)
        payload_start = offset+30+local[-2]+local[-1]
        payload = fetch_range(payload_start, payload_start+compressed_size-1)
        data = zlib.decompress(payload, -15) if fields[4] == 8 else payload
        if len(data) != fields[9] or zlib.crc32(data) != fields[7]:
            raise RuntimeError(f'Template CRC/size mismatch: {name}')
        target = destination / name.removeprefix('templates/')
        target.write_bytes(data)
        print(f'Official template: {target.name} ({len(data):,} bytes)', flush=True)

def read_pack(path):
    with path.open('rb') as stream:
        header = stream.read(104)
        magic, version, major, minor, patch, flags, base, directory = struct.unpack_from('<6I2Q', header)
        if magic != 0x43504447 or version != 3 or flags != 2 or (major,minor,patch) != (4,6,2):
            raise RuntimeError('Unsupported PCK format/version/flags; no unsafe repack attempted')
        stream.seek(directory)
        count, = struct.unpack('<I',stream.read(4))
        files = []
        for _ in range(count):
            length, = struct.unpack('<I', stream.read(4))
            name = stream.read(length).rstrip(b'\0').decode('utf-8')
            offset,size = struct.unpack('<QQ',stream.read(16))
            digest = stream.read(16)
            file_flags, = struct.unpack('<I',stream.read(4))
            if file_flags:
                raise RuntimeError('Encrypted/removal entry unsupported')
            files.append({'name':name,'offset':base+offset,'size':size,'digest':digest})
    return header, files

def optimize_pack(stock, target, reference):
    header, files = read_pack(stock)
    images = {item['imported'].removeprefix('res://'):item for item in reference}
    optimized = []; entries = []
    with stock.open('rb') as source, target.open('wb') as out:
        out.write(header); out.write(b'\0' * ((-out.tell()) % 32)); base = out.tell()
        for item in files:
            source.seek(item['offset']); data = source.read(item['size'])
            if hashlib.md5(data).digest() != item['digest']:
                raise RuntimeError('Stock PCK checksum mismatch: '+item['name'])
            original_size = len(data)
            image = images.get(item['name'])
            if image and image['sha256'] == image['source_sha256']:
                # The native verifier proved imported pixels equal source pixels.
                # Keep the original GST2 header; replace its sole WebP payload.
                if data[:4] != b'GST2' or struct.unpack_from('<I',data,36)[0] != 2 or struct.unpack_from('<I',data,44)[0] != 0:
                    raise RuntimeError('Unsupported texture layout: '+item['name'])
                source_webp = (ROOT/image['source'].removeprefix('res://')).read_bytes()
                if source_webp[:4] != b'RIFF' or source_webp[8:12] != b'WEBP':
                    raise RuntimeError('Expected original WebP: '+image['source'])
                data = data[:52] + struct.pack('<I',len(source_webp)) + source_webp
                optimized.append({'source':image['source'],'before':original_size,'after':len(data),'pixel_sha256':image['sha256']})
            offset = out.tell()-base
            out.write(data); out.write(b'\0' * ((-out.tell()) % 32))
            entries.append((item['name'],offset,len(data),hashlib.md5(data).digest()))
        directory = out.tell(); out.write(struct.pack('<I',len(entries)))
        for name,offset,size,digest in entries:
            encoded = name.encode('utf-8'); encoded += b'\0' * ((-len(encoded)) % 4)
            out.write(struct.pack('<I',len(encoded))+encoded+struct.pack('<QQ',offset,size)+digest+struct.pack('<I',0))
        out.seek(24); out.write(struct.pack('<QQ',base,directory))
    _, verify = read_pack(target)
    with target.open('rb') as stream:
        for item in verify:
            stream.seek(item['offset'])
            if hashlib.md5(stream.read(item['size'])).digest() != item['digest']:
                raise RuntimeError('Repacked PCK checksum mismatch: '+item['name'])
    names = [item['name'] for item in files]
    forbidden = ('tests/','tools/','docs/','work/','outputs/','assets/sources/','data/card_sync')
    if any(name.startswith(forbidden) or name in ['AGENTS.md','README.md'] for name in names):
        raise RuntimeError('Development files were included in export')
    return {'stock_pack_bytes':stock.stat().st_size,'pack_bytes':target.stat().st_size,'files':len(files),'optimized_textures':optimized,'preserved_textures':len(images)-len(optimized)}

def build(args):
    (ROOT/'work').mkdir(exist_ok=True)
    templates()
    output = Path(args.output).resolve(); output.mkdir(parents=True,exist_ok=True)
    executable = output/'Illuminati.exe'
    subprocess.run([args.godot,'--headless','--path',str(ROOT),'--export-release','Windows Share',str(executable)],check=True,cwd=ROOT)
    reference_log=ROOT/'work/windows-reference.log'
    with reference_log.open('w',encoding='utf-8') as stream:
        result=subprocess.run([args.godot,'--path',str(ROOT),'--position','9000,9000','--script','res://tests/test_windows_export.gd','--',f'--reference={Path(args.reference).resolve()}'],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,timeout=120)
    if result.returncode or '"failures":[]' not in reference_log.read_text(encoding='utf-8'):
        raise RuntimeError('Native source-pixel reference failed: '+str(reference_log))
    pack = executable.with_suffix('.pck'); stock = ROOT/'work/windows-stock.pck'; shutil.move(str(pack),stock)
    reference = json.loads(Path(args.reference).read_text(encoding='utf-8'))
    report = optimize_pack(stock,pack,reference)
    report.update(executable_bytes=executable.stat().st_size,engine=VERSION,architecture='Windows x86_64',default_language='en',no_additional_loss=True)
    (ROOT/'work/windows-export-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='optimized_textures'},indent=2))
    captures=ROOT/'work/qa-windows';captures.mkdir(parents=True,exist_ok=True)
    log=ROOT/'work/windows-shipped-smoke.log'
    with log.open('w',encoding='utf-8') as stream:
        # Release templates intentionally omit --script. Test the same PCK using
        # the script-capable engine, then render actual release EXE snapshots.
        result=subprocess.run([args.godot,'--main-pack',str(pack),'--position','9000,9000','--script',str(ROOT/'tests/test_windows_export.gd'),'--',f'--verify={Path(args.reference).resolve()}',f'--output={captures}'],cwd=output,stdout=stream,stderr=subprocess.STDOUT,timeout=180)
    diagnostics=log.read_text(encoding='utf-8')
    if result.returncode or any(word in diagnostics for word in ['ERROR:', 'SCRIPT ERROR:', 'Parse Error']) or '"failures":[]' not in diagnostics:
        raise RuntimeError('Exported executable smoke test failed; inspect '+str(log))
    print(diagnostics[-1600:],flush=True)
    for mode in ['menu','battle','inspect']:
        screenshot=captures/f'release-{mode}.png';runtime_log=captures/f'release-{mode}.log'
        result=subprocess.run([str(executable),'--position','9000,9000','--log-file',str(runtime_log),'--',f'--snapshot={mode}',f'--snapshot-output={screenshot}'],cwd=output,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=45)
        messages=runtime_log.read_text(encoding='utf-8') if runtime_log.exists() else ''
        if result.returncode or not screenshot.exists() or 'ERROR:' in messages:
            raise RuntimeError('Native release rendering failed: '+mode)
        print('Native release snapshot: '+mode,flush=True)
    package(output,report)

def package(output,report):
    """Create a conventional ZIP; Windows Explorer can extract it directly."""
    readme='''ILLUMINATI - WINDOWS PLAYTEST

Extract the entire ZIP first, then double-click Illuminati.exe.
Keep Illuminati.exe and Illuminati.pck together. No Godot installation is needed.
Windows 64-bit (Intel/AMD), OpenGL 3.3 compatible graphics.

The first launch is in English. Settings > Language switches English / Chinese.
Choose Easy, Normal or Hard, then start a game against the AI.

CONTROLS
Click to select a card. Hover, right-click or use Inspect to read the full card.
Drag empty tabletop space to pan; use the mouse wheel to zoom.
During setup, click the Select button to choose a card; its picture opens Inspect.
Battle and attack-preview windows can be dragged by their title bars.
Use View Battlefield to hide a choice or battle window, then return to it.

See Quick_Start_EN.txt for rules, alignments, tags, support and Resources.
Your language and other preferences are saved locally on your own computer.

This is a local single-player playtest against AI.
'''
    (output/'README.txt').write_text(readme,encoding='utf-8')
    quick=(ROOT/'docs/Quick_Start_EN.md').read_text(encoding='utf-8')
    (output/'Quick_Start_EN.txt').write_text(quick,encoding='utf-8')
    licenses=output/'Licenses';licenses.mkdir(exist_ok=True)
    for source,name in [(ROOT/'assets/fonts/OFL.txt','NotoSansSC-OFL.txt'),(ROOT/'assets/audio/Kenney-License.txt','Kenney-CC0.txt'),(ROOT/'work/GODOT-LICENSE.txt','Godot-MIT.txt'),(ROOT/'work/GODOT-THIRD-PARTY.txt','Godot-Third-Party.txt')]:
        shutil.copyfile(source,licenses/name)
    (output/'CREDITS.txt').write_text('Engine: Godot Engine 4.6.2 (MIT).\nFont: Noto Sans SC (SIL OFL 1.1).\nAudio: Kenney Interface Sounds (CC0).\nCard and interface illustrations: generated for this project.\nTaylor Swift and Lionel Messi photographs: supplied by the project owner; original photographic rights remain with their owners.\nCard names and themes are inspired by Illuminati.\nSee Licenses for engine, font and audio license texts.\n',encoding='utf-8')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    card_count=len(json.loads((ROOT/'data/cards.json').read_text(encoding='utf-8')))
    manifest={'engine':VERSION,'source_commit':revision,'platform':'Windows x86_64','default_language':'en','card_count':card_count,'additional_image_quality_loss':False,'files':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [output/'Illuminati.exe',output/'Illuminati.pck']}}
    (output/'BUILD.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    archive=output.parent/'Illuminati-Windows-x64-EN.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as zip:
        for path in sorted(output.rglob('*')):
            if path.is_file():zip.write(path,output.name+'/'+path.relative_to(output).as_posix())
    with zipfile.ZipFile(archive) as zip:
        if zip.testzip() is not None:raise RuntimeError('ZIP integrity test failed')
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(digest+'  '+archive.name+'\n',encoding='ascii')
    report.update(zip_path=str(archive),zip_bytes=archive.stat().st_size,zip_sha256=digest)
    (ROOT/'work/windows-export-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(f'SHARE ZIP: {archive} ({archive.stat().st_size:,} bytes)',flush=True)

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--output',default=str(ROOT/'outputs/windows/Illuminati'))
    parser.add_argument('--reference',default=str(ROOT/'work/windows-texture-reference.json'))
    build(parser.parse_args())
