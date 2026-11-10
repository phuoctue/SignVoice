# PAYMENT_WEBHOOKS Fix Plan

## Changes

- Future payment integration — verify provider signatures on every request and persist processed event IDs.

## New files

- Provider-specific webhook route and idempotency model when billing is approved.

## Verification goals

- [ ] Invalid signatures return 400.
- [ ] Duplicate events are ignored safely.

## Manual verification (for the human)

- Use provider test events in an isolated environment.
