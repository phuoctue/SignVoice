# CORS Fix Plan

## Changes

- `backend/src/config/env.ts` — reject wildcard and malformed production origins.
- Tests — cover allowed, disallowed, missing, and reflected-origin requests.

## New files

- None required.

## Verification goals

- [ ] Production CORS has only exact trusted origins.
- [ ] Credentials never pair with wildcard origin.
- [ ] Static and API responses behave consistently.

## Manual verification (for the human)

- Verify the deployed origin list after every hosting change.
