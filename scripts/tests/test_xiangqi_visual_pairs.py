"""Runs only on Actions; matrices are never expanded to a million-element list."""
import copy
import sys
import json
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import xiangqi_visual_pairs as pairs


def registry(extra_axes=None):
    axes = {
        "board.boardTheme": [f"theme-{index}" for index in range(26)],
        "board.brightness": [f"{index / 10:.1f}" for index in range(2, 15)],
        "board.hue": list(range(0, 361, 30)),
        **(extra_axes or {}),
    }
    return {
        "schema": 1,
        "environment": {
            "size": [[480, 480], [1280, 720], [1920, 1080]],
            "locale": ["en-GB", "zh-CN"],
            "mode": ["light", "dark"],
            "textScale": [1, 2],
            "dpi": [1, 2],
        },
        "axes": axes,
        "roles": [{
            "id": "board",
            "sources": {"lichess": "lib/chess.dart", "xiangqi": "lib/xiangqi.dart"},
            "states": [{
                "id": "normal",
                "driver": "board",
                "axes": list(axes),
                "requiredRoles": ["toolbar"],
                "allowedDifferences": ["board-art"],
            }],
        }],
    }


class MatrixTests(unittest.TestCase):
    def test_locked_environment_and_filter_grid_are_a_full_cartesian_product(self):
        self.assertEqual(pairs.count_cases(registry()), 210_912)

    def test_all_discrete_preferences_multiply_not_pairwise_sample(self):
        value = registry({"board.coordinates": [False, True], "board.pieceSet": ["a", "b", "c"]})
        self.assertEqual(pairs.count_cases(value), 210_912 * 2 * 3)

    def test_true_dpi_and_text_scale_remain_independent_axes(self):
        value = registry()
        value["axes"] = {}
        value["roles"][0]["states"][0]["axes"] = []
        cases = [pairs.case_at(value, index) for index in range(48)]
        configurations = {(
            tuple(case["configuration"]["environment"]["size"]),
            case["configuration"]["environment"]["locale"],
            case["configuration"]["environment"]["mode"],
            case["configuration"]["environment"]["textScale"],
            case["configuration"]["environment"]["dpi"],
        ) for case in cases}
        self.assertEqual(len(configurations), 48)

    def test_random_access_is_exact_beyond_javascript_and_int64_ranges(self):
        value = registry({f"toggle-{index}": [False, True] for index in range(60)})
        count = pairs.count_cases(value)
        self.assertEqual(count, 210_912 * 2**60)
        last = pairs.case_at(value, count - 1)
        self.assertEqual(last["index"], str(count - 1))
        self.assertEqual(last["configuration"]["environment"]["dpi"], 2)
        self.assertTrue(all(last["configuration"]["preferences"][f"toggle-{i}"] for i in range(60)))

    def test_batch_caps_and_shards_keep_every_requested_case(self):
        batch = pairs.plan_batch(registry(), 100, 1024)
        self.assertEqual(len(batch), 16)
        self.assertTrue(all(len(shard["cases"]) <= 64 for shard in batch))
        indexes = [int(case["index"]) for shard in batch for case in shard["cases"]]
        self.assertEqual(indexes, list(range(100, 1124)))

    def test_oversized_or_out_of_range_batches_are_rejected_not_clamped(self):
        for offset, limit in [(0, 1025), (-1, 1), (0, 0), (210_912, 1), (210_911, 2)]:
            with self.subTest(offset=offset, limit=limit):
                with self.assertRaises(ValueError):
                    pairs.plan_batch(registry(), offset, limit)

    def test_unknown_duplicate_or_empty_axes_cannot_silently_shrink_coverage(self):
        for field in ("unknown", "duplicate", "empty"):
            value = registry()
            if field == "unknown":
                value["roles"][0]["states"][0]["axes"].append("missing")
            elif field == "duplicate":
                value["roles"][0]["states"][0]["axes"].append("board.hue")
            else:
                value["axes"]["board.hue"] = []
            with self.subTest(field=field):
                with self.assertRaises(ValueError):
                    pairs.count_cases(value)

    def test_fingerprint_binds_source_registry_engine_fonts_and_renderer(self):
        value = registry()
        runtime = {"flutter": "fixed-engine", "fonts": {"cjk": "hash-a"}}
        original = pairs.fingerprint("a" * 40, value, runtime)
        changed = copy.deepcopy(value)
        changed["roles"][0]["states"][0]["allowedDifferences"].append("extra-mask")
        for digest in [
            pairs.fingerprint("b" * 40, value, runtime),
            pairs.fingerprint("a" * 40, changed, runtime),
            pairs.fingerprint("a" * 40, value, {**runtime, "flutter": "different"}),
            pairs.fingerprint("a" * 40, value, {**runtime, "fonts": {"cjk": "hash-b"}}),
        ]:
            self.assertNotEqual(digest, original)
        self.assertEqual(len(original), 64)

    def test_an_absent_pair_report_never_counts_as_passed(self):
        verdict = pairs.evaluate_case({}, {}, Path("/nonexistent"), "2026-11-02T00:00:00Z")
        self.assertEqual(verdict["status"], "invalid")

    def test_production_registry_keeps_locked_environment_filters_and_all_entry_roles(self):
        path = Path(__file__).resolve().parents[2] / "test/visual/xiangqi_pair_registry.json"
        value = json.loads(path.read_text())
        self.assertEqual(value["environment"], registry()["environment"])
        self.assertEqual(value["axes"]["board.brightness"], registry()["axes"]["board.brightness"])
        self.assertEqual(value["axes"]["board.hue"], registry()["axes"]["board.hue"])
        self.assertEqual(len(value["roles"]), 49)
        self.assertEqual(len({role["id"] for role in value["roles"]}), 49)
        self.assertTrue(all(value["nonVisualAcceptance"][kind] == "not-run" for kind in value["nonVisualAcceptance"]))


if __name__ == "__main__":
    unittest.main()
