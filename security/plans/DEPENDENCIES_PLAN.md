# DEPENDENCIES Fix Plan

## Changes

- CI — run `npm audit --audit-level=high`, lockfile validation, and optional semgrep/gitleaks jobs.
- Dependency policy — review major updates and avoid unnecessary range widening.

## New files

- CI security workflow if one does not already exist.

## Verification goals

- [ ] Fresh registry audit has no high/critical vulnerabilities or has documented exceptions.
- [ ] Lockfile and manifest stay synchronized.
- [ ] Secret/static-analysis scans run on pull requests.

## Manual verification (for the human)

- Re-run against the production branch with network access before release.
