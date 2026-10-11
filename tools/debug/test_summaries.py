#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
from summarize import summarize
from perf_symbols import summarize as summarize_perf

class SummaryTests(unittest.TestCase):
    def test_domain_coverage_observer_and_operations(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'synthetic.log'
            path.write_text('start|bots=16\n'
                'domains|weapons=1|hats=1|identity_pairing=same_source_player\n'
                'coverage|equipped_custom_weapons=20|equipped_custom_hats=31\n'
                'coverage|equipped_custom_weapons=22|equipped_custom_hats=31\n'
                'observer|root_ms=0.1|tick_peak_ms=0.01\n'
                'observer|root_ms=0.3|tick_peak_ms=0.02\n'
                'slow_operation|tick=10|class=2|profile=0|ms=55.0\n'
                'summary|reason=complete\n')
            result=summarize(path)
            self.assertEqual(result['coverage']['equipped_custom_hats'],{'min':31,'max':31})
            self.assertEqual(result['coverage']['equipped_custom_weapons'],{'min':20,'max':22})
            self.assertEqual(result['observer']['mean_ms_per_second'],0.2)
            self.assertEqual(result['worst_operations'][0]['ms'],'55.0')

    def test_incomplete_not_reported_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'synthetic.log'
            path.write_text('start|bots=16\n')
            with self.assertRaises(ValueError): summarize(path)

    def test_perf_symbol_report_omits_addresses_and_private_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'synthetic.perf.txt'
            path.write_text('srcds_linux 123 100.123456: cpu-clock:u:\n'
                '\t deadbeef SourceHook::MakePageWritable(void*)+0x42 (/private/metamod.2.tf2.so)\n'
                '\t aabbccdd CritManager::OnEntityDestroyed(CBaseEntity*) (/private/game.tf2.ext.2.tf2.so)\n\n')
            result=summarize_perf(path)
            self.assertEqual(result['samples'],1)
            self.assertEqual(len(result['page_write_stacks']),1)
            self.assertNotIn('private',str(result))
            self.assertNotIn('deadbeef',str(result))

if __name__=='__main__': unittest.main()
