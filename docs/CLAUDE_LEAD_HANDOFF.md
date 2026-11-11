# SignVoice — Claude lead/reviewer, Codex worker

Snapshot: 2026-11-10, repository `E:/WorkSpace/SignVoice/SignVoice`.
This is a navigation/handoff note, not a complete audit or replacement for source.

## Read first, then only the assigned scope

1. `.agents/AGENT.md`, `docs/ORCHESTRATOR_POLICY.md`, `docs/SPEC.md`.
2. This note, then the relevant heading in `docs/TASKS.md` (avoid loading the whole board).
3. `git status --short --branch`, current diff, and the task-specific files below.

## Working agreement

- Claude owns task definition, scope, acceptance criteria and final review.
- Codex implements one bounded task, runs appropriate checks and reports evidence.
- Claude reviews the actual diff independently; worker claims alone are not evidence.
- Use separate branch/worktree when feasible; maximum two review/fix rounds.
- Audits are read-only. Fixes require a separate implementation task.
- Workers do not push/merge. Lead integrates only with owner authorization.
- Preserve existing changes. Do not edit `backend/src/routes/sign-collection.routes.ts`
  under the existing restricted trial task; obtain a new explicit scope if needed.
- Never print `.env`, tokens, credential-helper output or database credentials.
- Do not delete sec-t1/sec-t2 worktrees: they contain uncommitted Claude work.
- Do not invent token telemetry; current tooling has not supplied it.

## Architecture / source map

Flutter mobile/web: `lib/main.dart` → `lib/app.dart`; navigation/state in `lib/core/`.
Auth state: `lib/providers/auth_provider.dart`. Common UI: `lib/widgets/ui.dart`,
`web_workspace.dart`, `sign_video_surface.dart`. Landing: `lib/features/auth/`.
Learning/collections/quiz: `lib/features/learning/`. Speech/sign sequence:
`lib/features/speech/`. Camera: `lib/features/recognition/`. API clients: `lib/services/`.
Flutter tests: `test/`, `integration_test/`.

Backend: Node/TypeScript/Express/Mongoose. Startup: `backend/src/server.ts`;
middleware/CSP/CORS/router setup: `backend/src/app.ts`; config: `backend/src/config/`.
Routes → controllers → services → models under `backend/src/`; tests: `backend/tests/`.
Public startup: `scripts/start-signvoice.ps1`, `scripts/start-public-server.ps1`.
AI public bridge: `backend/src/ai-public-proxy.ts`; AI Python source: `ai_service/`.

## Git state and completed security work

- Local `dev` and GitLab `dev` verified at `57c4c43` after successful push.
- Existing Claude lead worktree `C:/Users/Phuoc Tue/orca/workspaces/SignVoice/SignVoice-Lead`
  is still at `5aafc40` in this snapshot. Check its dirty state, fetch GitLab and
  integrate current dev before reviewing new work; preserve any local edits.
- GitLab remote: `https://gitlab.com/signvoice/SignVoice.git`.
- GitHub remotes are separate. The displayed `ahead 20` is versus `phuoctue/dev`,
  not GitLab; do not push GitHub merely to clear that message.
- `a8e6271`: production config validation, auth rate limits, proxy guards/scripts.
- `05279d0`: preliminary security audit documents (not confirmed audit coverage).
- `acef193`: incorporates GitLab dev, including previously merged UI changes.
- `57c4c43`: production binds `127.0.0.1`; development/test bind `0.0.0.0`.
- Ignored local `backend/.env`: legacy `ADMIN_PASSWORD` now empty. It is not an
  account password; weak nonempty values still fail production validation.
- Public command: `./scripts/start-signvoice.ps1 Public -SkipBuild -TrustProxy loopback`.
  Build backend first after source edits; omit SkipBuild when appropriate.
- Conveyor observed appending real IP after forged leftmost XFF; `loopback` is
  appropriate for that observed single-local-proxy chain, not arbitrary proxies.
- Proxy503 guard applies only to register/login/guest/refresh; Bearer endpoints,
  OAuth and password reset retain their separate behavior.
- Owner confirmed real 4G login/use/logout; logs matched with no new auth errors.
  This does not establish OAuth, refresh/logout races or token replay acceptance.
- Runtime metadata/logs are ignored in `.runtime/`. Read selected fields only;
  saved public URLs/process IDs may change. Do not blindly stop saved PIDs.

## Checks and known baseline

- Last implementation verification at this source: backend build and focused
  env-production + auth-rate-limit tests PASS, 41/41; fresh review PASS.
- Bounded full-suite historical result: 296 PASS / 19 FAIL; the same 19 failures
  reproduced on baseline dc49b0f in collection-personal-words, learning,
  library-sync, mail and sign-collections. Do not call the full suite green.
- ESLint has no config in the existing repo; lint failure is pre-existing.
- Ordinary checks from backend/: `npm run typecheck`, `npm run lint`, `npm test`.
  Focused: `npm run test:isolated -- tests/env-production.test.ts tests/auth-rate-limit.test.ts --maxWorkers=2 --minWorkers=1`.
- Flutter: `flutter analyze`, scoped `flutter test` as relevant.
- Before commit: inspect diff, `git diff --check`,
  `node scripts/check-readme-download-links.cjs`.
  Before push also run `node scripts/check-readme-download-links.cjs --ref HEAD`.
  Keep `.githooks` enabled; never bypass hooks.

## Remaining security tasks: read narrowly

1. CSP: `backend/src/app.ts`, Flutter web bootstrap/build configuration and media
   source requirements. Inline scripts/CDN/general https sources remain allowed.
   This is hardening evidence, not a demonstrated XSS exploit.
2. Staff / cross-account isolation: `routes/admin.routes.ts`, `staff.routes.ts`,
   matching controllers, `services/authorization.service.ts`, `models/Role.model.ts`,
   `common/middlewares/auth.middleware.ts`, plus each selected data service.
   Admin routes have module permissions; collection owner queries include userId.
   Need a per-operation two-account/permission matrix; no whole-repo IDOR pass claimed.
3. OAuth / session lifecycle: `services/oauth.service.ts`, OAuth controller/config/
   provider code, `services/auth.service.ts`, `models/AuthSession.model.ts`, auth
   middleware and related tests. State is one-use/browser-bound; Google uses PKCE.
   Refresh claims the token atomically; logout revokes the session family;
   middleware validates persisted session. Investigate refresh/logout concurrency,
   callback identity validation and account linking before claiming replay safety.
4. Dependencies / scaling: `backend/package.json`, package lockfiles, deployment
   scripts, `common/middlewares/auth-rate-limit.ts`. No fresh advisory result yet.
   Limiter uses default process memory; shared store/edge enforcement needed before
   multiple replicas. CIDR allowlist tightening and proxy-parser consistency remain.

Prior notes: `docs/active/SECURITY_T1_T2_FOLLOWUP.md`, `security/AUDIT_SUMMARY.md`.
They contain historical pending states and preliminary severity claims; use current
source/evidence above instead of treating those claims as confirmed vulnerabilities.

Security-audit skill requires OS-enforced isolated execution and prohibits live
security probes. Current focused review was static; execution validation needs an
appropriate sandbox. Do not run test scripts against the live MongoDB/public app.

## Small worker task template

Objective: one concrete behavior. Inputs: exact files and source ref.
Allowed edits: explicit paths. Outside scope: auth/schema/dependencies unless granted.
Acceptance: observable before/after plus relevant regression checks.
Return under 10 lines: changed files, evidence, failures/baseline, risks and commit.
Claude then reads the diff and checks acceptance; commit/push/merge only as authorized.

## Reading budget: workers and reviewers

These are default budgets, not permission to skip evidence or mandatory instructions.
Claude includes a read allowlist in every task; expand it only for a concrete dependency.

- Worker: start with 3–6 named source/test files and one task excerpt. Normally keep
  a task within 10 relevant files. Read mandatory project instructions separately.
- Reviewer: start with the task brief, base/head refs, diff stat, full scoped diff
  and relevant test results. Follow changed symbols into their callers/security
  boundaries as needed; do not reread the entire worker conversation or repository.
- Search filenames first with `rg --files`, then search symbols within named folders
  using `rg -n`. Read the matched function and surrounding context before expanding.
- Do not dump lockfiles, generated models, bundled JS, large logs, all of TASKS.md,
  all skills, or all previous audit reports into context. Extract relevant entries.
- Select a skill because its workflow fits the task. Read its required instructions
  fully, but load supporting references only when the skill/task requires them.
- If evidence requires more files, state the missing relationship and extra paths
  in the short result. Routine read-only expansion can proceed without waiting for
  owner approval; changing edit scope must be coordinated with the lead.
- Never stop tracing auth, ownership or data flow merely to meet a file/token cap.
  If the task is too broad, return the evidence and a proposed split to Claude.
- Avoid repeated reads/checks when source and evidence have not changed. Recheck
  changed paths and affected behavior after revisions; include exact source refs.

## Task sizing and model selection

Claude chooses one observable objective per task. Each brief contains input paths,
allowed edits, dependencies, acceptance checks, outside scope and risk level.

- Small: copy, spacing, isolated styles or documentation; normally 1–3 edited files.
  Use an available economical model and a short focused check.
- Medium: one component/endpoint behavior and its regression tests; normally 3–6
  edited files. Use a coding model appropriate to the logic involved.
- High risk: auth/session lifecycle, permissions, data isolation, migration or
  deployment trust. Give each invariant its own task and use a stronger worker
  plus independent review; keep owner approval gates required by project policy.
- Separate investigation from implementation when the cause is not established.
  An audit task returns source evidence and a narrow proposed fix, not source edits.
- Split tasks that combine unrelated features, require broad refactoring, or have
  independent acceptance criteria. Do not split a security invariant so that no
  worker/reviewer owns the end-to-end boundary.
- Run tasks concurrently only when edit sets and dependencies do not overlap;
  serialize shared-file work and review the combined integration afterward.
- A reviewer checks requirements, regressions, tests and scope; unrelated cleanup
  becomes a separate task. After two fix/review rounds, report unresolved blockers.
- Select only models actually exposed by the runner. A prompt alone cannot switch
  the current session's model; choose it when launching a worker if supported,
  otherwise report that limitation. Do not claim an automatic switch occurred.
- Lower pricing does not itself reduce token count. Control context size, repetition
  and task scope; increase reasoning capability when repeated failed fixes cost more.

Worker/reviewer result: source ref, files changed/reviewed, commands and outcomes,
concrete findings with file/line, remaining gaps. Aim for under 10 lines; put long
logs in the task's designated local artifact location, without secrets.
