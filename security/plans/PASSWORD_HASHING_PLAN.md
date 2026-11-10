# PASSWORD_HASHING Fix Plan

## Changes

- Password utility — keep Argon2id and review cost parameters during capacity planning.
- Tests — retain known-good, wrong-password, malformed-hash, and rehash cases.

## New files

- None required.

## Verification goals

- [ ] New passwords use Argon2id.
- [ ] Legacy weak hashes cannot remain active without migration/reset.

## Manual verification (for the human)

- Review login latency under production-like load.
