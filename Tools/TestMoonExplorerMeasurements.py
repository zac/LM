#!/usr/bin/env python3
"""Tests for the owner's noise-floor rule and callback exclusion boundary."""
import unittest
from MeasureMoonExplorerRuns import compare, distribution, overlaps


def run(value):
    return {key: value for key in ['footprint_min_mib', 'footprint_max_mib', 'lifetime_peak_mib',
            'max_window_mean_ms', 'max_window_p99_ms', 'hitches_over_25ms',
            'largest_callback_ms', 'largest_callback_excluding_texture_ms']}


class MeasurementTests(unittest.TestCase):
    def test_decimal_boundary_is_inclusive(self):
        result = compare([run(19.52), run(19.52), run(19.67)], [run(19.67)] * 3)
        self.assertTrue(result['passed'])

    def test_three_runs_required(self):
        with self.assertRaises(AssertionError):
            distribution([1, 2])

    def test_median_is_not_worst_run(self):
        result = compare([run(10), run(12), run(14)], [run(9), run(10), run(1000)])
        self.assertTrue(result['passed'])
        self.assertEqual(result['metrics']['lifetime_peak_mib']['candidate']['median'], 10)

    def test_noise_range_does_not_override_hitch_cap(self):
        result = compare([run(15), run(19), run(18)], [run(22), run(22), run(22)])
        self.assertEqual(result['metrics']['hitches_over_25ms']['noise_limit'], 22)
        self.assertFalse(result['metrics']['hitches_over_25ms']['passed'])

    def test_peak_cap_survives_wide_control_spread(self):
        result = compare([run(600), run(620), run(700)], [run(650)] * 3)
        self.assertFalse(result['metrics']['lifetime_peak_mib']['passed'])
        self.assertEqual(result['metrics']['lifetime_peak_mib']['hard_cap'], 645)

    def test_excludes_callback_that_ends_after_texture_interval(self):
        self.assertTrue(overlaps(9.95, 10.15, [(9, 10)]))
        self.assertFalse(overlaps(10.01, 10.15, [(9, 10)]))

    def test_texture_change_uses_raw_callback(self):
        control, candidate = [run(10)] * 3, [run(10) for _ in range(3)]
        for row in candidate:
            row['largest_callback_ms'] = 100
        self.assertTrue(compare(control, candidate)['passed'])
        self.assertFalse(compare(control, candidate, changes_texture=True)['passed'])


if __name__ == '__main__':
    unittest.main()
