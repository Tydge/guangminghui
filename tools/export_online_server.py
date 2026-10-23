"""Export a headless Linux room host, with rules/data and no artwork or audio."""
from pathlib import Path
import argparse, json, os, shutil, struct, subprocess, zlib
from export_windows import ROOT, TEMPLATE_BYTES, fetch_range, read_pack

def template():
    destination=Path(os.environ['APPDATA'])/'Godot/export_templates/4.6.2.stable'
    target=destination/'linux_release.x86_64'
    if target.exists():return target
    start=TEMPLATE_BYTES-131072
    tail=fetch_range(start,TEMPLATE_BYTES-1)
    end=struct.unpack_from('<4s4H2IH',tail,tail.rfind(b'PK\x05\x06'))
    directory=tail[end[6]-start:end[6]-start+end[5]];position=0
    while position<len(directory):
        fields=struct.unpack_from('<4s6H3I5H2I',directory,position)
        length,extra,comment=fields[10:13]
        name=directory[position+46:position+46+length].decode()
        position+=46+length+extra+comment
        if name!='templates/linux_release.x86_64':continue
        offset=fields[16]
        header=struct.unpack('<4s5H3I2H',fetch_range(offset,offset+29))
        payload_start=offset+30+header[-2]+header[-1]
        raw=fetch_range(payload_start,payload_start+fields[8]-1)
        binary=zlib.decompress(raw,-15) if fields[4]==8 else raw
        if len(binary)!=fields[9] or zlib.crc32(binary)!=fields[7]:raise RuntimeError('Linux template integrity mismatch')
        destination.mkdir(parents=True,exist_ok=True);target.write_bytes(binary)
        print(f'Official Linux runtime: {len(binary):,} bytes',flush=True)
        return target
    raise RuntimeError('Linux runtime not found in official templates')

def preset(staging):
    files=[p.relative_to(ROOT).as_posix() for top in ['scripts','server'] for p in (ROOT/top).rglob('*.gd')]
    files+=['server/main.tscn','data/cards.json','data/release.json','data/update_channel.json','data/localization/en.json']
    selection=', '.join(json.dumps('res://'+name) for name in sorted(files))
    block='''[preset.0]

name="Linux Online Server"
platform="Linux"
runnable=false
dedicated_server=true
custom_features="online_server"
export_filter="resources"
export_files=PackedStringArray(%s)
include_filter="data/cards.json,data/release.json,data/update_channel.json,data/localization/en.json"
exclude_filter="tests/*,tools/*,work/*,outputs/*,docs/*,assets/*,data/card_sync*"
export_path="outputs/online-server/IlluminatiServer"
script_export_mode=2

[preset.0.options]

custom_template/debug="%s"
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
binary_format/architecture="x86_64"
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
'''
    debug_template=(Path(os.environ['APPDATA'])/'Godot/export_templates/4.6.2.stable/linux_release.x86_64').as_posix()
    (staging/'export_presets.cfg').write_text(block%(selection,debug_template),encoding='utf-8')

def stage():
    staging=ROOT/'work/online-server-project';staging.mkdir(parents=True,exist_ok=True)
    for top in ['scripts','server','data']:
        for source in (ROOT/top).rglob('*'):
            if not source.is_file() or source.suffix not in ['.gd','.tscn','.uid','.json']:continue
            if top=='data' and source.name not in ['cards.json','release.json','update_channel.json','en.json']:continue
            target=staging/source.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    (staging/'project.godot').write_text('''config_version=5
[application]
config/name="Illuminati Server"
run/main_scene="res://server/main.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
''',encoding='utf-8')
    preset(staging)
    return staging

def build(args):
    template();staging=stage()
    directory=Path(args.output).resolve();directory.mkdir(parents=True,exist_ok=True)
    output=directory/'IlluminatiServer'
    log=ROOT/'work/online-server-build.log'
    with log.open('w',encoding='utf-8') as stream:
        imported=subprocess.run([args.godot,'--headless','--editor','--path',str(staging),'--import','--quit'],stdout=stream,stderr=subprocess.STDOUT,timeout=90)
        if imported.returncode:raise RuntimeError('Server staging import failed')
        result=subprocess.run([args.godot,'--headless','--path',str(staging),'--export-release','Linux Online Server',str(output)],stdout=stream,stderr=subprocess.STDOUT,timeout=180)
    errors=log.read_text(encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR:' in errors:raise RuntimeError('Server export failed: '+str(log))
    _,entries=read_pack(output.with_suffix('.pck'))
    if any(e['name'].startswith(('assets/','tests/','tools/','work/','outputs/','docs/')) for e in entries):raise RuntimeError('Unexpected asset/development files in server pack')
    print(json.dumps({'exe_bytes':output.stat().st_size,'pack_bytes':output.with_suffix('.pck').stat().st_size,'files':len(entries),'output':str(output)},indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--output',default=str(ROOT/'outputs/online-server'))
    build(parser.parse_args())
