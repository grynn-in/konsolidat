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
question that matters: does it succeed, and where did the file land?

**When this guard cannot understand a line, it refuses loudly rather than
parsing harder.** A red on an unusual-but-correct line is annoying; a green on
a broken line, or a guard that executes something it should not, is what this
PR kept producing. Every refusal below is named in
`test_every_mktemp_line_is_a_shape_this_guard_understands`, so nothing is
skipped silently.

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
import sys
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
    """(command, None) when the line is the shape this guard runs, else (None, why).

    There is no third answer. A line this guard cannot run is reported by name
    in the shape test below; it is never skipped.
    """
    match = _ASSIGNED_MKTEMP.match(line)
    if match is None:
        return None, "not `VAR=$(mktemp ...)`, the only shape this guard runs"
    return match.group(1), None


def _remove(path):
    """Delete a file or directory mktemp made, whichever it is."""
    if os.path.isdir(path):
        os.rmdir(path)
    elif os.path.exists(path):
        os.remove(path)


def _default_temp_directory(env):
    """Where a temp file lands under `env`, asked of a child Python.

    Not `tempfile.gettempdir()` in this process: a Mac always has TMPDIR set and
    gettempdir() caches its answer, so this process cannot say where a child
    with TMPDIR removed would write.
    """
    result = subprocess.run(
        [sys.executable, "-c", "import tempfile; print(tempfile.gettempdir())"],
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(
            "could not ask Python where temp files go: %s"
            % (result.stderr.strip() or "(no stderr)")
        )
    return result.stdout.strip()


def _check_mktemp_call(command, set_tmpdir):
    """Run one mktemp command; return the reasons it fails, or [] when it passes.

    With `set_tmpdir` the command runs with TMPDIR pointing at a scratch
    directory; without it, TMPDIR is removed from the environment. Whatever the
    command creates is deleted before returning.
    """
    with tempfile.TemporaryDirectory() as scratch:
        env = dict(os.environ)
        if set_tmpdir:
            env["TMPDIR"] = scratch
        else:
            for name in ("TMPDIR", "TEMP", "TMP"):
                env.pop(name, None)
        result = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            text=True,
            timeout=30,
            cwd=scratch,
            env=env,
        )
        if result.returncode != 0:
            return [
                "exited %d: %s"
                % (result.returncode, result.stderr.strip() or "(no stderr)")
            ]
        path = result.stdout.strip()
        if not path:
            return ["printed no path"]
        reasons = []
        try:
            # `mktemp -d` is a directory and equally legitimate; assert only
            # that the path exists, and clean up either kind. Asserting
            # isfile() failed a correct `-d` line and then raised in cleanup.
            if not os.path.exists(path):
                reasons.append("created nothing at %r" % path)
        finally:
            _remove(path)
        return reasons


def _is_gnu_mktemp():
    """True when the host's mktemp is GNU coreutils. BSD mktemp has no --version."""
    try:
        result = subprocess.run(
            ["mktemp", "--version"], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0 and "GNU coreutils" in result.stdout


def _sets_pipefail(line):
    """True when this line of shell turns pipefail on."""
    # The option as the shell spells it, before any `#`, so an explanatory
    # comment ("deliberately not pipefail, see #139") is not a failure.
    # `pipefail` after ANY `-o`, not only the first option group:
    # `set -o errexit -o pipefail` enables it just as `set -eo pipefail` does.
    setting = re.compile(
        r"^[^#\n]*\bset\s+(?:-[a-zA-Z]*\s+|-o\s+\w+\s+)*-[a-zA-Z]*o\s+pipefail\b"
    )
    return bool(setting.match(line))


def _pipefail_lines(text):
    """"<n>: <line>" for each line of `text` that turns pipefail on."""
    return [
        "%d: %s" % (n, line.strip())
        for n, line in enumerate(text.splitlines(), 1)
        if _sets_pipefail(line)
    ]


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
        unknown = []
        for n, line in _mktemp_lines():
            command, why = _mktemp_command(line)
            if command is None:
                unknown.append("deploy.sh:%d: %s\n    refused: %s" % (n, line, why))
        self.assertEqual(
            [],
            unknown,
            "this guard runs `VAR=$(mktemp ...)` and nothing else. Keep the "
            "call in that shape, or extend the guard for these:\n"
            + "\n".join(unknown),
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
            command, _why = _mktemp_command(line)
            if command is None:
                continue  # reported by the test above
            for label, set_tmpdir in (("TMPDIR set", True), ("TMPDIR unset", False)):
                with self.subTest(line=n, command=command, environment=label):
                    reasons = _check_mktemp_call(command, set_tmpdir)
                    self.assertEqual(
                        [],
                        reasons,
                        "deploy.sh:%d (%s): %s" % (n, label, "; ".join(reasons)),
                    )


class TheGuardItself(unittest.TestCase):
    """What the guard does with lines deploy.sh does not have today.

    Every input below is one a reviewer measured against this file. They are
    here so that a future edit to the guard cannot quietly re-accept a broken
    line or re-refuse a correct one.
    """

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_a_template_that_ignores_tmpdir_is_caught(self):
        """`"${TMPDIR}/x"` without the `:-` default is konsolidat#239 again.

        As root, `mktemp "/konsolidat-dbt.XXXXXX"` succeeds and creates the file
        at `/`, so an existence check alone passes. The guard must look at WHERE
        the file landed.
        """
        reasons = _check_mktemp_call(
            'mktemp "${TMPDIR}/konsolidat-dbt-guardcheck.XXXXXX"', set_tmpdir=False
        )
        self.assertTrue(
            reasons,
            "with TMPDIR unset this writes to / (as root) or fails (as anyone "
            "else); the guard accepted it",
        )

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_the_real_line_passes_both_ways(self):
        """The positive control for the test above."""
        for label, set_tmpdir in (("TMPDIR set", True), ("TMPDIR unset", False)):
            with self.subTest(environment=label):
                self.assertEqual(
                    [],
                    _check_mktemp_call(
                        'mktemp "${TMPDIR:-/tmp}/konsolidat-dbt-guardcheck.XXXXXX"',
                        set_tmpdir,
                    ),
                )

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_a_dry_run_call_is_not_failed_for_creating_nothing(self):
        """`mktemp -u` prints a name and creates nothing, which is fair for a
        path `tee` will create."""
        self.assertEqual(
            [],
            _check_mktemp_call(
                'mktemp -u "${TMPDIR:-/tmp}/konsolidat-dbt-guardcheck.XXXXXX"',
                set_tmpdir=True,
            ),
        )

    def test_the_path_is_the_last_line_of_stdout(self):
        """Anything printed before the name is not part of the name.

        Defence in depth: the shape guard refuses a chained capture, so this can
        now only arise from an mktemp that prints a warning of its own first.
        """
        self.assertEqual(
            [],
            _check_mktemp_call(
                'echo "warning: something"; mktemp "$TMPDIR/guardcheck.XXXXXX"',
                set_tmpdir=True,
            ),
        )

    def test_a_capture_carrying_another_command_is_refused(self):
        """The capture is RUN. `$(mktemp -d && chmod 777 /tmp/x)` must not be."""
        for line in (
            "LOG=$(mktemp -d; echo hi)",
            'LOG="$(mktemp -d && chmod 777 /tmp/x)"',
            'LOG="$(mktemp -d || true)"',
            'LOG="$(mktemp -d | tr a b)"',
            'LOG="$(mktemp -d `id`)"',
        ):
            with self.subTest(line=line):
                command, why = _mktemp_command(line)
                self.assertIsNone(
                    command, "this guard would have run %r" % (command,)
                )
                self.assertTrue(why, "a refusal must say why")

    def test_ordinary_assignments_are_understood(self):
        """These are correct shell. Refusing them is a bug in the guard."""
        cases = {
            "LOG=$(mktemp -d)   # scratch": "mktemp -d",
            'export LOG="$(mktemp /tmp/x.XXXXXX)"': "mktemp /tmp/x.XXXXXX",
            'local LOG="$(mktemp /tmp/x.XXXXXX)"': "mktemp /tmp/x.XXXXXX",
            'readonly LOG="$(mktemp /tmp/x.XXXXXX)"': "mktemp /tmp/x.XXXXXX",
        }
        for line, expected in cases.items():
            with self.subTest(line=line):
                self.assertEqual(expected, _mktemp_command(line)[0])

    def test_a_nested_command_substitution_is_refused_by_name(self):
        """Still refused — finding the matching `)` is parsing shell again — but
        the refusal has to say so."""
        command, why = _mktemp_command('LOG="$(mktemp "$(pwd)/x.XXXXXX")"')
        self.assertIsNone(command)
        self.assertIn("nested", why)


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
        hits = _pipefail_lines(_deploy_sh())
        self.assertEqual(
            [],
            hits,
            "pipefail would skip the failure classification:\n" + "\n".join(hits),
        )

    def test_pipefail_guard_matches_every_spelling(self):
        for line in (
            "set -o pipefail",
            "set -eo pipefail",
            "set -e -o pipefail",
            "set -o errexit -o pipefail",
            'if [ -n "$x" ]; then set -o pipefail; fi',
            "for f in a; do set -o pipefail; done",
            "true && set -o pipefail",
        ):
            with self.subTest(line=line):
                self.assertTrue(_sets_pipefail(line))

    def test_pipefail_guard_ignores_the_option_named_in_text(self):
        for line in (
            'echo "never set -o pipefail here"',
            'err "re-run with set -o pipefail to see the first failure"',
            "set -e  # deliberately not pipefail, see #139",
            "# set -o pipefail",
        ):
            with self.subTest(line=line):
                self.assertFalse(_sets_pipefail(line))

    def test_step_5_still_reads_pipestatus_zero(self):
        self.assertIn("${PIPESTATUS[0]}", _deploy_sh())


if __name__ == "__main__":
    unittest.main()
