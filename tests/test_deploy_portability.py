"""deploy.sh step 5 must run on a Linux host (konsolidat#239).

`deploy.sh` created the dbt log with `mktemp -t konsolidat-dbt`. GNU coreutils
requires a `-t` template to end in at least three `X`s; BSD/macOS does not. So
the line worked on a developer's Mac and failed on every Linux host with
`mktemp: too few X's in template`, and step 5 of 5 — the dbt build — never ran
on a server.

Measured 22 September 2026 on `debian:bookworm-slim`: `mktemp -t
konsolidat-dbt` exits 1, `mktemp -t konsolidat-dbt.XXXXXX` exits 0.

The tests below are the PRD's acceptance criteria 1-4
(`docs/prd/PRD-DEPLOY-STEP5-PORTABILITY.md`). Criteria 3 and 4 are guards, not
wishes: the issue proposed `set -o pipefail`, which would make `set -e` exit at
the `docker compose ... | tee` pipeline itself, so the `${PIPESTATUS[0]}` read
and the failure classification konsolidat#139 added would never run.
"""
import os
import re
import shlex
import subprocess
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEPLOY_SH = os.path.join(PROJECT_ROOT, "deploy.sh")

# A template is portable when it ends in a run of at least three X's.
PORTABLE_TEMPLATE = re.compile(r"X{3,}$")

# Options that swallow the word after them, so that word is a directory and
# not a template.
OPTIONS_TAKING_A_VALUE = {"-p", "--tmpdir", "--suffix"}


def _shell_scripts():
    """Every *.sh tracked in the repo, .git excluded."""
    for root, dirs, names in os.walk(PROJECT_ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".venv")]
        for name in sorted(names):
            if name.endswith(".sh"):
                yield os.path.join(root, name)


def _mktemp_templates(text):
    """Yield (template, line_number) for every mktemp call in a shell script.

    The words after `mktemp` are cut at the first shell metacharacter that ends
    the command (`$(mktemp ...)` leaves a trailing paren), split as the shell
    would split them, and the non-option words are the templates. A bare
    `mktemp` with no template is portable and yields nothing.
    """
    for n, line in enumerate(text.splitlines(), 1):
        for match in re.finditer(r"\bmktemp\b", line):
            rest = line[match.end():]
            rest = re.split(r"[)|;&><`]", rest, maxsplit=1)[0]
            try:
                words = shlex.split(rest)
            except ValueError:
                words = rest.split()
            skip_next = False
            for word in words:
                if skip_next:
                    skip_next = False
                    continue
                if word.startswith("-"):
                    if word in OPTIONS_TAKING_A_VALUE:
                        skip_next = True
                    continue
                yield word, n


def _is_gnu_mktemp():
    """True when the host's mktemp is GNU coreutils. BSD mktemp has no --version."""
    try:
        result = subprocess.run(
            ["mktemp", "--version"],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0 and "GNU coreutils" in result.stdout


def _deploy_sh():
    with open(DEPLOY_SH) as f:
        return f.read()


class EveryTemplateIsPortable(unittest.TestCase):
    """Acceptance criterion 1 — a static scan of the whole repo, not just deploy.sh.

    Nothing but deploy.sh calls mktemp today; this covers any future caller.
    """

    def test_every_mktemp_template_in_every_shell_script_ends_in_three_xs(self):
        offenders = []
        scanned = 0
        for path in _shell_scripts():
            scanned += 1
            with open(path) as f:
                text = f.read()
            for template, n in _mktemp_templates(text):
                if not PORTABLE_TEMPLATE.search(template):
                    rel = os.path.relpath(path, PROJECT_ROOT)
                    offenders.append("%s:%d: %s" % (rel, n, template))
        self.assertGreater(scanned, 0, "found no *.sh files to scan")
        self.assertEqual(
            [],
            offenders,
            "GNU coreutils refuses a template with fewer than three X's "
            "('too few X's in template'), so these fail on every Linux host:\n"
            + "\n".join(offenders),
        )


class TheRealTemplateWorksOnGnuCoreutils(unittest.TestCase):
    """Acceptance criterion 2 — behavioural, and only meaningful on GNU coreutils.

    The check runs the mktemp line deploy.sh actually contains and asserts it
    creates a file. On a BSD/macOS host the check cannot fail — BSD mktemp
    accepts a template with no X's — so it is skipped there, declared rather
    than silently passing. Run it on Linux, or in CI, or in a container:
    `docker run --rm debian:bookworm-slim`.
    """

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_the_line_deploy_sh_uses_creates_a_file(self):
        lines = [
            line.strip()
            for line in _deploy_sh().splitlines()
            if "mktemp" in line and not line.lstrip().startswith("#")
        ]
        self.assertEqual(1, len(lines), "expected exactly one mktemp call: %r" % lines)
        # `set -e` is what deploy.sh:14 sets, and it makes a failed assignment
        # abort here too, so the assertion below reports mktemp's own message
        # rather than an empty path from a script that carried on.
        result = subprocess.run(
            ["bash", "-c", 'set -e\n' + lines[0] + '\nprintf "%s" "$DBT_LOG"'],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            0,
            result.returncode,
            "the mktemp line failed on GNU coreutils: %s" % result.stderr.strip(),
        )
        path = result.stdout.strip()
        self.addCleanup(lambda: os.path.exists(path) and os.remove(path))
        self.assertTrue(path, "the mktemp line printed no path")
        self.assertTrue(os.path.isfile(path), "mktemp created no file at %r" % path)


class ExitHandlingIsUnchanged(unittest.TestCase):
    """Acceptance criteria 3 and 4 — the fix must not touch step 5's exit handling."""

    def test_deploy_sh_still_sets_set_e(self):
        self.assertRegex(_deploy_sh(), r"(?m)^set -e\b")

    def test_deploy_sh_does_not_set_pipefail(self):
        hits = [
            "%d: %s" % (n, line.strip())
            for n, line in enumerate(_deploy_sh().splitlines(), 1)
            if "pipefail" in line and not line.lstrip().startswith("#")
        ]
        self.assertEqual(
            [],
            hits,
            "pipefail plus set -e would exit at the `dbt_init | tee` pipeline, so "
            "the PIPESTATUS read and the failure classification (konsolidat#139) "
            "would never run:\n" + "\n".join(hits),
        )

    def test_step_5_still_reads_pipestatus_zero(self):
        self.assertIn("${PIPESTATUS[0]}", _deploy_sh())


if __name__ == "__main__":
    unittest.main()
