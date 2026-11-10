# SSRF Fix Plan

## Changes

- `backend/src/services/*` — route all future user-supplied URL fetches through a shared validator/resolver.
- Tests — cover loopback, RFC1918, link-local, IPv6 local, redirects, and DNS rebinding.

## New files

- Shared outbound URL policy module.

## Verification goals

- [ ] Only approved schemes/hosts are fetched.
- [ ] Private/link-local destinations and redirects are blocked.

## Manual verification (for the human)

- Verify outbound allowlist against production integrations.
