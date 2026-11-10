# RATE_LIMITING Security Report

## Status: MEDIUM

## Findings

Rate limits exist for OAuth, password reset, quiz, AI, collection import/share, and some reports. `backend/src/routes/auth.routes.ts` does not apply a limiter to register, login, guest creation, or refresh. Those endpoints are brute-force/account-abuse targets.

## What's at risk

Credential stuffing, account enumeration pressure, guest-account exhaustion, and refresh abuse.

## What's already secure

Sensitive OAuth/password-reset flows explicitly disable unsafe forwarded-IP validation and return 429 responses through express-rate-limit.

## Recommendations

Add endpoint-specific limits to login/register/guest/refresh, use a trusted proxy configuration, and monitor rate-limit events.
