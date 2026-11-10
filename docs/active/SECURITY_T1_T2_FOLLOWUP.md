# T1/T2 security follow-up

Scope: integrate the uncommitted Claude T1/T2 work on a new branch without modifying
their worktrees. No database/schema/package changes or collection-route changes.

## Public proxy deployment gate

`start-signvoice.ps1 Public` now requires an explicit `-TrustProxy` argument.
Local mode always uses `false`. Do not blindly set `true` or assume a hop count.
The public script restores the previous process environment after startup.

Before selecting a value, verify the actual Conveyor edge from two independent
clients using an isolated staging service: it must append/overwrite X-Forwarded-For
so that Express selects the real client from the right of the chain; repeat with
a forged leftmost XFF value and confirm it does not become the selected client.
Restrict direct access to the backend port, and trust only the observed proxy chain.
If the tunnel supplies no trustworthy client IP, keep public deployment blocked
and use an edge with verified forwarding/edge rate limiting before deploying T2.

The four IP-limited auth endpoints return 503 when production proxy mode still resolves the client
to loopback, before counting limiter budgets. This is a deployment diagnostic,
not proof of Conveyor behavior. Local supertest forwarding tests are simulations.

Limits are in-process MemoryStore counters: one Node process only. Restarts reset
counters and multiple replicas need a shared store or edge limiter in a later task.
Existing OAuth/password-reset thresholds are unchanged.

## Acceptance

- Production refuses development DB credentials, short/default admin passwords,
  enabled Swagger and invalid production CORS origins.
- Swagger is disabled without explicit development mode or a non-production opt-in.
- Public auth endpoints enforce 429; forwarded-IP trust is explicit and tested.
- Full-suite pre-existing failures remain documented separately from new regressions.
- Production tunnel acceptance remains pending; no public tunnel is started by tests.

## Verification results (2026-11-10)

- `npm run typecheck`: exit 0.
- `npm run test:isolated -- tests/env-production.test.ts tests/auth-rate-limit.test.ts`:
  exit 0, 31/31 passed (14 config and 17 limiter/proxy cases).
- `npm run test:isolated -- --maxWorkers=2 --minWorkers=1`: exit 1,
  296 passed / 19 failed, 39 passed / 5 failed test files, 315 tests total.
- Detached baseline dc49b0f, same five failing files, same worker limits:
  11 passed / 19 failed, 5 failed files (30 tests total). Files:
  collection-personal-words, learning, library-sync, mail, sign-collections.
  These are pre-existing assertion failures; full suite is not green.
- The unrestricted-concurrency run additionally encountered MongoDB hook timeouts:
  254 passed / 15 failed and 9 failed files. Bounded run removed those timeouts.
- `npm run lint`: existing missing ESLint configuration; no configuration installed.
- Both PowerShell files parse; public guard rejects nine unsafe/invalid settings;
  `git diff --check` passes. Original sec-t1 and sec-t2 worktrees remain untouched.
- Fresh review round 2/2: PASS with NIT. PS accepts some noncanonical IP syntax
  (e.g. bracketed IPv6/zero-padded IPv4) that Node rejects later; use canonical IPs
  or named `loopback`. Parser alignment remains a follow-up, not an accepted input.
- An initial invalid-value guard check accepted `99` as a .NET shorthand IP and
  unexpectedly launched a tunnel/server using the existing build. The exact newly
  created processes were stopped; shorthand IP acceptance was removed and guard
  checks rerun. No staging-forwarding acceptance is claimed from that launch.

Local logs are ignored `.runtime/sec-followup-{targeted,full,full-bounded,baseline}.log`.
No deployment/commit/merge is approved by these checks. Token telemetry unavailable.

## Conveyor probe acceptance — 2026-11-10

Isolated diagnostic HTTP server on 127.0.0.1:3089, without application/database
access. Real Conveyor requests recorded in ignored .runtime/xff-probe-results.jsonl:

- Desktop external request at 05:00:54 UTC: socket peer loopback; one forwarded IP.
- Forged leftmost XFF at 05:00:56 UTC: supplied documentation address followed by
  the same real desktop egress IP. Conveyor appended the real address on the right.
- Owner confirmed phone 4G screenshot; received at 05:07:23 and 05:08:24 UTC:
  loopback peer and a forwarded IP different from desktop (addresses omitted here).

For this observed single local Conveyor hop, select `-TrustProxy loopback`.
Express stops at the rightmost untrusted client IP; a forged leftmost address
does not become the selected client (also covered by isolated proxy tests).
This conclusion applies to the observed chain, not arbitrary future proxies.
The diagnostic server binds loopback only. The actual application backend still
needs an independently verified direct-port restriction before public rollout;
the diagnostic listener does not establish that restriction for the application.

Guard scope follow-up: 39/39 focused tests passed, typecheck passed, fresh reviewer
PASS. Only login/register/guest/refresh use the guard; Bearer routes reach normal
authentication and OAuth/password-reset are unchanged. No commit/merge performed.

## Remaining work

Public rollout requires verified Conveyor XFF behavior and backend-port access
restriction. The older unset-NODE_ENV OAuth behavior remains a separate legacy
configuration follow-up; this change restricts Swagger exposure without altering
OAuth compatibility. CSP remediation is a separate security task. Existing
`security/` audit documents are preliminary findings, not acceptance evidence for
unreviewed routes, ownership checks or production configuration.
