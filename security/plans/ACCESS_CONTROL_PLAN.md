# ACCESS_CONTROL Fix Plan

## Changes

- `backend/src/services/*` — document and enforce owner predicates for every ID-bearing operation.
- `backend/tests/*` — add two-user IDOR tests for all resource families.

## New files

- `security/access-control-matrix.md`.

## Verification goals

- [ ] Authenticated user A cannot read or mutate user B resources.
- [ ] Delete and bulk operations enforce ownership.
- [ ] Staff/admin exceptions are explicit and permission-scoped.

## Manual verification (for the human)

- Replay requests with swapped resource IDs using isolated QA accounts.
