---
id: non-ai-review
scope: independent OAuth and non-AI delivery verification
status: pending
depends-on: [non-ai-oauth, non-ai-backend, non-ai-frontend, non-ai-management-ui]
---

## Independent review

Review each committed implementation before merge and the integrated branch afterward.
Do not review code you authored. Use docs/active/NON_AI_DELIVERY.md, docs/active/NON_AI_API.md and
the baseline audit as the checklist; report concrete failures with file/line evidence.

OAuth requires special verification of configuration (empty/partial/invalid), fixed
callback paths, configured origins, one-use browser-bound state, cancellation, provider
token identity, account collisions, session rotation/revocation, callback handoff and
absence of provider/access/refresh credentials in URLs, logs or safe user DTOs. Verify
the mocked network boundary actually exercises real routes and database sessions.
Check `.env.example` and setup instructions against implemented names and official
provider requirements. Real Google/Meta login remains external until credentials exist.

Non-AI verification must cover per-user ownership, settings mass assignment, API/FE DTO
compatibility, mutation failures, account switching and stale asynchronous responses,
dictionary/favorites status/category/counter invariants, staff alias RBAC and navigation,
privacy/export/account/session actions, and absence of fabricated AI or synchronization.

Use a guarded dedicated test database only. Never test against the configured user DB,
print secrets, delete production data or create external provider accounts. Full delivery
checks: backend tests/typecheck/OpenAPI validation/coverage; Flutter analyzer/tests/web
build; Android build if toolchain is available. Record precise passed evidence and any
external limitation. Do not infer complete live verification from passing mocks.

Blocking findings return to the implementation agent. Commit a review report with
accepted evidence and remaining limitations; merge only after blocking fixes pass.
