# Account password management implementation plan

**Goal:** On the freshly pulled dev branch, expose personal password changes with current/new/repeated-new fields and add admin password resets for other local accounts, then leave the verified changes locally for the user's testing.

**Publication approval:** After the local testing checkpoint below, the user explicitly requested pushing the completed changes to dev. The earlier local-only hold is lifted; private configuration and the Word report remain excluded.

**Architecture:** Reuse existing /auth/change-password, hashing, passwordVersion and session invalidation. Add a strict /admin/users/:id/password endpoint using existing users:write and target permission hierarchy. Reject self-service bypass, guest/social/deleted targets; preserve account status. Reset hash/version, clear reset tokens and revoke sessions atomically, with a password-free audit record. Use shared guided password inputs in a profile screen and an owner-bound admin dialog.

**Constraints:** Keep .env and untracked Bao_cao_SignVoice.docx private and untouched. Do not reset real user passwords during verification. Preserve existing OAuth/JWT/login contracts. Hold changes locally until user acceptance; the subsequent explicit request to push dev supplies publication approval.

- [x] Add regression coverage for personal form validation/retry/session clearing and admin reset permissions/validation/old-session invalidation.
- [x] Implement guided personal form/navigation and admin password reset API/form.
- [x] Document endpoint and UI usage; run focused tests, build, review and verify.
- [x] Build and start Local for user testing; verify HEAD unchanged and no push.
- [x] Answer how to create an independent GitHub repository, distinguishing repository control from existing copyright/license rights (guide in docs/TAO_REPO_RIENG.md).

## Verification

- 40 backend tests passed: account passwords, admin management, authorization/security and password reset. A newly generated isolated test database was removed after execution.
- 31 Flutter tests passed: password forms, admin workspace, OAuth and password reset. Existing admin test fixture now injects in-memory AppState; OAuth tests follow current login UI rather than removed setup copy.
- TypeScript build and release Flutter web build passed; OpenAPI valid with 107/107 documented routes.
- Review caught uppercase ObjectId self-reset bypass and stale actor authorization; both fixed and covered by regression tests. Reviewer confirmed the fixes.
- Restarted Local at http://localhost:3002. Real local HTTP self-change test passed: wrong current password retains session, old sessions/password stop working, new password login succeeds. Temporary verification account deleted.
- Local testing checkpoint: original .env and the untracked Word report preserved; HEAD was 2f1a8ac on dev. No commit, push, repository copy or remote change had been performed at that point.
