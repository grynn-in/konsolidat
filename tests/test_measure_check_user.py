"""The ClickHouse user konsol's Measure expression check runs as (konsol#229).

A Measure expression is SQL an EPM Admin writes. konsol runs it before
publishing to catch a bad one; ClickHouse evaluates a scalar subquery inside
it even when the query reads no rows, so run as the stack's main user the
check would let an EPM Admin read any table in the shared warehouse
(system.users, another site's gold tables) and see the answer in the error
text. The check therefore runs as ``konsol_measure_check``, which may SELECT
only ``epm_silver.silver_gl_entries``, read-only, for at most 5 seconds.

``clickhouse/set-password.sh`` defines it on every container start from
``CLICKHOUSE_MEASURE_CHECK_PASSWORD``; ``deploy.sh`` generates that secret;
the configurator gives it to konsol's EPM Settings. No password, no user:
konsol then reports every expression "not checked" and never falls back.
"""
import hashlib
import os
import subprocess
import xml.etree.ElementTree as ET

import yaml

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(PROJECT_ROOT, "clickhouse", "set-password.sh")
USER = "konsol_measure_check"


def _run(tmp_path, password):
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "CLICKHOUSE_PASSWORD": "zz-main",
        "CLICKHOUSE_USERS_D": str(tmp_path),
        # the official entrypoint is not in a test checkout
        "CLICKHOUSE_ENTRYPOINT": "true",
    }
    if password is not None:
        env["CLICKHOUSE_MEASURE_CHECK_PASSWORD"] = password
    subprocess.run(["bash", SCRIPT], env=env, check=True)
    return tmp_path / "measure-check.xml"


def test_the_check_user_may_select_only_silver_gl_entries(tmp_path):
    path = _run(tmp_path, "zzsecret123")
    root = ET.parse(path).getroot()
    user = root.find(f"users/{USER}")
    assert user is not None, ET.tostring(root)
    grants = [q.text.strip() for q in user.findall("grants/query")]
    assert grants == ["GRANT SELECT ON epm_silver.silver_gl_entries"], grants
    assert user.findtext("access_management") == "0"
    # the secret is stored hashed, never in clear
    assert user.findtext("password_sha256_hex") == hashlib.sha256(b"zzsecret123").hexdigest()
    assert "zzsecret123" not in path.read_text()


def test_the_check_users_profile_is_read_only_and_time_limited(tmp_path):
    root = ET.parse(_run(tmp_path, "zzsecret123")).getroot()
    profile_name = root.findtext(f"users/{USER}/profile")
    profile = root.find(f"profiles/{profile_name}")
    assert profile is not None, profile_name
    assert profile.findtext("readonly") == "1"
    assert profile.findtext("max_execution_time") == "5"
    assert profile.findtext("cancel_http_readonly_queries_on_client_close") == "1"


def test_no_password_defines_no_check_user(tmp_path):
    (tmp_path / "measure-check.xml").write_text("<clickhouse/>")  # from an earlier start
    path = _run(tmp_path, None)
    assert not path.exists(), "a check user with no password was left defined"
    assert (tmp_path / "default-password.xml").exists()


def _services():
    with open(os.path.join(PROJECT_ROOT, "docker-compose.yml")) as f:
        return yaml.safe_load(f)["services"]


def test_compose_gives_the_secret_to_clickhouse_and_the_configurator():
    services = _services()
    for name in ("clickhouse", "configurator"):
        env = services[name].get("environment") or {}
        assert "CLICKHOUSE_MEASURE_CHECK_PASSWORD" in env, (name, sorted(env))


def test_the_configurator_hands_the_check_user_to_konsol():
    with open(os.path.join(PROJECT_ROOT, "docker", "configurator", "init.sh")) as f:
        text = f.read()
    assert "ch_check_user" in text and "ch_check_password" in text
    assert "CLICKHOUSE_MEASURE_CHECK_PASSWORD" in text


def test_deploy_generates_the_secret_for_a_new_and_an_existing_env():
    with open(os.path.join(PROJECT_ROOT, "deploy.sh")) as f:
        text = f.read()
    assert "set_env CLICKHOUSE_MEASURE_CHECK_PASSWORD" in text, \
        "an existing .env (every redeploy) would never get the check user"
