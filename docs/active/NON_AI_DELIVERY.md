# Non-AI completion contract

Date: 2026-10-16. Baseline: origin/main `78efbe2` from the user's pushed repository.
User instruction: remove the recently added AI/LM Studio integration and complete the
backend and Flutter frontend outside AI. Preserve the existing design, account ownership,
JWT session model, and USER/STAFF/ADMIN authorization model.

## Scope and acceptance

1. Remove the AI test page, LM Studio services/configuration, video adapter, packages,
   navigation entries, and their platform/server configuration changes. Preserve the user's
   installed LM Studio and downloaded models; these are outside the project.
2. Email registration, login, guest conversion, password recovery/change, session restore,
   refresh and logout must execute real APIs and handle invalid/expired/revoked credentials.
3. Google and Facebook OAuth are requested. Credentials will be supplied in backend/.env.
   Implement a secure authorization-code flow, single-use state/CSRF protection, provider
   identity validation, safe account collision behavior and a callback that does not expose
   access/refresh tokens in URLs. Missing configuration must be explicit, never simulated.
4. User profile/settings/history/favorites must persist on the backend, reload across sessions,
   isolate accounts, and show loading/empty/error/retry states. Guest restrictions must be
   consistent in both layers. Deletion/export actions must reflect real persisted data.
5. Published dictionary/category browsing, search, pagination, detail/media and favorites must
   use backend data. Never substitute sample entries when a request fails or returns empty.
6. Staff/admin management must enforce ownership/permissions and valid content status changes,
   reject invalid IDs and input, prevent dangerous role escalation and preserve useful audit data.
7. Synchronization means reloading persisted resources/settings, with accurate progress/errors.
   It must never claim success for a timer or silently swallow a failed operation.
8. Recognition, speech-to-text, OCR, automatic translation and AI generation remain excluded.
   Their routes must state that AI is unavailable and must not generate fake recognition results
   or save fabricated conversations. Text manually entered/edited by the user may be saved.
9. Existing non-AI voice settings may persist; do not claim actual playback unless implemented.
10. Web uses the same-origin backend when hosted by Conveyor; native API host is configurable.
    Secrets stay server-side. No browser calls to localhost AI endpoints remain.

## UI/state contract

```text
Authenticated shell
  Home: real published dictionary + real recent history + truthful unavailable-AI entry
  Dictionary: search/filter -> paged results -> detail/media -> persistent favorite
  History: search/filter -> owned detail -> favorite/copy/delete
  Profile: persisted identity -> edit/settings/sync/privacy/account/session actions
  Staff/Admin: role-aware navigation -> validated forms -> mutation -> refreshed lists
```

Keep the current mobile card layout, scrollable forms, desktop framing and accessibility
settings. New dialogs must be dismissible and keyboard-safe; a failed save preserves user input.
Settings are applied only from validated defaults or persisted server values. Account changes
clear all previous-account selections, caches and sensitive session state.

## Verification and reporting

Each delivery item needs API contract tests and/or frontend interaction/persistence tests.
Use real API/client/provider implementations at integration boundaries with controlled HTTP.
Run full backend tests/typecheck/docs validation, Flutter analyzer/tests/web build, and Android
build when the local toolchain supports it. Record external configuration, device, data/media,
or provider limitations explicitly. Do not report unverified or externally blocked flows as 100%.
No production data cleanup or external messages are authorized by this implementation task.
