# SQL_INJECTION Fix Plan

## Changes

- Validation layer — reject Mongo operator keys in all free-form filters.
- Tests — add `$where`, `$gt`, dotted-key, and regex abuse cases.

## New files

- No new production file required.

## Verification goals

- [ ] All database filters are schema-derived or parameterized.
- [ ] Operator injection tests fail closed.

## Manual verification (for the human)

- Review new query features before release.
