# SECURITY_HEADERS Security Report

## Status: HIGH

## Findings

The local live scan found a CSP with `script-src 'unsafe-inline'` and broad `connect-src`, `img-src`, and `media-src` values. `backend/src/app.ts` also permits development-only HTTP media and several broad origins to support local Flutter/AI workflows. The scanner passed X-Frame-Options, X-Content-Type-Options, Referrer-Policy, object-src, base-uri, form-action, and frame-ancestors. HSTS was not measurable on HTTP localhost.

## What's at risk

Inline script execution and broad resource destinations reduce XSS containment and data-exfiltration resistance if an injection occurs.

## What's already secure

Helmet is global and static assets receive the same headers locally.

## Recommendations

Separate development and production CSPs, remove inline/eval allowances from production, enumerate exact production origins, and roll out with Report-Only before enforcement.
