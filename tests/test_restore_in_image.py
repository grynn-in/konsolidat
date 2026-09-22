"""`bench restore` needs `file(1)` in the image (konsolidat#240).

Frappe shells out to `file` to decide whether a dump is gzipped, at
`frappe/commands/site.py:234` (restore) and `:375` (partial restore). The
image's apt list installed `git curl wget cron mariadb-client`, fonts,
`build-essential`, nodejs, yarn and wkhtmltopdf — not `file` — so `bench
restore` died with `file: command not found`. Measured 22 September 2026 in
the running `konsolidat_backend`: `command -v file` returned nothing.

This is asserted **statically**, by parsing `docker/frappe/Dockerfile` and
reading the package list of the `apt-get install` that already installs
`mariadb-client`. Static is what CI can afford: building the image is
`deploy.sh`'s job and takes minutes, and this repo has no Frappe site in CI.

What it therefore does NOT prove (see the PRD's "Residual" section in
`docs/prd/PRD-RESTORE-IN-IMAGE.md`): that the built image contains
`/usr/bin/file`, that `bench restore` succeeds, or that apt can resolve the
package at build time. It proves only that the list asks for `file`. That the
package provides the binary on this base is proven separately, by hand, on
`python:3.11-slim-bookworm`; the first real image rebuild closes the loop.

The package list is tokenised rather than searched as a substring: the string
"file" occurs in the Dockerfile in `Dockerfile` itself, in `/tmp/wkhtmltox.deb
-o`, and would occur in any future package whose name merely contains it. Only
a whole token counts.

Two properties of that parse are pinned by their own tests below, because both
were wrong once (konsolidat#242): a `#` line is dropped wherever it appears,
including inside a `\`-continued instruction — otherwise a Dockerfile that
merely *mentions* `file` in a comment passes as one that installs it — and the
install command is recognised in its ordinary spellings (`apt` or `apt-get`,
flags either side of the verb, leading `VAR=value`), so an edit to the
Dockerfile cannot turn the acceptance test into a false red.
"""
import os
import re
import shlex
import shutil
import tempfile
import textwrap
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCKERFILE = os.path.join(PROJECT_ROOT, "docker", "frappe", "Dockerfile")
_ENV_ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _logical_lines(path):
    """Yield the Dockerfile's instructions, with `\\`-continuations joined."""
    with open(path) as f:
        raw = f.read()
    joined = []
    buffer = ""
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            # Docker strips a comment line wherever it appears, including
            # inside a `\\`-continued instruction, and the continuation
            # carries on past it. Folding such a line into the instruction
            # turned its words into "packages" (konsolidat#242 F1), which let
            # `test_file_is_installed_alongside_mariadb_client` pass on a
            # Dockerfile that does not install `file` at all.
            continue
        if stripped.endswith("\\"):
            buffer += stripped[:-1].strip() + " "
            continue
        buffer += stripped
        if buffer.strip():
            joined.append(" ".join(buffer.split()))
        buffer = ""
    if buffer.strip():
        joined.append(" ".join(buffer.split()))
    return joined


def _apt_install_packages(package, path=DOCKERFILE):
    """Packages named by the `apt-get install` command that installs `package`.

    Returns the whole token list of that one `&&`-separated command, with the
    `apt-get install` words and every flag dropped, so callers compare whole
    tokens. Returns None when no such command exists. `path` defaults to the
    repo's Dockerfile; the regression tests below point it at a fixture.
    """
    for instruction in _logical_lines(path):
        if not instruction.startswith("RUN "):
            continue
        body = instruction[len("RUN "):]
        for command in body.split("&&"):
            try:
                tokens = shlex.split(command)
            except ValueError:  # unbalanced quoting: not a package list
                continue
            packages = _installed_packages(tokens)
            if packages is not None and package in packages:
                return packages
    return None


def _installed_packages(tokens):
    """The packages of one `apt`/`apt-get install` command, or None.

    Matching only the exact prefix `apt-get install` (konsolidat#242 F9) made
    `apt-get -y install …`, `apt install …` and
    `DEBIAN_FRONTEND=noninteractive apt-get install …` parse as nothing, so a
    legitimate Dockerfile edit failed the tests with "the parse, not the
    Dockerfile, is probably what changed" — a false red. Leading `VAR=value`
    assignments are skipped, `apt` and `apt-get` both count, and flags may sit
    on either side of the `install` verb.
    """
    rest = list(tokens)
    while rest and _ENV_ASSIGNMENT.match(rest[0]):
        rest.pop(0)
    if not rest or rest[0] not in ("apt", "apt-get"):
        return None
    rest = rest[1:]
    if "install" not in rest:
        return None
    # Everything before the verb is a flag or a flag's value, never a package:
    # `apt-get` takes its verb as the first non-option word.
    after = rest[rest.index("install") + 1:]
    return [t for t in after if not t.startswith("-")]


class DockerfileInstallsFile(unittest.TestCase):
    def test_the_apt_command_that_installs_mariadb_client_is_found(self):
        """Guard: the parse must find a real package list, or the next test
        passes for the wrong reason."""
        packages = _apt_install_packages("mariadb-client")
        self.assertIsNotNone(
            packages,
            "no `apt-get install` in %s installs mariadb-client; the parse, "
            "not the Dockerfile, is probably what changed" % DOCKERFILE,
        )
        self.assertIn("curl", packages, "package list parsed, but looks wrong: %r" % (packages,))

    def test_file_is_installed_alongside_mariadb_client(self):
        """konsolidat#240 acceptance criterion 1: `file` is in the same
        `apt-get install` that installs `mariadb-client`."""
        packages = _apt_install_packages("mariadb-client")
        self.assertIsNotNone(packages, "no apt-get install found for mariadb-client")
        self.assertIn(
            "file",
            packages,
            "`file` is not installed; `bench restore` shells out to file(1) "
            "(frappe/commands/site.py:234, :375) and fails with "
            "`file: command not found`. Packages found: %r" % (packages,),
        )


class _FixtureDockerfile(unittest.TestCase):
    """Base class: write a throwaway Dockerfile and hand the parser its path."""

    def fixture(self, text):
        directory = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, directory, True)
        path = os.path.join(directory, "Dockerfile")
        with open(path, "w") as f:
            f.write(textwrap.dedent(text).lstrip())
        return path


# konsolidat#242 finding F1: a `#` line inside a `\`-continued RUN was folded
# into the instruction, so its words became "packages". Docker strips such a
# line; the parser must too, or the acceptance test passes on a Dockerfile that
# does not install the package it claims to check.
DROPS_FILE_BUT_MENTIONS_IT_IN_A_COMMENT = r"""
    FROM python:3.11-slim-bookworm

    RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl wget cron \
    # file is provided by the base image \
        mariadb-client \
        build-essential python3-dev \
        && apt-get clean && rm -rf /var/lib/apt/lists/*
"""


class ContinuationCommentsAreNotPackages(_FixtureDockerfile):
    """konsolidat#242 F1 — the false pass."""

    def test_a_comment_inside_a_continued_run_does_not_supply_file(self):
        path = self.fixture(DROPS_FILE_BUT_MENTIONS_IT_IN_A_COMMENT)
        packages = _apt_install_packages("mariadb-client", path=path)
        self.assertIsNotNone(packages, "fixture's apt-get install was not found at all")
        self.assertNotIn(
            "file",
            packages,
            "this Dockerfile does NOT install `file` — it only names it in a "
            "continuation comment, which Docker strips. Reporting it as "
            "installed is the false pass of konsolidat#242 F1. Packages: %r"
            % (packages,),
        )

    def test_no_comment_word_is_reported_as_a_package(self):
        path = self.fixture(DROPS_FILE_BUT_MENTIONS_IT_IN_A_COMMENT)
        packages = _apt_install_packages("mariadb-client", path=path)
        for word in ("#", "is", "provided", "by", "the", "base", "image"):
            self.assertNotIn(word, packages, "comment word leaked into %r" % (packages,))

    def test_the_real_packages_still_survive_the_comment(self):
        """Dropping the comment must not drop the instruction around it."""
        path = self.fixture(DROPS_FILE_BUT_MENTIONS_IT_IN_A_COMMENT)
        packages = _apt_install_packages("mariadb-client", path=path)
        for word in ("git", "curl", "mariadb-client", "build-essential"):
            self.assertIn(word, packages, "real package lost: %r" % (packages,))


# konsolidat#242 finding F9: only the exact prefix `apt-get install` parsed, so
# every other legitimate spelling returned None and failed the tests with "the
# parse, not the Dockerfile, is probably what changed" — a false red.
APT_INSTALL_SPELLINGS = {
    "flag before the verb": "apt-get -y install mariadb-client file curl",
    "apt rather than apt-get": "apt install -y mariadb-client file curl",
    "leading environment assignment": (
        "DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-client file curl"
    ),
    "assignment and a flag before the verb": (
        "DEBIAN_FRONTEND=noninteractive apt-get -qq -y install mariadb-client file curl"
    ),
    "flags on both sides of the verb": (
        "apt-get -y install --no-install-recommends mariadb-client file curl"
    ),
}


class AptInstallSpellingsAreRecognised(_FixtureDockerfile):
    """konsolidat#242 F9 — the too-strict prefix match."""

    def test_every_legitimate_spelling_yields_its_package_list(self):
        for name, command in sorted(APT_INSTALL_SPELLINGS.items()):
            with self.subTest(spelling=name):
                path = self.fixture(
                    "FROM python:3.11-slim-bookworm\n\nRUN apt-get update \\\n    && %s\n"
                    % command
                )
                packages = _apt_install_packages("mariadb-client", path=path)
                self.assertIsNotNone(
                    packages, "`%s` was not recognised as an apt install" % command
                )
                self.assertIn("file", packages)
                self.assertIn("curl", packages)
                self.assertNotIn("-y", packages)

    def test_a_command_that_is_not_an_apt_install_is_still_refused(self):
        """The prefix match may loosen, but not to the point of matching
        anything: `dpkg -i … || apt-get install -fy` names no packages."""
        path = self.fixture(
            """
            FROM python:3.11-slim-bookworm

            RUN dpkg -i /tmp/wkhtmltox.deb || apt-get install -fy
            """
        )
        self.assertIsNone(_apt_install_packages("mariadb-client", path=path))


if __name__ == "__main__":
    unittest.main()
