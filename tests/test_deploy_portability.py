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

`TheParserFindsOnlyRealTemplates` and `TheScanIsOfTrackedFilesOnly` pin the
parser findings of the konsolidat#242 review; each test names the finding it
closes.
"""
import collections
import os
import re
import shutil
import subprocess
import tempfile
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEPLOY_SH = os.path.join(PROJECT_ROOT, "deploy.sh")

# A template is portable when it ends in a run of at least three X's.
PORTABLE_TEMPLATE = re.compile(r"X{3,}$")

# Options that swallow the word after them, so that word is a value and not a
# template. `--tmpdir` is deliberately absent: GNU documents `--tmpdir[=DIR]`,
# an OPTIONAL value, so a bare `--tmpdir` leaves the next word as the template
# (konsolidat#242 F6). `--tmpdir=DIR` is one word and is skipped as an option.
OPTIONS_TAKING_A_VALUE = {"-p", "--suffix"}

# What ends a simple command, outside quotes. A redirection (`<`, `>`) and a
# word-initial `#` end it too, and are handled separately because each one also
# decides what to do with the word being built.
END_OF_COMMAND = ";&|\n"

# `value` is the word as the shell would expand its quoting: what the X-suffix
# check reads. `source` is the word exactly as written, quotes included: what
# the behavioural test hands back to bash, so `"${TMPDIR:-/tmp}/x.XXXXXX"` is
# re-run with its expansion intact.
Template = collections.namedtuple("Template", "value source line")


def _tracked_shell_scripts():
    """Every *.sh git has, or None when git cannot answer."""
    try:
        result = subprocess.run(
            ["git", "-C", PROJECT_ROOT, "ls-files", "-z", "--", "*.sh"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return [os.path.join(PROJECT_ROOT, p) for p in result.stdout.split("\0") if p]


def _walk_shell_scripts(root):
    """The fallback for a tree with no usable git: *.sh, minus what git ignores.

    `docker/frappe/konsol` is the deploy-owned checkout of another repo, which
    this project forbids editing, so an offender there is not actionable. A
    `name 2.sh` is an iCloud duplicate of a file already scanned.
    """
    vendored = os.path.join(root, "docker", "frappe", "konsol")
    for parent, dirs, names in os.walk(root):
        dirs[:] = [
            d
            for d in dirs
            if d not in (".git", "node_modules", ".venv")
            and os.path.join(parent, d) != vendored
        ]
        for name in sorted(names):
            if name.endswith(".sh") and not name.endswith(" 2.sh"):
                yield os.path.join(parent, name)


def _shell_scripts():
    """Every *.sh tracked in the repo (konsolidat#242 F7).

    Tracked, not "on disk": the walk picked up the deploy-owned checkout at
    `docker/frappe/konsol` and would pick up iCloud `* 2.sh` copies. The walk
    survives only as the fallback for a tree without git, e.g. a source tarball
    unpacked in a container.
    """
    tracked = _tracked_shell_scripts()
    if tracked is not None:
        return sorted(tracked)
    return sorted(_walk_shell_scripts(PROJECT_ROOT))


def _read_double_quoted(text, i):
    """Read the "..." starting at `i`; return (value, index after the close).

    An unterminated quote is read to the end of the line rather than discarded:
    whatever it yields shows up as an offender, instead of a call site
    disappearing from the scan without a word.
    """
    i += 1
    out = ""
    while i < len(text):
        c = text[i]
        if c == "\\":
            out += text[i + 1:i + 2]
            i += 2
            continue
        if c == '"':
            return out, i + 1
        if text.startswith("$(", i) or c == "`":
            inner, i = _read_substitution(text, i)
            out += inner
            continue
        out += c
        i += 1
    return out, len(text)


def _read_substitution(text, i):
    """Read the `$(...)` or backtick substitution at `i`, nesting and all.

    Returns it verbatim: a substitution is opaque to this scan, it only has to
    stay inside the word it belongs to (konsolidat#242 F2).
    """
    if text[i] == "`":
        j = text.find("`", i + 1)
        if j < 0:
            return text[i:], len(text)
        return text[i:j + 1], j + 1
    depth = 0
    j = i
    while j < len(text):
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == "'":
            k = text.find("'", j + 1)
            if k < 0:
                break
            j = k + 1
            continue
        if c == '"':
            _, j = _read_double_quoted(text, j)
            continue
        if text.startswith("$(", j):
            depth += 1
            j += 2
            continue
        if c == "(":
            depth += 1
            j += 1
            continue
        if c == ")":
            depth -= 1
            j += 1
            if depth == 0:
                return text[i:j], j
            continue
        j += 1
    return text[i:], len(text)


def _split_command(rest):
    """Split the text after `mktemp` into the words of that one command.

    Quoting is honoured, so a `$(...)` or a quoted string stays one word, and
    the split stops at what really ends the command: an unquoted `;`, `&`, `|`,
    a redirection, a word-initial `#`, or the `)` that closes an enclosing
    `$(`. Cutting at the first metacharacter instead (the form this replaces)
    turned the `2` of `2>` into a template and `"$(dirname "$x")/f.XXXXXX"`
    into two (konsolidat#242 F2).
    """
    words = []
    value = ""
    start = None
    i = 0
    end = len(rest)
    while i < len(rest):
        c = rest[i]
        if c in " \t":
            if start is not None:
                words.append((value, rest[start:i]))
                value, start = "", None
            i += 1
            continue
        if c in END_OF_COMMAND or c == ")":
            end = i
            break
        if c in "<>":
            # A redirection ends the command. An all-digit word glued to it is
            # the file descriptor, not an argument.
            if start is not None and value.isdigit():
                start = None
            end = i
            break
        if c == "#" and start is None:
            end = i
            break
        if start is None:
            start = i
        if c == "\\":
            value += rest[i + 1:i + 2]
            i += 2
            continue
        if c == "'":
            j = rest.find("'", i + 1)
            if j < 0:
                value += rest[i + 1:]
                i = len(rest)
                continue
            value += rest[i + 1:j]
            i = j + 1
            continue
        if c == '"':
            quoted, i = _read_double_quoted(rest, i)
            value += quoted
            continue
        if rest.startswith("$(", i) or c == "`":
            inner, i = _read_substitution(rest, i)
            value += inner
            continue
        value += c
        i += 1
    if start is not None:
        words.append((value, rest[start:end]))
    return words


def _strip_comment(line):
    """Drop a `#` comment, quotes honoured.

    The sibling checks below have always ignored comments; the scan did not, so
    documenting the superseded `mktemp -t konsolidat-dbt` beside the fix — the
    very next likely edit — reddened CI (konsolidat#242 F3). A `#` inside a
    word, as in `${x#/tmp/}`, is not a comment.
    """
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = line.find("'", i + 1)
            if j < 0:
                return line
            i = j + 1
            continue
        if c == '"':
            _, i = _read_double_quoted(line, i)
            continue
        if c == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i]
        i += 1
    return line


def _mktemp_templates(text):
    """Yield a Template for every argument of every mktemp call in a script.

    Option words are skipped, and so is the value of an option that takes one.
    A bare `mktemp` with no template is portable and yields nothing.
    """
    for n, line in enumerate(text.splitlines(), 1):
        line = _strip_comment(line)
        for match in re.finditer(r"\bmktemp\b", line):
            skip_next = False
            for value, source in _split_command(line[match.end():]):
                if skip_next:
                    skip_next = False
                    continue
                if value.startswith("-"):
                    if value in OPTIONS_TAKING_A_VALUE:
                        skip_next = True
                    continue
                yield Template(value, source, n)


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


def _all_templates():
    """Every template in every tracked shell script, with where it came from."""
    found = []
    for path in _shell_scripts():
        with open(path) as f:
            text = f.read()
        rel = os.path.relpath(path, PROJECT_ROOT)
        for template in _mktemp_templates(text):
            found.append((rel, template))
    return found


def _deploy_sh():
    with open(DEPLOY_SH) as f:
        return f.read()


class EveryTemplateIsPortable(unittest.TestCase):
    """Acceptance criterion 1 — a static scan of the whole repo, not just deploy.sh.

    Nothing but deploy.sh calls mktemp today; this covers any future caller.
    """

    def test_every_mktemp_template_in_every_shell_script_ends_in_three_xs(self):
        scripts = _shell_scripts()
        self.assertGreater(len(scripts), 0, "found no *.sh files to scan")
        offenders = [
            "%s:%d: %s" % (rel, template.line, template.value)
            for rel, template in _all_templates()
            if not PORTABLE_TEMPLATE.search(template.value)
        ]
        self.assertEqual(
            [],
            offenders,
            "GNU coreutils refuses a template with fewer than three X's "
            "('too few X's in template'), so these fail on every Linux host:\n"
            + "\n".join(offenders),
        )


class EveryTemplateCreatesAFileOnGnuCoreutils(unittest.TestCase):
    """Acceptance criterion 2 — behavioural, and only meaningful on GNU coreutils.

    Every template the scan finds, in every tracked shell script, is handed
    back to bash and has to create a file. That is the whole check: it does not
    care what variable the result is assigned to, nor how many mktemp calls a
    script makes — the form this replaces asserted `exactly one` call in
    deploy.sh and hardcoded `$DBT_LOG`, so a second portable call reddened the
    suite and renaming the variable failed with a message blaming mktemp
    (konsolidat#242 F8).

    On a BSD/macOS host the check cannot fail — BSD mktemp accepts a template
    with no X's — so it is skipped there, declared rather than silently
    passing. Run it on Linux, or in CI, or in a container:
    `docker run --rm debian:bookworm-slim`.
    """

    @unittest.skipUnless(
        _is_gnu_mktemp(),
        "host mktemp is not GNU coreutils; a too-short template cannot fail here",
    )
    def test_every_template_in_every_tracked_script_creates_a_file(self):
        templates = _all_templates()
        self.assertGreater(
            len(templates),
            0,
            "found no mktemp templates to run; if deploy.sh no longer calls "
            "mktemp, delete this test rather than letting it pass on nothing",
        )
        for rel, template in templates:
            with self.subTest(script=rel, line=template.line, template=template.source):
                # `set -e` is what deploy.sh:14 sets. The substitution is
                # assigned on its own line, as deploy.sh assigns it: a failed
                # substitution aborts an assignment under `set -e`, so the
                # assertion below reports mktemp's own message. Inlined into
                # `printf "%s" "$(mktemp ...)"` it would not — printf still
                # exits 0 — and the failure would read as an empty path.
                script = (
                    "set -e\npath=$(mktemp "
                    + template.source
                    + ')\nprintf "%s" "$path"'
                )
                result = subprocess.run(
                    ["bash", "-c", script],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                path = result.stdout.strip()
                if path:
                    self.addCleanup(lambda p=path: os.path.exists(p) and os.remove(p))
                self.assertEqual(
                    0,
                    result.returncode,
                    "%s:%d: mktemp %s failed on GNU coreutils: %s"
                    % (rel, template.line, template.source, result.stderr.strip()),
                )
                self.assertTrue(
                    path, "%s:%d: mktemp printed no path" % (rel, template.line)
                )
                self.assertTrue(
                    os.path.isfile(path),
                    "%s:%d: mktemp created no file at %r" % (rel, template.line, path),
                )


class TheParserFindsOnlyRealTemplates(unittest.TestCase):
    """Regression tests for the parser findings of the konsolidat#242 review.

    Each one feeds the reviewer's exact input to `_mktemp_templates` and pins
    the answer the parser gave before the fix.
    """

    def templates(self, line):
        return [t[0] for t in _mktemp_templates(line)]

    def test_f2_the_fd_of_a_redirection_is_not_a_template(self):
        # Before the fix the split at the first metacharacter left the `2` of
        # `2>` behind, and `2` has no X's, so a correct line reddened CI.
        self.assertEqual(
            ["foo.XXXXXX"],
            self.templates("LOG=$(mktemp -t foo.XXXXXX 2>/dev/null)"),
        )

    def test_f2_a_nested_command_substitution_is_one_template(self):
        # Before the fix this yielded `"$(dirname` and `"$x"` — two spurious
        # offenders — and lost the real template.
        self.assertEqual(
            ['$(dirname "$x")/foo.XXXXXX'],
            self.templates('mktemp "$(dirname "$x")/foo.XXXXXX"'),
        )

    def test_f2_a_word_before_a_redirection_is_still_a_template(self):
        self.assertEqual(["foo.XXXXXX"], self.templates("mktemp foo.XXXXXX>/dev/null"))

    def test_f2_the_command_ends_at_a_pipe_or_a_semicolon(self):
        self.assertEqual(
            ["foo.XXXXXX"], self.templates("mktemp foo.XXXXXX | tee bar.log")
        )
        self.assertEqual(["foo.XXXXXX"], self.templates("mktemp foo.XXXXXX; echo baz"))

    def test_f3_a_commented_out_mktemp_is_not_scanned(self):
        # Documenting the superseded form beside the fix must not break CI.
        self.assertEqual(
            [],
            self.templates('# old form was: DBT_LOG="$(mktemp -t konsolidat-dbt)"'),
        )

    def test_f3_a_trailing_comment_is_not_scanned(self):
        self.assertEqual(
            [], self.templates("    echo hi  # was: mktemp -t konsolidat-dbt")
        )

    def test_f3_a_comment_after_a_real_call_is_not_a_template(self):
        self.assertEqual(
            ["foo.XXXXXX"],
            self.templates("mktemp foo.XXXXXX  # was konsolidat-dbt"),
        )

    def test_f3_a_hash_inside_a_word_is_not_a_comment(self):
        self.assertEqual(
            ["${x#/tmp/}.XXXXXX"],
            self.templates("mktemp ${x#/tmp/}.XXXXXX"),
        )

    def test_f6_a_bare_tmpdir_does_not_swallow_the_template(self):
        # GNU documents `--tmpdir[=DIR]`: the value is optional, so a bare
        # `--tmpdir` leaves the next word as the template. Before the fix this
        # yielded nothing and the guard passed a line GNU rejects.
        self.assertEqual(
            ["konsolidat-dbt"],
            self.templates("mktemp --tmpdir konsolidat-dbt"),
        )

    def test_f6_tmpdir_with_a_value_is_still_one_word(self):
        self.assertEqual(
            ["foo.XXXXXX"],
            self.templates("mktemp --tmpdir=/var/tmp foo.XXXXXX"),
        )

    def test_f6_options_that_really_take_a_value_still_swallow_it(self):
        self.assertEqual(["foo.XXXXXX"], self.templates("mktemp -p /var/tmp foo.XXXXXX"))
        self.assertEqual(
            ["foo.XXXXXX"], self.templates("mktemp --suffix .log foo.XXXXXX")
        )

    def test_a_bare_mktemp_yields_nothing(self):
        self.assertEqual([], self.templates("LOG=$(mktemp)"))

    def test_the_source_of_a_template_keeps_its_quoting(self):
        # What the behavioural test re-runs, so the expansion survives.
        line = 'DBT_LOG="$(mktemp "${TMPDIR:-/tmp}/konsolidat-dbt.XXXXXX")"'
        self.assertEqual(
            ['"${TMPDIR:-/tmp}/konsolidat-dbt.XXXXXX"'],
            [t.source for t in _mktemp_templates(line)],
        )

    def test_the_line_of_a_template_is_reported(self):
        self.assertEqual(
            [3], [t.line for t in _mktemp_templates("a\nb\nmktemp foo.XXXXXX\n")]
        )


class TheScanIsOfTrackedFilesOnly(unittest.TestCase):
    """F7 — the docstring says "tracked in the repo"; the scan must mean it."""

    def test_f7_the_scan_matches_git_ls_files(self):
        try:
            result = subprocess.run(
                ["git", "-C", PROJECT_ROOT, "ls-files", "-z", "--", "*.sh"],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            # A source tarball unpacked in a container has no git, and the
            # scan falls back to the walk there. Declared, not silent.
            self.skipTest("git cannot list this tree (%s); the scan falls back "
                          "to the walk, which the test below covers" % exc)
        if result.returncode != 0:
            self.skipTest("git cannot list this tree (%s); the scan falls back "
                          "to the walk, which the test below covers"
                          % result.stderr.strip())
        tracked = sorted(
            os.path.join(PROJECT_ROOT, p) for p in result.stdout.split("\0") if p
        )
        self.assertEqual(tracked, sorted(_shell_scripts()))

    def test_f7_the_fallback_walk_skips_vendored_and_icloud_copies(self):
        # The walk picked up docker/frappe/konsol/scripts/hot-deploy-exec.sh,
        # a checkout of another repo this project forbids editing, so an
        # offender there could not be fixed.
        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, True)
        for rel in (
            "deploy.sh",
            "deploy 2.sh",
            "docker/frappe/konsol/scripts/hot-deploy-exec.sh",
            "scripts/dbt-init.sh",
        ):
            path = os.path.join(root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write("#!/bin/bash\n")
        self.assertEqual(
            [
                os.path.join(root, "deploy.sh"),
                os.path.join(root, "scripts", "dbt-init.sh"),
            ],
            sorted(_walk_shell_scripts(root)),
        )


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
