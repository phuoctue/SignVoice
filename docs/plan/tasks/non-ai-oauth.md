---
id: non-ai-oauth
scope: configurable Google/Facebook authentication
status: implemented-awaiting-review
depends-on: []
---

## Objective

Implement the user's eight OAuth requirements while preserving email/password, guest,
password recovery and existing JWT rotation. No credentials or fixed HTTPS domain are available.
Read docs/INDEX.md, docs/active/NON_AI_DELIVERY.md and existing auth service/controller/storage/tests.

## Contract

- Node/Express/TypeScript backend. Optional provider config must not prevent backend startup.
- Fixed paths `/api/v1/auth/oauth/google/callback` and `/api/v1/auth/oauth/facebook/callback`.
- Environment config provides backend public origin, frontend success/error destination,
  Google client ID/secret, Facebook app ID/secret, graph API version, state expiry and
  optional explicit callback overrides. localhost HTTP is permitted only in development;
  public origins/callbacks require HTTPS. Never derive callback host from untrusted Host/
  X-Forwarded-Host/redirect query parameters. Dynamic Conveyor domains work by editing env.
- Authorization-code flow. Google uses official verification library for signature,
  audience, issuer, expiration, subject, verified email and request nonce; PKCE where supported.
- Facebook exchanges code server-side, validates token using debug_token (app ID, validity,
  expiry, user identity), requests minimum profile/email, and uses appsecret_proof where
  appropriate. Do not accept a client-supplied provider profile/token as authenticated identity.
- Cryptographically random state bound to the initiating browser, provider and configured
  redirect; short TTL, one-use atomic consumption, including cancellation/error callbacks.
  Cross-site callback must work with SameSite=Lax state cookie. HttpOnly, Secure on HTTPS,
  bounded lifetime, and no provider secrets or access tokens in logs/URLs/DTOs.
- Do not automatically merge a social identity into a pre-existing local account based
  solely on matching email. Return a clear collision error; linking requires separate
  authenticated proof and is outside this first OAuth login flow. Suspended/deleted users
  cannot log in. Provider subject uniqueness and concurrent first-login races must be handled.
- Reuse real SignVoice access+refresh session persistence and authorization, never create
  standalone JWTs lacking database sessions. OAuth web callback sets an HttpOnly refresh
  cookie, redirects only to configured frontend `/oauth-complete` route without tokens,
  and Flutter obtains its normal session through an authenticated completion/refresh flow.
  Account metadata bootstrap must work even when there was no prior local login.
- Public provider availability endpoint returns only enabled/disabled provider flags.
  Unconfigured start returns a precise disabled/configuration error, without affecting other
  login methods. UI must never simulate social success; disabled providers show useful setup
  explanation. Preserve existing email auth UI and handle cancel/errors on return.
- Browser web OAuth must be fully wired to start/callback/completion. Native platform support
  must be truthful and documented; do not pretend a system browser cookie signs in native app.

## Path ownership

Own backend auth/OAuth routes, services/controllers, config/env.ts, .env.example,
User model provider identity fields/indexes, OAuth state model, auth-related tests,
auth session helper refactors if necessary, package dependency manifests, OAuth OpenAPI sections.
Own Flutter lib/features/auth, lib/services/auth, lib/providers/auth_provider.dart,
lib/app.dart callback routing only, auth tests and docs/active/OAUTH_SETUP.md.
Parent explicitly extended ownership to common/middlewares/requestLogger.ts OAuth redaction
and /auth/change-password plus app.dart AppState.bindAccount lifecycle wiring.
Do not modify AppState, profile/library/home screens, user/favorites/history API routes or
UserSettings/Conversation models. Other tasks will own those boundaries.

## Verification

Use official primary provider docs (Google OpenID Connect, Meta manual login/debug_token).
Unit/HTTP tests cover disabled config, invalid domain/callback config, missing/mismatched/
expired/replayed state, provider mismatch and cancellation, bad token audience/issuer/nonce,
Facebook mismatched app/user/expiry, account collision/suspension, safe refresh session handoff,
and unchanged existing login/guest flows. Fake provider network boundaries in automated tests;
test the application's real routes/session logic. Do not claim a live provider login succeeded.
Run backend typecheck/relevant tests, Flutter auth/route tests/analyzer. Install dependencies
only in this worktree; never change shared machine settings or real provider accounts.

Document exact env variables, localhost and Conveyor examples, provider-console redirect URLs,
test-user setup, missing-credential smoke tests and manual live verification instructions.
Commit code, contract/docs and tests on task/non-ai-oauth before reporting for independent review.

## Implementation evidence (2026-10-16)

- Configurable provider code flow, Google official verifier/nonce/PKCE, Meta server exchange/
  debug_token/user match/appsecret_proof, atomic Mongo browser-bound state and safe redirects.
- Normal persisted JWT sessions and HttpOnly cookie completion bootstrap, email collision
  rejection, subject unique indexes, suspended/deleted rejection, explicit provider flags/UI.
- Flutter same-tab web OAuth/complete/error UI; native unsupported explanation; preserved
  email/guest methods. Local password change verifies proof, increments passwordVersion and
  revokes sessions. Exact environment/provider-console/manual instructions in OAUTH_SETUP.md.
- Backend typecheck and OpenAPI validation/coverage passed (68/68 documented routes).
- OAuth DB/HTTP suite 25 tests passed on isolated signvoice_test_oauth_v2_1; existing auth
  (9), auth-security (15), password-reset (11) passed in regression run. Only added password
  validation assertion initially mismatched existing 400 semantics, fixed and OAuth rerun passed.
- Flutter OAuth bootstrap/cancellation/error tests: 4 passed. Focused auth analyzer initially
  passed. Final app analyzer/route suite awaits sibling AppState.bindAccount implementation:
  app.dart now calls the agreed signature for identity changes; do not omit that dependency.
- Live provider login was NOT verified: user has not supplied credentials. Official Google
  docs retrieved; official Meta pages inaccessible/rate limited via research tool, linked in setup.
- Test database guard cherry-picked from backend task (7e113b4 -> local 50bce7b).
- Independent review follow-up: failed current-password proof is HTTP 400 validation, preserving
  the valid bearer session. Real AuthProvider/AuthService/ApiClient controlled-HTTP regression
  verifies identity, tokens, metadata and no refresh/invalidation until a successful retry;
  backend route regression verifies the existing access session remains valid after rejection.
