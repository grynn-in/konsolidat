"""TDD tests for stack cleanup — verify redundant components are removed."""
import os
import yaml

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def test_streamlit_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "streamlit"))


def test_cube_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "cube"))


def test_api_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "api"))


def test_dagster_dir_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "dagster"))


def test_dockerfile_api_removed():
    assert not os.path.exists(os.path.join(PROJECT_ROOT, "docker", "Dockerfile.api"))


def test_docker_compose_only_clickhouse():
    """docker-compose.yml should only have clickhouse service."""
    path = os.path.join(PROJECT_ROOT, "docker-compose.yml")
    with open(path) as f:
        dc = yaml.safe_load(f)

    services = list(dc.get("services", {}).keys())
    assert "clickhouse" in services
    # These should be gone
    removed = [
        "dagster_postgres",
        "dbt_init",
        "dagster_webserver",
        "dagster_daemon",
        "cube",
        "api",
        "streamlit",
    ]
    for svc in removed:
        assert svc not in services, f"Service {svc} should be removed"


def test_docker_compose_no_removed_volumes():
    """Removed volumes should not exist."""
    path = os.path.join(PROJECT_ROOT, "docker-compose.yml")
    with open(path) as f:
        dc = yaml.safe_load(f)

    volumes = list(dc.get("volumes", {}).keys()) if dc.get("volumes") else []
    assert "dagster_postgres_data" not in volumes


def test_env_example_no_cube_vars():
    """No Cube.js env vars in .env.example."""
    path = os.path.join(PROJECT_ROOT, ".env.example")
    with open(path) as f:
        content = f.read()
    assert "CUBEJS" not in content
    assert "CUBE_" not in content


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
