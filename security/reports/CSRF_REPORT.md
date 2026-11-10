# CSRF Security Report

## Status: MEDIUM / manual pending

## Findings

Refresh cookies in `backend/src/controllers/auth.controller.ts` use `HttpOnly` and `SameSite=Strict`, with `Secure` enabled for production/HTTPS. CORS uses an explicit origin list. However, no CSRF token middleware was found, and landing-page scanning cannot observe post-login cookies or cross-origin form behavior.

## What's at risk

A future cookie-authenticated state-changing endpoint or a deployment that weakens SameSite could be vulnerable to cross-site requests.

## What's already secure

Bearer authentication is used by many API calls, refresh cookies are scoped to `/api/v1/auth`, and foreign origins are rejected locally.

## Recommendations

Add automated cross-origin POST tests and document the invariant that all cookie-authenticated mutations require strict SameSite or CSRF validation.
