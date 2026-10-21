"""Validate English display data without changing canonical Chinese rules or tables."""
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
FIELDS=('name','en','effect','goal','style','target','cost','category')
CJK=re.compile('[\u3400-\u9fff]')
FMT=re.compile(r'%%|%[+ 0-9]*(?:\.\d+)?[sdf]')
def inspect_catalog():
 cards=json.loads((ROOT/'data/cards.json').read_text(encoding='utf-8'))
 catalog=json.loads((ROOT/'data/localization/en.json').read_text(encoding='utf-8'))
 errors=[];sources=catalog['sources'];ui=catalog['ui'];translations=catalog['cards']
 if set(cards)!=set(sources) or set(cards)!=set(translations):errors.append('Card IDs differ between rule data and English catalog')
 for cid,card in cards.items():
  snapshot={k:card[k] for k in FIELDS if k in card}
  if sources.get(cid)!=snapshot:errors.append(f'{cid}: source changed; review its English text and source snapshot')
  if ui.get(card['name'])!=card['en']:errors.append(f'{cid}: English card name is not registered')
  for word in card.get('align',[])+card.get('tags',[])+[card.get('mode',''),card.get('category','')]:
   if CJK.search(word) and word not in ui:errors.append(f'{cid}: unregistered display term {word}')
  for field in ('effect','goal','style','target','cost'):
   if not card.get(field):continue
   text=translations.get(cid,{}).get(field,'')
   if not text or CJK.search(text):errors.append(f'{cid}.{field}: missing English')
   if ui.get(card[field])!=text:errors.append(f'{cid}.{field}: card text differs from runtime phrase')
 for source,text in ui.items():
  if not isinstance(text,str) or (CJK.search(text) and source!='中文'):errors.append(f'Invalid English phrase: {source}')
 templates=catalog['templates'];registered=set(ui)
 for item in templates:
  registered.add(item['source'])
  try:re.compile(item['pattern'])
  except re.error as exc:errors.append(f'Invalid pattern: {item["source"]}: {exc}')
  count=len([x for x in FMT.findall(item['source']) if x!='%%'])
  if set(re.findall(r'\{(\d+)\}',item['text']))!={str(i) for i in range(count)}:errors.append(f'Placeholder mismatch: {item["source"]}')
 for path in (ROOT/'scripts').glob('*.gd'):
  for match in re.finditer(r'"(?:[^"\\]|\\.)*"',path.read_text(encoding='utf-8')):
   source=json.loads(match.group())
   if CJK.search(source) and source.replace('%s%s','%s') not in registered:errors.append(f'{path.name}: unregistered source {source}')
 return {'cards':len(cards),'phrases':len(ui),'templates':len(templates),'errors':errors}
if __name__=='__main__':
 result=inspect_catalog();print(json.dumps(result,ensure_ascii=False,indent=2));sys.exit(bool(result['errors']))
