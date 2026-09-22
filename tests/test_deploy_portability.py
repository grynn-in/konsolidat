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


# The one shape this guard understands: VAR=$(mktemp ...) or VAR="$(mktemp ...)",
# which is what deploy.sh:395 is. The mktemp command is captured on its own so it
# can be run alone — never the whole line. An earlier version ran the line
# verbatim, which would have executed `rm -rf "$SCRATCH"/*  # made with mktemp -d`
# with SCRATCH unset. A line that mentions mktemp in any other shape is refused
# loudly below rather than skipped.
_ASSIGNED_MKTEMP = re.compile(
    r"""^[A-Za-z_][A-Za-z0-9_]*=      # VAR=
        "?\$\(\s*(mktemp\b[^()]*?)\s*\)"?$   # $(mktemp ...) or "$(mktemp ...)"
    """,
    re.VERBOSE,
)


def _mktemp_lines():
    """(line number, line) for each non-comment line of deploy.sh calling mktemp."""
    for n, line in enumerate(_deploy_sh().splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if re.search(r"\bmktemp\b", stripped):
            yield n, stripped


def _mktemp_command(line):
    """The bare `mktemp ...` command in an assignment, or None."""
    match = _ASSIGNED_MKTEMP.match(line)
    return match.group(1) if match else None


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

    def test_every_mktemp_line_is_a_shape_this_guard_understands(self):
        """No silent pass: a call this guard cannot run must fail, not vanish."""
        unknown = [
            "deploy.sh:%d: %s" % (n, line)
            for n, line in _mktemp_lines()
            if _mktemp_command(line) is None
        ]
        self.assertEqual(
            [],
            unknown,
            "this guard runs `VAR=$(mktemp ...)` and nothing else. Extend it "
            "for these, or keep the call in that shape:\n" + "\n".join(unknown),
        )

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_every_mktemp_call_succeeds_on_gnu_coreutils(self):
        """konsolidat#239: the bug was a non-zero exit, so run it and look.

        Each call is run twice: once with TMPDIR set, once with it removed. A
        template written `"${TMPDIR}/x.XXXXXX"` without the `:-` default would
        pass the first and fail the second as `mktemp /x.XXXXXX`, which is #239
        again on a host that does not set TMPDIR.

        Skipped on a Mac, where BSD mktemp accepts a template with no X's and
        the check cannot fail. It runs in CI, which is ubuntu.
        """
        for n, line in _mktemp_lines():
            command = _mktemp_command(line)
            if command is None:
                continue  # reported by the test above
            for label in ("TMPDIR set", "TMPDIR unset"):
                with self.subTest(line=n, command=command, environment=label):
                    with tempfile.TemporaryDirectory() as tmp:
                        env = dict(os.environ)
                        if label == "TMPDIR set":
                            env["TMPDIR"] = tmp
                        else:
                            env.pop("TMPDIR", None)
                        result = subprocess.run(
                            ["bash", "-c", command],
                            capture_output=True,
                            text=True,
                            timeout=30,
                            cwd=tmp,
                            env=env,
                        )
                        self.assertEqual(
                            0,
                            result.returncode,
                            "deploy.sh:%d (%s) failed on GNU coreutils: %s"
                            % (n, label, result.stderr.strip() or "(no stderr)"),
                        )
                        path = result.stdout.strip()
                        self.assertTrue(path, "mktemp printed no path")
                        self.addCleanup(
                            lambda p=path: os.path.exists(p) and os.remove(p)
                        )
                        self.assertTrue(
                            os.path.isfile(path), "mktemp created no file at %r" % path
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
        # The option as the shell spells it, before any `#`, so an explanatory
        # comment ("deliberately not pipefail, see #139") is not a failure.
        setting = re.compile(r"^[^#\n]*\bset\s+-[a-zA-Z]*o\s+pipefail\b")
        hits = [
            "%d: %s" % (n, line.strip())
            for n, line in enumerate(_deploy_sh().splitlines(), 1)
            if setting.match(line)
        ]
        self.assertEqual([], hits, "pipefail would skip the failure classification:\n" + "\n".join(hits))

    def test_step_5_still_reads_pipestatus_zero(self):
        self.assertIn("${PIPESTATUS[0]}", _deploy_sh())


if __name__ == "__main__":
    unittest.main()
