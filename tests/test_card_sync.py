import copy
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('card_table', PROJECT / 'tools/card_table.py')
sync = importlib.util.module_from_spec(spec); spec.loader.exec_module(sync)
CARDS = json.loads((PROJECT / 'data/cards.json').read_text(encoding='utf-8'))
DOCUMENT = (PROJECT / 'docs' / sync.FILENAME).read_text(encoding='utf-8')

class CardSyncTests(unittest.TestCase):
    def test_clean_clone_uses_its_own_card_table(self):
        with tempfile.TemporaryDirectory(dir=PROJECT / 'tests') as directory:
            root=Path(directory); (root/'docs').mkdir(); (root/'data').mkdir()
            self.assertEqual(sync.review_path(root), root/'docs'/sync.FILENAME)
            (root/'data/card_sync_config.json').write_text(json.dumps({'review_document':'missing-on-another-computer.md'}),encoding='utf-8')
            self.assertEqual(sync.review_path(root), root/'docs'/sync.FILENAME)

    def test_all_card_fields_roundtrip(self):
        self.assertEqual(sync.parse_table(DOCUMENT, CARDS), CARDS)
        self.assertNotIn('<br', DOCUMENT)

    def test_disjoint_human_and_developer_changes_merge(self):
        human, developer = copy.deepcopy(CARDS), copy.deepcopy(CARDS)
        human['G071']['p'] = 8; developer['G071']['gp'] = 2
        merged, changes = sync.merge_cards(CARDS, {'human': human, 'game': developer})
        self.assertEqual((merged['G071']['p'], merged['G071']['gp']), (8, 2))
        self.assertEqual(len(changes), 2)
        self.assertEqual(CARDS['G071']['p'], 7)

    def test_same_field_conflicts_are_not_silently_overwritten(self):
        human, developer = copy.deepcopy(CARDS), copy.deepcopy(CARDS)
        human['G071']['p'] = 8; developer['G071']['p'] = 9
        with self.assertRaisesRegex(ValueError, 'Conflict: G071.p'):
            sync.merge_cards(CARDS, {'human': human, 'game': developer})

    def test_duplicate_and_missing_rows_are_errors(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            sync.parse_table(DOCUMENT + sync.card_row('G071', CARDS['G071']), CARDS)
        human = copy.deepcopy(CARDS); del human['G071']
        with self.assertRaisesRegex(ValueError, 'missing'):
            sync.merge_cards(CARDS, {'human': human, 'game': CARDS})

    def test_new_cards_export_without_dropping_user_notes(self):
        extended = copy.deepcopy(CARDS); extended['G999'] = copy.deepcopy(CARDS['G043'])
        extended['G999'].update(id='G999', name='测试团体')
        template = DOCUMENT + '\n玩家批注：保留这行。\n'
        rendered = sync.render(template, extended, json.dumps(extended).encode())
        self.assertEqual(sync.parse_table(rendered, extended), extended)
        self.assertIn(f"团体 · {sum(c['kind']=='group' for c in CARDS.values())+1}种", rendered)
        self.assertIn('玩家批注：保留这行。', rendered)

    def test_windows_reader_lock_preserves_notes_and_rejects_concurrent_edit(self):
        with tempfile.TemporaryDirectory(dir=PROJECT / 'tests') as directory:
            target=Path(directory)/'review.md'; target.write_bytes(b'player notes')
            error=PermissionError('reader keeps rename locked'); error.winerror=32
            with patch.object(Path, 'replace', side_effect=error):
                sync.write_verified(target, b'new data and notes', b'player notes')
                self.assertEqual(target.read_bytes(), b'new data and notes')
                with self.assertRaisesRegex(ValueError, 'edited during'):
                    sync.write_verified(target, b'would overwrite', b'old snapshot')
                self.assertEqual(target.read_bytes(), b'new data and notes')

    def test_real_import_and_effect_review_guard(self):
        parent = (PROJECT / 'tests').resolve()
        with tempfile.TemporaryDirectory(prefix='cards-sync-', dir=parent) as directory:
            root = Path(directory).resolve()
            self.assertEqual(root.parent, parent)  # Cleanup remains inside this test workspace.
            (root / 'data').mkdir(); (root / 'docs').mkdir()
            source = root / 'data/cards.json'; local = root / 'docs' / sync.FILENAME; review = root / 'review.md'
            source.write_text(json.dumps(CARDS, ensure_ascii=False), encoding='utf-8')
            local.write_text(DOCUMENT, encoding='utf-8'); review.write_text(DOCUMENT, encoding='utf-8')
            sync.run(root, review, 'sync')
            altered = copy.deepcopy(CARDS); altered['G071']['p'] = 8
            review.write_text(sync.render(DOCUMENT, altered, json.dumps(altered).encode()), encoding='utf-8')
            report, code = sync.run(root, review, 'check')
            self.assertEqual(code, 1); self.assertEqual(json.loads(source.read_text(encoding='utf-8'))['G071']['p'], 7)
            sync.run(root, review, 'sync')
            self.assertEqual(json.loads(source.read_text(encoding='utf-8'))['G071']['p'], 8)
            altered['G071']['effect'] = '待实现的新技能。'
            review.write_text(sync.render(review.read_text(encoding='utf-8'), altered, json.dumps(altered).encode()), encoding='utf-8')
            originals = {path: path.read_bytes() for path in [source, local, review]}
            with self.assertRaisesRegex(ValueError, 'implement and test'):
                sync.run(root, review, 'sync')
            self.assertEqual(originals, {path: path.read_bytes() for path in originals})
            sync.run(root, review, 'sync', accept_rule_text=True)
            self.assertEqual(json.loads(source.read_text(encoding='utf-8'))['G071']['effect'], '待实现的新技能。')

if __name__ == '__main__': unittest.main()
