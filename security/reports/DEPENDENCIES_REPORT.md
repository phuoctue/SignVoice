# DEPENDENCIES Security Report

## Status: MEDIUM / audit pending

## Findings

`backend/package-lock.json` is committed, but `backend/package.json` uses caret ranges for production dependencies. Online `npm audit` did not complete; offline audit reported zero cached advisories for 534 dependencies. `gitleaks` and `semgrep` are not installed.

## What's at risk

Unreviewed transitive vulnerabilities or dependency drift can enter future installs.

## What's already secure

The lockfile pins resolved versions for reproducible installs and package names are from standard registries.

## Recommendations

Run online `npm audit`, review advisories, keep lockfile-only updates, and add dependency scanning to CI.
