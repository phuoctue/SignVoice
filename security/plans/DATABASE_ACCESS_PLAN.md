# DATABASE_ACCESS Fix Plan

## Changes

- `backend/src/services/*` — require owner/userId predicates in every user-scoped query.
- `backend/tests/*` — add cross-user read/update/delete denial tests for each resource family.

## New files

- Ownership matrix under `security/` or backend test documentation.

## Verification goals

- [ ] Every user resource query scopes by authenticated user id.
- [ ] Cross-user tests return 403/404 and never leak data.
- [ ] Admin paths are separately permission-gated.

## Manual verification (for the human)

- Run the matrix against an isolated QA database with two users.
