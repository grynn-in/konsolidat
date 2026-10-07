"""Every service caps its Docker log, so a container stuck in an error loop
cannot fill the host's disk.

6 Oct 2026: ClickHouse's own log channel broke on 30 Sep and from then on wrote
a stack trace to stderr for every message. Docker kept stderr in an uncapped
json-file log that grew to 28.6 GB and filled the VM disk, after which every
ClickHouse write failed with NOT_ENOUGH_SPACE. A cap turns that failure into a
noisy log instead of a dead warehouse.
"""
import os

import yaml

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPOSE_FILES = ["docker-compose.yml", "docker-compose.cluster.yml"]


def _services(name):
    with open(os.path.join(PROJECT_ROOT, name)) as f:
        return (yaml.safe_load(f) or {}).get("services", {})


def _size_bytes(text):
    units = {"k": 1024, "m": 1024 ** 2, "g": 1024 ** 3}
    text = str(text).strip().lower()
    if text[-1] in units:
        return int(text[:-1]) * units[text[-1]]
    return int(text)


def test_every_service_caps_its_log():
    uncapped = []
    for name in COMPOSE_FILES:
        for svc, spec in _services(name).items():
            logging = (spec or {}).get("logging") or {}
            options = logging.get("options") or {}
            driver = logging.get("driver", "json-file")
            if driver not in ("json-file", "local") or "max-size" not in options \
                    or "max-file" not in options:
                uncapped.append(f"{name}:{svc}")
    assert not uncapped, f"services without a Docker log cap: {uncapped}"


def test_the_cap_is_bounded():
    """max-size x max-file stays under 1 GiB per container."""
    for name in COMPOSE_FILES:
        for svc, spec in _services(name).items():
            options = ((spec or {}).get("logging") or {}).get("options") or {}
            if not options:
                continue
            total = _size_bytes(options["max-size"]) * int(options["max-file"])
            assert total <= 1024 ** 3, f"{name}:{svc} may keep {total} bytes of log"
