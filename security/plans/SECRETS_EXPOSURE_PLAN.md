# SECRETS_EXPOSURE Fix Plan

## Changes

- `backend/src/config/env.ts` — remove usable admin/database defaults and require explicit deployment values.
- `.env.example` — keep placeholders only; document generation and rotation.
- CI — run gitleaks against commits and reject secrets.

## New files

- Optional CI job for gitleaks.

## Verification goals

- [ ] No tracked environment or key files.
- [ ] Missing production secrets abort startup.
- [ ] gitleaks passes current tree and history.
- [ ] Local-only defaults cannot authenticate against a deployed service.

## Manual verification (for the human)

- Rotate any credential that was shared outside the machine.
