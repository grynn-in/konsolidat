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
"""
import os
import shlex
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCKERFILE = os.path.join(PROJECT_ROOT, "docker", "frappe", "Dockerfile")


def _logical_lines(path):
    """Yield the Dockerfile's instructions, with `\\`-continuations joined."""
    with open(path) as f:
        raw = f.read()
    joined = []
    buffer = ""
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped.startswith("#") and not buffer:
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


def _apt_install_packages(package):
    """Packages named by the `apt-get install` command that installs `package`.

    Returns the whole token list of that one `&&`-separated command, with the
    `apt-get install` words and every flag dropped, so callers compare whole
    tokens. Returns None when no such command exists.
    """
    for instruction in _logical_lines(DOCKERFILE):
        if not instruction.startswith("RUN "):
            continue
        body = instruction[len("RUN "):]
        for command in body.split("&&"):
            try:
                tokens = shlex.split(command)
            except ValueError:  # unbalanced quoting: not a package list
                continue
            if tokens[:2] != ["apt-get", "install"]:
                continue
            packages = [t for t in tokens[2:] if not t.startswith("-")]
            if package in packages:
                return packages
    return None


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


if __name__ == "__main__":
    unittest.main()
