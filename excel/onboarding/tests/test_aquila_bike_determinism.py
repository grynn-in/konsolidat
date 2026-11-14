"""The Aquila Bike replica is byte-reproducible: expected.json is a pure function of inputs.json."""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ONB = os.path.dirname(HERE)
COMMITTED = os.path.join(ONB, "examples", "aquila-bike", "model", "expected.json")

SCRIPT = """
import sys
sys.path.insert(0, %r)
import aquila_bike_offline as ab
d = ab.load_inputs()
ab.MODEL_DIR = sys.argv[1]
ab.Offline(d).run().dump()
""" % ONB


def regenerate(hashseed):
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, PYTHONHASHSEED=str(hashseed))
        subprocess.run([sys.executable, "-c", SCRIPT, tmp], check=True, env=env, capture_output=True)
        with open(os.path.join(tmp, "expected.json"), "rb") as f:
            return f.read()


class Determinism(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a, cls.b = regenerate(1), regenerate(2)

    def test_two_regenerations_are_byte_identical(self):
        self.assertEqual(self.a, self.b)

    def test_committed_expected_json_is_a_fresh_regeneration(self):
        with open(COMMITTED, "rb") as f:
            self.assertEqual(f.read(), self.a)

    def test_no_negative_zero_and_no_zero_amount_rows(self):
        text = self.a.decode()
        self.assertNotIn("-0.0,", text)
        self.assertNotIn("-0.0\n", text)
        import json
        for row in json.loads(text)["cta"]:
            self.assertNotEqual(row["amount"], 0)


if __name__ == "__main__":
    unittest.main()
