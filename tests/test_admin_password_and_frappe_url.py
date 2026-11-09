"""A new site never gets a known Administrator password, and deploy.sh reaches
Frappe when FRAPPE_PORT names a host (Deepak Pai, 8 Nov 2026).

- docker/configurator/init.sh created a site with `admin123` when ADMIN_PASSWORD
  was unset, and a stack whose .env held the public placeholder
  `not-stored-here-site-already-exists` would have created its site with that
  string. check-admin-password.sh refuses both, and an empty value, before
  `bench new-site`.
- The demo server binds Frappe to 127.0.0.1 (FRAPPE_PORT=127.0.0.1:8069), and
  deploy.sh built http://localhost:127.0.0.1:8069. frappe-url.sh builds the URL
  from either spelling.
The scripts are run here on real values.
"""
import os
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECK = os.path.join(ROOT, "docker", "configurator", "check-admin-password.sh")
URL = os.path.join(ROOT, "scripts", "frappe-url.sh")


def check(value):
    env = {k: v for k, v in os.environ.items() if k != "ADMIN_PASSWORD"}
    if value is not None:
        env["ADMIN_PASSWORD"] = value
    return subprocess.run(["bash", CHECK], capture_output=True, text=True, env=env)


def url(value):
    env = {k: v for k, v in os.environ.items() if k != "FRAPPE_PORT"}
    if value is not None:
        env["FRAPPE_PORT"] = value
    return subprocess.run(["bash", URL], capture_output=True, text=True, env=env)


class AdminPasswordCheck(unittest.TestCase):
    def test_refuses_unset_and_empty(self):
        for value in (None, "", "   "):
            r = check(value)
            self.assertEqual(r.returncode, 1, repr(value))
            self.assertIn("ADMIN_PASSWORD", r.stderr)

    def test_refuses_known_passwords(self):
        for value in ("admin123", "not-stored-here-site-already-exists", "not-stored-here"):
            r = check(value)
            self.assertEqual(r.returncode, 1, value)
            self.assertNotIn(value, r.stdout + r.stderr, "the refused value must not be printed")

    def test_accepts_a_real_password(self):
        r = check("k7Qz2pLmW9xRt4Vb")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout + r.stderr, "")

    def test_init_runs_the_check_before_new_site_and_has_no_default(self):
        init = open(os.path.join(ROOT, "docker", "configurator", "init.sh")).read()
        self.assertNotIn("admin123", init)
        self.assertLess(init.index("check-admin-password.sh"), init.index("bench new-site"))
        self.assertNotIn('Administrator / ${ADMIN_PASSWORD}', init, "the log must not print the password")


class FrappeUrl(unittest.TestCase):
    def test_bare_port(self):
        self.assertEqual(url("8069").stdout, "http://localhost:8069")
        self.assertEqual(url(None).stdout, "http://localhost:8069")

    def test_host_and_port(self):
        self.assertEqual(url("127.0.0.1:8069").stdout, "http://127.0.0.1:8069")
        self.assertEqual(url("172.30.0.1:8169").stdout, "http://172.30.0.1:8169")

    def test_deploy_uses_it_everywhere(self):
        deploy = open(os.path.join(ROOT, "deploy.sh")).read()
        self.assertNotIn("localhost:${FRAPPE_PORT", deploy)
        self.assertIn("scripts/frappe-url.sh", deploy)


if __name__ == "__main__":
    unittest.main()
