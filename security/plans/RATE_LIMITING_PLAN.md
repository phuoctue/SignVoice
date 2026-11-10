# RATE_LIMITING Fix Plan

## Changes

- `backend/src/routes/auth.routes.ts` — add separate limits for login, registration, guest creation, and refresh.
- Backend tests — assert 429 thresholds and verify spoofed `X-Forwarded-For` cannot bypass them.

## New files

- Optional shared limiter configuration module.

## Verification goals

- [ ] Auth abuse endpoints return 429 at documented thresholds.
- [ ] Limits are keyed safely behind the actual proxy configuration.
- [ ] Legitimate mobile retry behavior remains usable.

## Manual verification (for the human)

- Tune thresholds using production traffic and alerting data.
