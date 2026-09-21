#!/usr/bin/env python3
"""CI guard: every gold dbt model must carry exactly one Build Governance domain.

Checks the models ON DISK against the generated YAML, not the YAML alone. A gold
model that was never registered as a konsol Build Model doc does not appear in
the generated block at all — so a guard that enumerated the YAML could not see
it, and five such models had accumulated, each rebuilt by no governed scope.
That is the very failure this file was written to prevent, so it now reads the
directory and reports both directions: a model with no entry, and an entry with
no model.

Build Governance runs scoped builds via `dbt build --select tag:domain:<domain>`.
A gold model with no `domain:` tag is built by NO scope (only a full build), so it
silently goes stale; a model with an unknown domain is never selected. konsol's
Build Model doctype is the source of truth that generates these tags — this check
guards the result so a model added to dbt_project.yml without a domain fails CI
instead of disappearing from governed builds.

Usage:  python scripts/check_gold_domains.py [path/to/dbt_project.yml]
Exit:   0 = all gold models tagged with a known domain; 1 = violations (listed).
"""
import os
import sys

import yaml

# Keep in sync with konsol Build Scope fixtures / tasks.SCOPE_SELECTOR.
KNOWN_DOMAINS = {"staging", "actuals", "scenarios", "consolidation", "reporting"}


def _domain_tags(cfg):
    tags = (cfg or {}).get("+tags", []) or []
    return [t.split(":", 1)[1] for t in tags
            if isinstance(t, str) and t.startswith("domain:")]


def _models_on_disk(project_yml_path, models_dir=None):
    """Gold model names as .sql files beside the project file."""
    directory = models_dir or os.path.join(
        os.path.dirname(os.path.abspath(project_yml_path)), "models", "gold")
    if not os.path.isdir(directory):
        return None  # unknown, not empty: never treat "no directory" as "no models"
    return {f[:-4] for f in os.listdir(directory) if f.endswith(".sql")}


def check(path, models_dir=None):
    with open(path) as f:
        project = yaml.safe_load(f) or {}

    gold = (((project.get("models") or {}).get("open_epm") or {}).get("gold")) or {}
    models = {name: cfg for name, cfg in gold.items() if not name.startswith("+")}

    on_disk = _models_on_disk(path, models_dir)
    unregistered = sorted(on_disk - set(models)) if on_disk is not None else []
    stale_entries = sorted(set(models) - on_disk) if on_disk is not None else []

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
    if unregistered:
        problems.append(
            "Gold models on disk with NO entry in dbt_project.yml (built by no "
            "governed scope, and invisible to this check until it started "
            "reading the directory):\n  - " + "\n  - ".join(unregistered))
    if stale_entries:
        problems.append(
            "dbt_project.yml entries with no model file (the coverage count "
            "reads as reassuring and is wrong):\n  - " + "\n  - ".join(stale_entries))
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
        print(f"\nRegister each gold model as a konsol 'Build Model' doc (which "
              f"generates its domain: tag) — do not hand-edit the generated YAML.")
        return 1

    counted = len(on_disk) if on_disk is not None else len(models)
    print(f"OK: all {counted} gold models are registered and carry a known "
          f"Build Governance domain.")
    return 0


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "dbt_project/dbt_project.yml"
    sys.exit(check(path, sys.argv[2] if len(sys.argv) > 2 else None))
