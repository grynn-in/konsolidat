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


if __name__ == "__main__":
    unittest.main()
