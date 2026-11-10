# SECURITY_HEADERS Fix Plan

## Changes

- `backend/src/app.ts` — define an explicit production CSP without `unsafe-inline`, `unsafe-eval`, wildcard/bare HTTPS, or development origins.
- Hosting configuration — mirror CSP, HSTS, X-Frame-Options, nosniff, and Referrer-Policy for static responses.
- Tests — assert headers on HTML, JS, API, and media responses.

## New files

- Optional CSP report endpoint/configuration.

## Verification goals

- [ ] Production CSP blocks inline scripts and restricts connect/img/media/frame sources.
- [ ] HSTS is enabled on HTTPS with at least one year and includeSubDomains.
- [ ] Core Flutter pages work without CSP console violations.

## Manual verification (for the human)

- Deploy Report-Only first and review browser reports before enforcement.
