---
id: non-ai-backend
scope: persisted non-AI APIs and management integrity
status: ready
depends-on: [non-ai-baseline]
---

## Objective

Close the baseline backend blockers in docs/plan/reviews/non-ai-baseline-audit.md, following
docs/active/NON_AI_DELIVERY.md and docs/active/NON_AI_API.md. Deliver real owned persistence and strict
validation for user/settings/favorites/history/manual conversations/privacy/sessions, shared
dictionary write invariants, staff/admin safety/audit correctness and test database isolation.

## Path

Own backend/src/routes/{user,history,favorites,category,dictionary,staff,admin}.routes.ts,
new conversations route, user validation/services/DTO helpers, UserSettings/Conversation
models, dictionary services/controller/admin-management/staff controllers, related tests,
backend/src/app.ts only for new non-AI route mounting, common error handling if required,
vitest config/test safety, OpenAPI non-auth sections and API coverage mapping.
Do NOT edit auth/OAuth routes/services/controllers, User.model.ts, config/env.ts,
requestLogger.ts, package manifests or .env.example; OAuth developer owns those concurrently.
Coordinate required changes across that boundary instead of editing it.

## Verification

First create a dedicated test database guard; never let automated tests mutate the user's
configured signvoice database. Test strict settings ownership against mass assignment,
favorites targets/counters/idempotency, two-user conversations CRUD/export/delete isolation,
safe profile DTO/email rules/settings ranges, session/account deletion and last-admin guard,
staff aliases ownership/status/IDs/queries and privilege escalation boundaries. Existing
backend tests and documentation validation/coverage must pass with added routes. No silent
fallbacks or fabricated report data. Run typecheck and commit before independent review.

Record exact DTOs or any necessary proposed contract changes early so frontend can integrate.
