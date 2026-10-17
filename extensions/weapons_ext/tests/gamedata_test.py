#!/usr/bin/env python3
"""Contract tests: preserve binary patterns and ordered address programs."""
from pathlib import Path
import unittest
from gamedata_merge import parse, emit, merge


class GameDataTests(unittest.TestCase):
    def test_escapes_and_order_round_trip(self):
        source = r'"Games" { "tf" { "Addresses" { "x" { "signature" "\x55\x89*" "read" "4" "read" "8" } } } }'
        self.assertEqual(parse(source), parse(emit(parse(source))))
        reads = parse(source)[0][1][0][1][0][1][0][1]
        self.assertEqual(reads[-2:], [('read', '4'), ('read', '8')])

    def test_platform_union_and_identical_deduplication(self):
        target = parse('"Games" { "tf" { "Offsets" { "x" { "linux" "2" } } } }')
        other = parse('"Games" { "tf" { "Offsets" { "x" { "linux" "2" "windows" "1" } } } }')
        merge(target, other)
        self.assertEqual(target, other)
        merge(target, other)
        self.assertEqual(target, other)

    def test_conflicting_platform_fails_closed(self):
        target = parse('"Games" { "tf" { "Offsets" { "x" { "linux" "2" } } } }')
        other = parse('"Games" { "tf" { "Offsets" { "x" { "linux" "3" } } } }')
        with self.assertRaises(ValueError):
            merge(target, other)

    def test_ordered_address_conflict_fails_closed(self):
        target = parse('"Games" { "tf" { "Addresses" { "x" { "linux" { "read" "4" "read" "8" } } } } }')
        other = parse('"Games" { "tf" { "Addresses" { "x" { "linux" { "read" "8" "read" "4" } } } } }')
        with self.assertRaises(ValueError):
            merge(target, other)

    def test_malformed_input_rejected(self):
        for source in ('"Games" {', '}', '"x"', 'unquoted'):
            with self.assertRaises(ValueError):
                parse(source)

    def test_master_has_unique_selectors_groups_and_entries(self):
        root = Path(__file__).resolve().parents[3]
        path = root / 'tf/addons/sourcemod/gamedata/weapons.games.txt'
        tree = parse(path.read_text())
        self.assertEqual([key for key, _ in tree], ['Games'])
        self.assertEqual(parse(emit(tree)), tree)
        def check(nodes, depth=0):
            if depth > 3:
                return  # Deeper address programs may repeat ordered directives.
            keys = [key for key, _ in nodes]
            self.assertEqual(len(keys), len(set(keys)))
            for _, value in nodes:
                if isinstance(value, list):
                    check(value, depth + 1)
        check(tree)
        groups = dict(dict(tree)['Games'][0][1])
        for group in ('Signatures', 'Offsets', 'Addresses', 'Functions', 'Keys'):
            self.assertIn(group, groups)

    def test_native_cache_is_distinct_but_same_physical_file(self):
        root = Path(__file__).resolve().parents[3]
        config = root / 'extensions/weapons_ext/src/smsdk_config.h'
        self.assertIn('#define WEAPONS_GAMECONFIG_NAME "./weapons.games"', config.read_text())
        directory = root / 'tf/addons/sourcemod/gamedata'
        self.assertEqual((directory/'./weapons.games.txt').resolve(),
                         (directory/'weapons.games.txt').resolve())

    def test_building_damage_binding(self):
        root = Path(__file__).resolve().parents[3]
        tree = parse((root/'tf/addons/sourcemod/gamedata/weapons.games.txt').read_text())
        groups = dict(dict(dict(tree)['Games'])['tf'])
        entry = dict(dict(groups['Signatures'])['CBaseObject::OnTakeDamage()'])
        self.assertEqual(entry['library'], 'server')
        self.assertEqual(entry['linux'], '@_ZN11CBaseObject12OnTakeDamageERK15CTakeDamageInfo')

    def test_scoped_crit_request_binding(self):
        root = Path(__file__).resolve().parents[3]
        tree = parse((root/'tf/addons/sourcemod/gamedata/weapons.games.txt').read_text())
        groups = dict(dict(dict(tree)['Games'])['tf'])
        entry = dict(dict(groups['Signatures'])['CTakeDamageInfo::SetCritType()'])
        self.assertEqual(entry['library'], 'server')
        self.assertEqual(entry['linux'], '@_ZN15CTakeDamageInfo11SetCritTypeENS_9ECritTypeE')


if __name__ == '__main__':
    unittest.main()
