---
id: non-ai-management-ui
scope: staff navigation, DTO compatibility and exposed management actions
status: ready
depends-on: [non-ai-oauth]
---

## Objective

Close the staff dashboard navigation/DTO blockers in the baseline audit. Follow
docs/active/NON_AI_API.md. Preserve existing admin workspace and permission gates. Review
exposed admin actions for fabricated success or incorrect service decoding, and fix
concrete broken flows rather than adding unrelated product features.

## Path

Own lib/screens/staff, lib/services/staff, lib/providers/staff_provider.dart and
staff_stats_model.dart; lib/app.dart only staff route registration after OAuth commit.
Own admin management screens/services only for concrete integration errors found.
Coordinate any models owned by frontend developer. Never edit OAuth/auth paths.

## UI contract

```text
Staff dashboard -> content list (search/status/page)
                  -> real detail -> permitted edit/approve/reject -> refreshed list
                -> user list (search/page) -> safe read-only detail
```

Every dashboard destination must exist and enforce permissions on direct navigation.
Lists show loading/error/retry/empty states, preserve filters across mutations, and
paginate real backend results. Detail fetches stable IDs and shows missing resources.
Failed mutations preserve inputs and show server errors. Moderation requires a real
reason for rejection and obeys shared backend ownership/status rules. No fake report
or notification submission. Unsupported actions show explicit unavailability.

## Verification

Use actual StaffService decoding against HTTP fixtures for flat stats, data.items and
flat detail DTOs. Widget tests must tap the dashboard destinations and exercise role
denial, failed mutations, refresh and empty lists. Run analyzer and applicable tests;
commit before independent review.
