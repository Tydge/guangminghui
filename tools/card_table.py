"""Merge edited Markdown tables and runtime JSON without overwriting either side."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

FILENAME = '光明会_全部卡牌完整效果_当前版.md'
ID_RE = re.compile(r'^[IGP]\d{2,}$')
KINDS = {'I': 'faction', 'G': 'group', 'P': 'plot'}
RULE_FIELDS = {'effect', 'goal', 'target', 'cost'}

def cell(value):
    return str(value).replace('\\', '\\\\').replace('|', '\\|').replace('\r\n', '\n').replace('\r', '\n').replace('\n', ' / ')

def split_row(line):
    return [part.strip().replace('\\|', '|').replace('\\\\', '\\') for part in re.split(r'(?<!\\)\|', line.strip())[1:-1]]

def row_id(line):
    if not line.strip().startswith('|'): return None
    parts = split_row(line)
    return parts[0] if parts and ID_RE.fullmatch(parts[0]) else None

def parse_table(text, defaults):
    result = {}
    for line in text.splitlines():
        key = row_id(line)
        if key is None: continue
        if key in result: raise ValueError(f'Duplicate card row: {key}')
        parts = split_row(line)
        kind = KINDS[key[0]]
        expected = 8 if kind == 'group' else 6
        if len(parts) != expected: raise ValueError(f'{key}: expected {expected} columns, found {len(parts)}')
        c = copy.deepcopy(defaults.get(key, {'id': key, 'kind': kind, 'p': 0, 'gp': 0, 'r': 0, 'slots': 0, 'align': [], 'tags': [], 'category': '光明会' if kind == 'faction' else ''}))
        if ' / ' not in parts[1]: raise ValueError(f'{key}: keep the Chinese / English name separator')
        c['name'], c['en'] = parts[1].split(' / ', 1)
        if kind == 'plot':
            c.update(zip(('category', 'target', 'effect', 'cost'), parts[2:]))
        else:
            stats = [int(n.strip()) for n in parts[2].split('/')]
            if len(stats) != (3 if kind == 'group' else 2): raise ValueError(f'{key}: invalid P / GP / R values')
            c.update(zip(('p', 'gp', 'r'), stats)); c['slots'] = int(parts[3])
            if kind == 'group':
                c.update(align=[] if parts[4] == '无' else parts[4].split('、'), tags=[] if parts[5] == '无' else parts[5].split('、'), category=parts[6], effect=parts[7])
            else: c.update(effect=parts[4], goal=parts[5])
            if min(c['p'], c['gp'], c['r']) < 0 or not 0 <= c['slots'] <= 3: raise ValueError(f'{key}: negative stat or slots outside 0..3')
            if c['gp'] > c['p']: raise ValueError(f'{key}: printed GP must not exceed P')
        result[key] = c
    if not result: raise ValueError('No card rows found')
    return result

def merge_cards(base, versions):
    merged, changes = {}, []
    keys = set(base).union(*(set(cards) for cards in versions.values()))
    for key in sorted(keys):
        if key in base and any(key not in cards for cards in versions.values()):
            raise ValueError(f'{key}: a document is missing a card; deletion must be handled explicitly')
        merged[key] = {}
        fields = set(base.get(key, {})).union(*(set(cards.get(key, {})) for cards in versions.values()))
        for field in sorted(fields):
            old = base.get(key, {}).get(field)
            changed = [(origin, cards[key][field]) for origin, cards in versions.items() if key in cards and field in cards[key] and cards[key][field] != old]
            values = {json.dumps(value, ensure_ascii=False, sort_keys=True) for _, value in changed}
            if len(values) > 1: raise ValueError(f'Conflict: {key}.{field}: ' + repr(changed))
            value = changed[0][1] if changed else old
            merged[key][field] = copy.deepcopy(value)
            if changed: changes.append({'id': key, 'field': field, 'old': old, 'new': value, 'origins': [origin for origin, _ in changed]})
    return merged, changes

def card_row(key, c):
    name = c['name'] + ' / ' + c['en']
    if c['kind'] == 'group': values = [key, name, f"{c['p']} / {c['gp']} / {c['r']}", c['slots'], '、'.join(c['align']) or '无', '、'.join(c['tags']) or '无', c['category'], c['effect']]
    elif c['kind'] == 'faction': values = [key, name, f"{c['p']} / {c['gp']}", c['slots'], c['effect'], c['goal']]
    else: values = [key, name, c['category'], c['target'], c['effect'], c['cost']]
    return '| ' + ' | '.join(cell(value) for value in values) + ' |'

def layout(text):
    return '\n'.join(line for line in text.splitlines() if row_id(line) is None and not line.startswith('数据校验：'))

def render(template, cards, data_bytes):
    lines = template.splitlines(); present = set(); last = {}
    for i, line in enumerate(lines):
        key = row_id(line)
        if key is not None:
            present.add(key); last[cards[key]['kind']] = i; lines[i] = card_row(key, cards[key])
    for kind, index in sorted(last.items(), key=lambda item: item[1], reverse=True):
        additions = [card_row(key, c) for key, c in sorted(cards.items()) if c['kind'] == kind and key not in present]
        lines[index+1:index+1] = additions
    count = len(cards); digest = hashlib.sha256(data_bytes).hexdigest()
    counts = {kind: sum(c['kind'] == kind for c in cards.values()) for kind in KINDS.values()}
    for i, line in enumerate(lines):
        if line.startswith('# 光明会：'): lines[i] = re.sub(r'：\d+种', f'：{count}种', line)
        if '包含' in line:
            lines[i] = re.sub(r'包含\d+种光明会、\d+种团体、\d+种阴谋', f"包含{counts['faction']}种光明会、{counts['group']}种团体、{counts['plot']}种阴谋", lines[i])
        for label, kind in [('光明会', 'faction'), ('团体', 'group'), ('阴谋', 'plot')]:
            if line.startswith(f'## {label} · '): lines[i] = f'## {label} · {counts[kind]}种'
        if line.startswith('数据校验：'): lines[i] = f'数据校验：{count}种卡牌；源数据 SHA-256：`{digest}`。'
    text = '\n'.join(lines).rstrip() + '\n'
    assert parse_table(text, cards) == cards
    return text

def write_verified(path, data, original):
    temporary = path.with_name(path.name + '.sync.tmp')
    temporary.write_bytes(data)
    try:
        temporary.replace(path)
    except PermissionError as error:
        if getattr(error, 'winerror', None) not in (5, 32): raise
        # Some Windows document readers permit writing but keep rename/delete locked.
        # Verify the open file again before an in-place write; never close the user's editor.
        with path.open('r+b') as stream:
            if stream.read() != original: raise ValueError(f'File edited during synchronization: {path}')
            stream.seek(0); stream.write(data); stream.truncate(); stream.flush()
        temporary.unlink()

def run(project, review, mode, accept_rule_text=False):
    source = project / 'data/cards.json'; local = project / 'docs' / FILENAME
    baseline_path = project / 'data/card_sync_base.json'
    paths = list(dict.fromkeys([source, local, review]))
    snapshots = {path: path.read_bytes() for path in paths}
    runtime = json.loads(snapshots[source].decode('utf-8-sig'))
    baseline = json.loads(baseline_path.read_text(encoding='utf-8')) if baseline_path.exists() else {'cards': runtime, 'template': snapshots[local].decode('utf-8-sig')}
    documents = {path: snapshots[path].decode('utf-8-sig') for path in dict.fromkeys([local, review])}
    versions = {'game': runtime}
    versions.update({str(path): parse_table(text, baseline['cards']) for path, text in documents.items()})
    merged, changes = merge_cards(baseline['cards'], versions)
    layouts = [text for text in documents.values() if layout(text) != layout(baseline['template'])]
    if len({layout(text) for text in layouts}) > 1: raise ValueError('Conflicting prose edits in the two Markdown documents')
    template = layouts[0] if layouts else next(iter(documents.values()))
    data_bytes = (json.dumps(merged, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    document = render(template, merged, data_bytes)
    drift = merged != runtime or any(parse_table(text, merged) != merged for text in documents.values())
    report = {'cards': len(merged), 'changes': changes, 'in_sync': not drift, 'rule_text_review': any(change['field'] in RULE_FIELDS for change in changes)}
    if mode == 'check': return report, int(drift)
    if report['rule_text_review'] and not accept_rule_text: raise ValueError('Effect/goal/target/cost text changed: implement and test the rule change, then use --accept-rule-text')
    for path, original in snapshots.items():
        if path.read_bytes() != original: raise ValueError(f'File edited during synchronization: {path}')
    for path, data in [(source, data_bytes), *((path, document.encode('utf-8')) for path in documents)]:
        if path.read_bytes() != data:
            write_verified(path, data, snapshots[path])
    baseline_path.write_text(json.dumps({'cards': merged, 'template': document}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    report['in_sync'] = True
    (project / 'data/card_sync_last_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return report, 0

def review_path(project, explicit=None):
    if explicit is not None: return explicit
    config = project / 'data/card_sync_config.json'
    if config.exists():
        path=Path(json.loads(config.read_text(encoding='utf-8'))['review_document'])
        if not path.is_absolute():path=project/path
        if path.exists():return path
    return project / 'docs' / FILENAME

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['check', 'sync'])
    parser.add_argument('--review', type=Path)
    parser.add_argument('--accept-rule-text', action='store_true')
    args = parser.parse_args(); project = Path(__file__).resolve().parents[1]
    review = review_path(project, args.review)
    try:
        report, code = run(project, review, args.mode, args.accept_rule_text)
        summary = {key: value for key, value in report.items() if key != 'changes'}
        summary['changed_fields'] = len(report['changes']); summary['changed_cards'] = sorted({change['id'] for change in report['changes']})
        print(json.dumps(summary, ensure_ascii=True)); raise SystemExit(code)
    except (ValueError, KeyError, OSError) as error:
        print(str(error)); raise SystemExit(2)

if __name__ == '__main__': main()
