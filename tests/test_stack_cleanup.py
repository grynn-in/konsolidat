"""TDD tests for stack cleanup — verify redundant components are removed."""
import os
import yaml

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_streamlit_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "streamlit"))


def test_cube_dir_removed():
    """Cube left the stack (konsol#232, konsolidat#283, decided 7 Nov 2026)."""
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "cube"))
    assert not os.path.exists(
        os.path.join(PROJECT_ROOT, "scripts", "generate_cube_schemas.py")
    )


def test_api_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "api"))


def test_dagster_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "dagster"))


def test_dockerfile_api_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "docker", "Dockerfile.api"))


def test_docker_compose_core_services():
    """docker-compose.yml has the core stack and none of the retired services."""
    path = os.path.join(PROJECT_ROOT, "docker-compose.yml")
    with open(path) as f:
        dc = yaml.safe_load(f)

    services = list(dc.get("services", {}).keys())
    # Core stack: ClickHouse warehouse and the Frappe app. Reads go through
    # konsol straight to ClickHouse; there is no semantic-layer service.
    assert "clickhouse" in services
    assert "frappe_backend" in services
    # Retired alternatives that must stay gone. cubejs: konsolidat#283.
    removed = [
        "dagster_postgres",
        "dagster_webserver",
        "dagster_daemon",
        "api",
        "streamlit",
        "cubejs",
    ]
    for svc in removed:
        assert svc not in services, f"Service {svc} should be removed"
    caddy_deps = dc["services"]["caddy"].get("depends_on") or []
    assert "cubejs" not in caddy_deps


def test_docker_compose_no_removed_volumes():
    """Removed volumes should not exist."""
    path = os.path.join(PROJECT_ROOT, "docker-compose.yml")
    with open(path) as f:
        dc = yaml.safe_load(f)

    volumes = list(dc.get("volumes", {}).keys()) if dc.get("volumes") else []
    assert "dagster_postgres_data" not in volumes


def test_env_example_no_cube_vars():
    """No Cube env vars in .env.example (konsolidat#283)."""
    path = os.path.join(PROJECT_ROOT, ".env.example")
    with open(path) as f:
        content = f.read()
    assert "CUBEJS" not in content


def test_caddyfile_no_cube_route():
    """Caddy no longer proxies the never-built konsol.cube_proxy endpoint or
    the Cube playground (konsolidat#283)."""
    path = os.path.join(PROJECT_ROOT, "docker", "caddy", "Caddyfile")
    with open(path) as f:
        content = f.read()
    assert "cube" not in content.lower()


def test_deploy_sh_no_cube():
    """deploy.sh neither generates CUBEJS_API_SECRET nor starts cubejs."""
    path = os.path.join(PROJECT_ROOT, "deploy.sh")
    with open(path) as f:
        content = f.read()
    assert "cube" not in content.lower()


def test_env_example_no_dagster_vars():
    """No Dagster env vars in .env.example."""
    path = os.path.join(PROJECT_ROOT, ".env.example")
    with open(path) as f:
        content = f.read()
    assert "DAGSTER" not in content


def test_healthcheck_no_old_ports():
    """healthcheck.sh should not check ports 8501, 8080, 4000, 15432, 3000."""
    path = os.path.join(PROJECT_ROOT, "scripts", "healthcheck.sh")
    with open(path) as f:
        content = f.read()
    for port in ["8501", "8080", "4000", "15432", "3000"]:
        assert port not in content, f"Port {port} should be removed from healthcheck"
