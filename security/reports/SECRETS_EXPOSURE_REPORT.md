# SECRETS_EXPOSURE Security Report

## Status: MEDIUM

## Findings

- `backend/.env` and `**/.env*` are ignored, and the local scan checked 20 sensitive paths with no exposure.
- `backend/src/config/env.ts` contains insecure development defaults: MongoDB uses `signvoice:dev_password`, and `ADMIN_PASSWORD` defaults to `admin123456`.
- JWT secrets default empty and are rejected by `validateEnv`; this is safer than silently generating a weak token, but startup depends on deployment configuration.
- No tracked `.env` file or secret key was found by the available checks. `gitleaks` was not installed, so history was not scanned with that tool.

## What's at risk

If development defaults leak into a reachable deployment or seed script, an attacker may obtain database/admin access.

## What's already secure

The ignore rules exclude environment files, private keys, token pickles, runtime state, and build output. Live requests did not expose `.env`, `.git`, dumps, keys, logs, or directory listings.

## Recommendations

Remove credential defaults from production code paths, fail closed unless explicit secrets are supplied, run a history scan with gitleaks, and rotate any secret ever used outside local development.
