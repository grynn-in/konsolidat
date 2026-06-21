#!/usr/bin/env python3
"""CI guard: every gold dbt model must carry exactly one Build Governance domain.

Build Governance runs scoped builds via `dbt build --select tag:domain:<domain>`.
A gold model with no `domain:` tag is built by NO scope (only a full build), so it
silently goes stale; a model with an unknown domain is never selected. konsol's
Gold Model doctype is the source of truth that generates these tags — this check
guards the result so a model added to dbt_project.yml without a domain fails CI
instead of disappearing from governed builds.

Usage:  python scripts/check_gold_domains.py [path/to/dbt_project.yml]
Exit:   0 = all gold models tagged with a known domain; 1 = violations (listed).
"""
import sys

import yaml

# Keep in sync with konsol Build Domain fixtures / tasks.SCOPE_SELECTOR.
KNOWN_DOMAINS = {"staging", "actuals", "scenarios", "consolidation", "reporting"}


def _domain_tags(cfg):
    tags = (cfg or {}).get("+tags", []) or []
    return [t.split(":", 1)[1] for t in tags
            if isinstance(t, str) and t.startswith("domain:")]


def check(path):
    with open(path) as f:
        project = yaml.safe_load(f) or {}

    gold = (((project.get("models") or {}).get("open_epm") or {}).get("gold")) or {}
    models = {name: cfg for name, cfg in gold.items() if not name.startswith("+")}

    missing, unknown, multiple = [], [], []
    for name, cfg in models.items():
        domains = _domain_tags(cfg)
        if not domains:
            missing.append(name)
        elif len(domains) > 1:
            multiple.append((name, domains))
        elif domains[0] not in KNOWN_DOMAINS:
            unknown.append((name, domains[0]))

    problems = []
    if missing:
        problems.append("Gold models with NO domain: tag (won't be built by any "
                        "governed scope):\n  - " + "\n  - ".join(sorted(missing)))
    if unknown:
        problems.append("Gold models with an UNKNOWN domain (not in "
                        f"{sorted(KNOWN_DOMAINS)}):\n  - "
                        + "\n  - ".join(f"{n} -> domain:{d}" for n, d in sorted(unknown)))
    if multiple:
        problems.append("Gold models with MORE THAN ONE domain: tag:\n  - "
                        + "\n  - ".join(f"{n} -> {ds}" for n, ds in sorted(multiple)))

    if problems:
        print("FAIL: gold model domain coverage\n")
        print("\n\n".join(problems))
        print(f"\nRegister each gold model as a konsol 'Gold Model' doc (which "
              f"generates its domain: tag) — do not hand-edit the generated YAML.")
        return 1

    print(f"OK: all {len(models)} gold models carry a known Build Governance domain.")
    return 0


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "dbt_project/dbt_project.yml"
    sys.exit(check(path))
