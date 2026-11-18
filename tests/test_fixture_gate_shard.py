"""CI-1: fixture_gate.py --shard K/N splits the fixture list across CI jobs.

#358 had 293 fixtures and the serial gate took 73.5 min. The split is by
sorted file name, every N-th file, so the shards partition the list.

Plain unittest: `python -m unittest -v tests.test_fixture_gate_shard`.
"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import fixture_gate as g  # noqa: E402

PATHS = ["/f/%03d_%s.sql" % (i, c) for i, c in enumerate("zyxwvutsrqponmlkjihgfedcba" * 3)]


class ShardSelection(unittest.TestCase):
    def test_shards_partition_the_list_without_overlap(self):
        for n in (1, 2, 3, 4, 7):
            parts = [g.select_shard(PATHS, k, n) for k in range(1, n + 1)]
            flat = [p for part in parts for p in part]
            self.assertEqual(len(flat), len(set(flat)), "overlap at n=%d" % n)
            self.assertEqual(sorted(flat), sorted(PATHS), "union differs at n=%d" % n)

    def test_split_is_deterministic_and_input_order_free(self):
        a = g.select_shard(PATHS, 2, 3)
        self.assertEqual(a, g.select_shard(list(reversed(PATHS)), 2, 3))
        self.assertEqual(a, sorted(PATHS)[1::3])

    def test_split_is_roughly_even(self):
        sizes = [len(g.select_shard(PATHS, k, 3)) for k in (1, 2, 3)]
        self.assertLessEqual(max(sizes) - min(sizes), 1, sizes)

    def test_bad_k_or_n_is_refused(self):
        for bad in ("0/3", "4/3", "-1/3", "1/0", "x/3", "2", "1/2/3", "", "1.5/3"):
            with self.assertRaises(ValueError, msg=bad):
                g.parse_shard(bad)
        self.assertEqual(g.parse_shard("2/3"), (2, 3))

    def test_no_shard_means_the_whole_list(self):
        self.assertEqual(g.select_shard(PATHS, 1, 1), sorted(PATHS))


# konsolidat#370 B (Deepak Pai, 18 Nov 2026): a final CI job proves that the
# shards together ran every fixture exactly once. Without it, a shard that never
# starts, or one whose list was cut short, leaves the workflow green.
NAMES = ["a.sql", "b.must_flag.sql", "c.sql", g.ZERO_DIM_FIXTURES[0]]


def _reports(n, names=NAMES):
    out = []
    for k in range(1, n + 1):
        mine = [os.path.basename(p) for p in g.select_shard(names, k, n)]
        out.append({"shard": [k, n], "labels": g.expected_labels(mine)})
    return out


class ShardsComplete(unittest.TestCase):
    def test_expected_labels_add_the_zero_dimension_rerun(self):
        self.assertEqual(g.expected_labels(["a.sql", g.ZERO_DIM_FIXTURES[0]]),
                         ["a.sql", g.ZERO_DIM_FIXTURES[0], g.ZERO_DIM_FIXTURES[0] + " [dimensions: []]"])

    def test_every_shard_reporting_every_fixture_is_complete(self):
        for n in (1, 2, 3):
            self.assertEqual(g.check_shards(_reports(n), NAMES), [], n)

    def test_a_missing_shard_fails(self):
        problems = g.check_shards(_reports(3)[:2], NAMES)
        self.assertTrue(any("shard 3/3" in p for p in problems), problems)
        self.assertTrue(any("never ran" in p for p in problems), problems)

    def test_no_report_at_all_fails(self):
        self.assertTrue(g.check_shards([], NAMES))

    def test_a_dropped_fixture_fails_by_name(self):
        reps = _reports(3)
        reps[0]["labels"] = reps[0]["labels"][1:]
        problems = g.check_shards(reps, NAMES)
        self.assertTrue(any("a.sql" in p for p in problems), problems)

    def test_a_fixture_run_twice_fails(self):
        reps = _reports(3)
        reps[1]["labels"].append("a.sql")
        self.assertTrue(any("more than once" in p for p in g.check_shards(reps, NAMES)))

    def test_an_unknown_fixture_fails(self):
        reps = _reports(3)
        reps[2]["labels"].append("ghost.sql")
        self.assertTrue(any("ghost.sql" in p for p in g.check_shards(reps, NAMES)))

    def test_shards_disagreeing_on_n_fail(self):
        reps = _reports(3)
        reps[0]["shard"] = [1, 4]
        self.assertTrue(g.check_shards(reps, NAMES))

    def test_the_report_round_trips_through_the_log_dir(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            for i, r in enumerate(_reports(3), 1):
                sub = os.path.join(d, "fixture-gate-logs-%d" % i, "fixtures-%d" % i)
                os.makedirs(sub)
                g.write_report(sub, tuple(r["shard"]), r["labels"])
            self.assertEqual(g.check_shards(g.read_reports(d), NAMES), [])


if __name__ == "__main__":
    unittest.main()
