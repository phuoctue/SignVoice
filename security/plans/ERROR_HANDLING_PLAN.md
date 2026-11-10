# ERROR_HANDLING Fix Plan

## Changes

- `backend/src/config/swagger.ts` — require an explicit authenticated/admin gate for docs, or disable them in all production-like modes.
- `backend/src/config/env.ts` — reject contradictory production/debug settings.
- Backend tests — assert generic production errors and inaccessible docs.

## New files

- Optional admin-only docs middleware.

## Verification goals

- [ ] `/api-docs` is 404 or authenticated in production.
- [ ] Production errors contain no stack, path, SQL, or library details.
- [ ] Development diagnostics remain local-only.

## Manual verification (for the human)

- Check public deployment with `/api-docs`, `/api-docs/openapi.json`, and malformed requests.
