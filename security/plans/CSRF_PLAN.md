# CSRF Fix Plan

## Changes

- Backend integration tests — assert cookie flags and reject cross-origin state-changing requests.
- `backend/src/common/middlewares` — add CSRF token validation if any mutation relies on cookies beyond refresh.

## New files

- Cross-origin request regression test fixture.

## Verification goals

- [ ] All auth/session cookies are HttpOnly, Secure in HTTPS, and SameSite Strict/Lax.
- [ ] Cross-origin form POSTs fail.
- [ ] GET requests never mutate state.

## Manual verification (for the human)

- Inspect cookies after login/OAuth in browser DevTools.
