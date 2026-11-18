"""The release schedule covers real environments and interacting preference values."""
import copy
import itertools
import unittest

from test_xiangqi_visual_pairs import pairs, registry


class AcceptanceScheduleTests(unittest.TestCase):
    def setUp(self):
        self.value = registry()
        self.value['axes'] = {'board.brightness': ['0.5', '1.0', '1.4'],
                              'board.hue': [0, 90, 180], 'board.coordinates': [False, True]}
        self.value['roles'][0]['states'][0]['axes'] = list(self.value['axes'])
        self.value['interactionGroups'] = [['board.brightness', 'board.hue']]
        self.defaults = {'board': {'brightness': 1.0, 'hue': 0, 'coordinates': True}}

    def test_full_environment_on_defaults_and_each_declared_interaction_on_both_extremes(self):
        schedule = pairs.AcceptanceSchedule(self.value, self.defaults)
        rows = [case['configuration'] for shard in schedule.batch(0, schedule.total) for case in shard['cases']]
        self.assertEqual(len(rows), len({pairs.canonical(row) for row in rows}))
        self.assertEqual(len({pairs.canonical(row['environment']) for row in rows}), 48)
        defaults = {'board.brightness': '1.0', 'board.hue': 0, 'board.coordinates': True}
        self.assertEqual(sum(row['preferences'] == defaults for row in rows), 48)
        for size, locale, mode, scale, dpi in [([480, 480], 'zh-CN', 'dark', 2, 2),
                                                ([1920, 1080], 'en-GB', 'light', 1, 1)]:
            environment = dict(size=size, locale=locale, mode=mode, textScale=scale, dpi=dpi)
            prefs = [row['preferences'] for row in rows if row['environment'] == environment]
            self.assertEqual({(row['board.brightness'], row['board.hue']) for row in prefs},
                             set(itertools.product(['0.5', '1.0', '1.4'], [0, 90, 180])))
            self.assertEqual({row['board.coordinates'] for row in prefs}, {True, False})
        self.assertLess(schedule.total, pairs.count_cases(self.value))

    def test_filtered_batches_retain_global_indexes_and_resource_limits(self):
        other = copy.deepcopy(self.value['roles'][0])
        other['id'] = 'second'
        self.value['roles'].append(other)
        schedule = pairs.AcceptanceSchedule(self.value, self.defaults)
        scoped = schedule.batch(0, 2, role='second', state='normal')[0]['cases']
        self.assertEqual(scoped, schedule.batch(schedule.total // 2, 2)[0]['cases'])
        self.assertEqual(scoped[0]['index'], str(schedule.total // 2))
        self.assertTrue(all(len(shard['cases']) <= 64 for shard in schedule.batch(0, schedule.total)))
        for offset, limit in [(-1, 1), (0, 1025), (schedule.total // 2, 1)]:
            with self.assertRaises(ValueError):
                schedule.batch(offset, limit, role='second')

    def test_missing_defaults_and_misspelled_interactions_fail_closed(self):
        with self.assertRaises(ValueError):
            pairs.AcceptanceSchedule(self.value, {})
        self.value['interactionGroups'][0].append('missing')
        with self.assertRaises(ValueError):
            pairs.AcceptanceSchedule(self.value, self.defaults)
