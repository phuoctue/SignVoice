---
id: non-ai-frontend
scope: active persisted user UI and truthful excluded-AI states
status: ready
depends-on: [non-ai-baseline]
---

## Objective

Complete the active lib/features user flows using docs/active/NON_AI_API.md and baseline audit.
Reuse the existing visual design and actual services/DTOs. Replace AppState-only data with
real profile/settings/favorites/manual conversations, safe per-account lifecycle and real sync.
Home/dictionary/detail must use actual data. Recognition/STT routes must state unavailable,
never fabricate or persist sample results. Manual text entry/save remains available.

## Path

Own lib/core/app_state.dart, lib/features/{home,library,profile,recognition,speech,system},
lib/models excluding UserModel, user/favorites/history/conversations/dictionary/category
services and their providers, lib/services/api/api_config.dart, platform INTERNET configuration,
and new user feature tests. Own stale unused user screens/providers cleanups and analyzer issues
within these paths. Do NOT modify lib/app.dart, features/auth, services/auth or AuthProvider;
OAuth developer owns them concurrently. Do NOT modify shared widgets/navigation until you
coordinate ownership with parent. Final app.dart integration will be a separate small task
if required; send exact needed binding/hooks/routes rather than editing it concurrently.

## Contract

AppScope may establish user bindings via existing AuthProvider above it; guard asynchronous
account changes. Allow explicit service/client injection for tests and real implementation
boundary tests. No network in ordinary widget-only tests unless fixtures explicitly provide it.
Settings/profile cache cannot overwrite another account; displayName/avatar changes apply only
after successful save. New conversation text labels TEXT, while legacy sources remain readable.
Export and deletion/session/password actions must use real APIs or be wired in an explicit
follow-up task. Coordinate change-password auth service method with OAuth developer.
Web API default is same-origin; native host configurable. Keep guest conversion and role gates.
Avoid duplicate unused screen stacks masquerading as completed routed features.

## Verification

Tests must exercise real service response decoding, active routed screen interactions,
mutation errors/retained inputs/reload, empty/missing resources, two-account stale-response
isolation, and absence of fake AI output. Run analyzer and Flutter tests. Report required
app.dart/navigation/widget integration precisely. Commit before independent review.
