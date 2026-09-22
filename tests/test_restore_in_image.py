"""`bench restore` needs `file(1)` in the image (konsolidat#240).

Frappe shells out to `file` to decide whether a dump is gzipped, at
`frappe/commands/site.py:234` (restore) and `:375` (partial restore). The
image's apt list installed `git curl wget cron mariadb-client`, fonts,
`build-essential`, nodejs, yarn and wkhtmltopdf — not `file` — so `bench
restore` died with `file: command not found`. Measured 22 September 2026 in the
running `konsolidat_backend`: `command -v file` returned nothing.

**The rule is deliberately loose.** An earlier version tokenised the apt
command: splitting on `&&`, matching the exact prefix `apt-get install`,
requiring `file` in the *same* command as `mariadb-client`. Every one of those
was a review finding — it missed `apt install`, missed `;`-separated commands,
missed version pins, and would have failed a Dockerfile that installs `file`
correctly in a `RUN` of its own. It also passed a Dockerfile that did not
install `file` at all, because a `#` comment inside a `\\`-continued `RUN` was
folded in and its words counted as packages.

So: comments are dropped wherever they appear, as Docker itself drops them;
continuations are joined; and `file` must appear as a bare word in some
instruction that installs packages. That is the requirement konsolidat#240
actually states — the built image has `/usr/bin/file` — and nothing narrower.

What this does NOT prove (the PRD's "Residual" section): that the built image
contains the binary, or that `bench restore` succeeds. It proves the list asks
for the package. That the package provides the binary on this base was measured
by hand on `python:3.11-slim-bookworm` (`file-5.44`); the first real image
rebuild closes the loop, and konsolidat#241 is the restore smoke test.
"""
import os
import re
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCKERFILE = os.path.join(PROJECT_ROOT, "docker", "frappe", "Dockerfile")


def _install_instructions(path=DOCKERFILE):
    """Dockerfile instructions that install packages, comments dropped.

    A whole-line comment is dropped whether or not a `\\` continuation is open:
    Docker strips those, and treating one as part of the instruction is how a
    Dockerfile that merely *mentions* a package was read as installing it.
    """
    with open(path) as f:
        raw = f.read()
    instructions, buffer = [], ""
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if stripped.endswith("\\"):
            buffer += stripped[:-1].strip() + " "
            continue
        buffer += stripped
        if buffer.strip():
            instructions.append(" ".join(buffer.split()))
        buffer = ""
    if buffer.strip():
        instructions.append(" ".join(buffer.split()))
    # The install verb, not merely the words "apt" and "install": otherwise
    # `RUN npm install -g x && rm -rf /var/lib/apt/lists/*` reads as an apt
    # install, and anything it happens to name counts as a package.
    verb = re.compile(r"\bapt(?:-get)?\s+(?:-\S+\s+)*install\b")
    return [i for i in instructions if verb.search(i)]


def _installs(package, path=DOCKERFILE):
    """True when some install instruction names `package` as a whole word.

    A version pin (`file=1:5.44-3`) counts; `Dockerfile`, `libfontconfig1` and
    `/tmp/wkhtmltox.deb` do not.
    """
    word = re.compile(r"(?<![\w./=-])%s(?![\w./-])" % re.escape(package))
    return any(word.search(i) for i in _install_instructions(path))


class TheImageInstallsFile(unittest.TestCase):
    def test_the_dockerfile_installs_packages_at_all(self):
        """Vacuity guard: if the scan finds no install instruction, or misses a
        package that is certainly there, the assertion below means nothing."""
        self.assertTrue(
            _install_instructions(),
            "no apt install instruction found in %s; the scan, not the "
            "Dockerfile, is probably what changed" % DOCKERFILE,
        )
        self.assertTrue(
            _installs("mariadb-client"),
            "the scan cannot even find mariadb-client; it is broken",
        )

    def test_file_is_installed(self):
        """konsolidat#240: `bench restore` shells out to file(1)."""
        self.assertTrue(
            _installs("file"),
            "`file` is not installed; `bench restore` shells out to file(1) "
            "(frappe/commands/site.py:234, :375) and fails with "
            "`file: command not found`. Install instructions found:\n%s"
            % "\n".join(_install_instructions()),
        )


if __name__ == "__main__":
    unittest.main()
