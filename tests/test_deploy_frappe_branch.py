"""deploy.sh refuses a .env naming a Frappe branch the image is not built for (konsol#358).

docker/frappe/Dockerfile is tied to Frappe v16 (Python 3.14, Node 24), and
docker-compose.yml no longer passes FRAPPE_BRANCH to the build. The live stack's
.env pinned FRAPPE_BRANCH=version-15: without this guard that line would either
build an untested v15-on-3.14 image (when compose still passed it) or be ignored
without a word (now). scripts/check-frappe-branch.sh is run here on real files.
"""
import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD = os.path.join(ROOT, "scripts", "check-frappe-branch.sh")


def run_guard(env_text):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, ".env")
        if env_text is not None:
            with open(path, "w") as f:
                f.write(env_text)
        return subprocess.run(["bash", GUARD, path], capture_output=True, text=True)


class FrappeBranchGuard(unittest.TestCase):
    def test_refuses_a_stale_v15_pin(self):
        r = run_guard("SITE_NAME=x\nFRAPPE_BRANCH=version-15\n")
        self.assertEqual(r.returncode, 1)
        self.assertIn("FRAPPE_BRANCH=version-15", r.stderr)
        self.assertIn("backup", r.stderr)

    def test_refuses_a_quoted_or_crlf_pin(self):
        self.assertEqual(run_guard('FRAPPE_BRANCH="version-15"\n').returncode, 1)
        self.assertEqual(run_guard("FRAPPE_BRANCH=version-15\r\n").returncode, 1)

    def test_reads_every_spelling_dotenv_allows(self):
        """Review of konsol#358: `export`, spaces around `=` and an inline
        comment slipped past (or tripped) an anchored `^FRAPPE_BRANCH=`."""
        self.assertEqual(run_guard("export FRAPPE_BRANCH=version-15\n").returncode, 1)
        self.assertEqual(run_guard("FRAPPE_BRANCH = version-15\n").returncode, 1)
        self.assertEqual(run_guard("  FRAPPE_BRANCH=version-15  # old\n").returncode, 1)
        self.assertEqual(run_guard("FRAPPE_BRANCH=version-16 # pinned\n").returncode, 0)
        self.assertEqual(run_guard("# FRAPPE_BRANCH=version-15\n").returncode, 0)
        self.assertEqual(run_guard("FRAPPE_BRANCH=\n").returncode, 0)

    def test_accepts_v16_absent_line_and_missing_file(self):
        self.assertEqual(run_guard("FRAPPE_BRANCH=version-16\n").returncode, 0)
        self.assertEqual(run_guard('FRAPPE_BRANCH="version-16"\r\n').returncode, 0)
        self.assertEqual(run_guard("SITE_NAME=x\n").returncode, 0)
        self.assertEqual(run_guard(None).returncode, 0)

    def test_deploy_runs_the_guard_and_compose_does_not_pass_the_branch(self):
        with open(os.path.join(ROOT, "deploy.sh")) as f:
            self.assertIn("bash scripts/check-frappe-branch.sh .env || exit 1", f.read())
        with open(os.path.join(ROOT, "docker-compose.yml")) as f:
            compose = f.read()
        self.assertNotIn("FRAPPE_BRANCH:", compose)
        with open(os.path.join(ROOT, "docker", "frappe", "Dockerfile")) as f:
            self.assertIn("ARG FRAPPE_BRANCH=version-16", f.read())


if __name__ == "__main__":
    unittest.main()
