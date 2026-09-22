"""deploy.sh step 5 must run on a Linux host (konsolidat#239).

`deploy.sh` created the dbt log with `mktemp -t konsolidat-dbt`. GNU coreutils
requires a `-t` template to end in at least three `X`s; BSD/macOS does not. So
the line worked on a developer's Mac and failed on every Linux host with
`mktemp: too few X's in template`, and step 5 of 5 — the dbt build — never ran
on a server.

**This test runs the lines rather than reading them.** An earlier version
parsed shell to decide which words were mktemp templates: which quotes were
open, where a comment began, where `$( )` nested, which options took a value.
Two review rounds found nine defects in that parser and none in the one-line
fix it guarded. Shell syntax has no end, so the parser was deleted. What is
left executes `deploy.sh`'s own mktemp call on a GNU host and asks the only
question that matters: does it succeed?

Two consequences, stated rather than hidden:

- The call must be on one line. A `\\`-continued `mktemp` will fail this test
  with a shell syntax error, not a wrong answer.
- The call is run with no other script state, so a future call using a variable
  set elsewhere in `deploy.sh` will fail here. That is a loud failure telling
  you to give this test that variable, not a silent pass.

Neither applies to the single call `deploy.sh` has today.
"""
import os
import re
import subprocess
import tempfile
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEPLOY_SH = os.path.join(PROJECT_ROOT, "deploy.sh")


def _deploy_sh():
    with open(DEPLOY_SH) as f:
        return f.read()


def _mktemp_lines():
    """(line number, line) for each non-comment line of deploy.sh calling mktemp."""
    for n, line in enumerate(_deploy_sh().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if re.search(r"\bmktemp\b", stripped):
            yield n, stripped


def _is_gnu_mktemp():
    """True when the host's mktemp is GNU coreutils. BSD mktemp has no --version."""
    try:
        result = subprocess.run(
            ["mktemp", "--version"], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0 and "GNU coreutils" in result.stdout


class Step5CreatesItsLogFile(unittest.TestCase):
    def test_deploy_sh_calls_mktemp(self):
        """Vacuity guard: the test below is worthless if it finds no calls."""
        self.assertTrue(
            list(_mktemp_lines()),
            "no mktemp call found in %s; this test has stopped testing anything"
            % DEPLOY_SH,
        )

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_every_mktemp_call_succeeds_on_gnu_coreutils(self):
        """konsolidat#239: the bug was a non-zero exit, so run it and look.

        Skipped on a Mac, where BSD mktemp accepts a template with no X's and
        the check cannot fail. It runs in CI, which is ubuntu.
        """
        for n, line in _mktemp_lines():
            with self.subTest(line=n, source=line):
                with tempfile.TemporaryDirectory() as tmp:
                    result = subprocess.run(
                        ["bash", "-c", "set -e\n" + line],
                        capture_output=True,
                        text=True,
                        timeout=30,
                        cwd=tmp,
                        env=dict(os.environ, TMPDIR=tmp),
                    )
                    self.assertEqual(
                        0,
                        result.returncode,
                        "deploy.sh:%d failed on GNU coreutils: %s"
                        % (n, result.stderr.strip() or "(no stderr)"),
                    )


class ExitHandlingIsUnchanged(unittest.TestCase):
    """The fix must not touch step 5's exit handling.

    konsolidat#239 suggested `set -o pipefail`. It must not be added: step 5
    reads `${PIPESTATUS[0]}` so that `docker compose ... | tee` reports dbt's
    status rather than tee's, and then tells a compilation error (abort the
    deploy) from data-quality failures on demo data (tolerate). Under pipefail
    with `set -e` the script exits at the pipeline and that classification never
    runs — the bug konsolidat#139 was filed for.
    """

    def test_deploy_sh_still_sets_set_e(self):
        self.assertRegex(_deploy_sh(), r"(?m)^set -e\b")

    def test_deploy_sh_does_not_set_pipefail(self):
        hits = [
            "%d: %s" % (n, line.strip())
            for n, line in enumerate(_deploy_sh().splitlines(), 1)
            if "pipefail" in line and not line.lstrip().startswith("#")
        ]
        self.assertEqual([], hits, "pipefail would skip the failure classification:\n" + "\n".join(hits))

    def test_step_5_still_reads_pipestatus_zero(self):
        self.assertIn("${PIPESTATUS[0]}", _deploy_sh())


if __name__ == "__main__":
    unittest.main()
