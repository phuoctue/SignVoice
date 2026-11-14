# SignVoice production operations

Operator reference as of 2026-11-14; run on the production Windows host. This does not authorize deployment or restore.

## Current production

- Checkout E: `E:/WorkSpace/SignVoice/SignVoice`.
- Approved release: `86393eca2e7eec6eece25124d5674bd2a56a64a1` (`86393ec`),
  ref `gitlab/release/logout-all-a-86393eca2e7e`. This is **not** dev head `f89ea47`.
- `-LocalOnly`, `-AttachTunnel` and `-ExpectedSha` exist only on that release pin
  (branch `release/logout-all-a-86393eca2e7e`); the release has not been merged into
  dev `f89ea47`, which lacks these flags. **Do not deploy from dev.**
- Backend + web: `127.0.0.1:3001`; AI: `127.0.0.1:8001`, accessed publicly only
  through the backend `/sign-ai` gateway. Never route directly to 8001.
- Production loads `backend/.env.production.local`, with no fallback to the dev
  `backend/.env` (which points to loopback MongoDB). `npm start` is not the
  production launch procedure; setting only `NODE_ENV=production` is insufficient.
- Database: owner's Atlas M0 cluster, database `signvoice`; no Atlas snapshots
  or point-in-time recovery. Writes since the last usable dump may be lost.

## Start and stop

Use checkout E, not a development worktree. To restart the verified build at the approved pin:

```powershell
Set-Location 'E:/WorkSpace/SignVoice/SignVoice'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/start-public-server.ps1 `
  -LocalOnly -SkipBuild -Port 3001 -AiPort 8001 `
  -PublicOrigin https://signvoice.id.vn -TrustProxy loopback `
  -ExpectedSha 86393eca2e7eec6eece25124d5674bd2a56a64a1
```

The launcher requires a clean checkout at the full expected SHA and validates
production configuration. `-SkipBuild` reuses artifacts; a matching HEAD alone
does not prove those artifacts were built from that SHA.

Before maintenance, remove the public hostname route in Cloudflare, then stop:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/stop-public-server.ps1
```

Do not use `-Local` (that selects development state). The stop command handles
the managed API/AI processes; it does **not** stop the separate Cloudflared
Windows service. As a Windows convenience (not a recorded deployment step), an
elevated owner session can use `Stop-Service Cloudflared` / `Start-Service Cloudflared`.
Cloudflared autostarts after reboot; an existing route stays published and returns
502 until the app server is started manually (it does **not** autostart).
Check local health before restoring any route removed for maintenance.

## Health and acceptance

```powershell
Invoke-RestMethod http://127.0.0.1:3001/health/ready
Invoke-RestMethod http://127.0.0.1:3001/sign-ai/health
Invoke-RestMethod https://signvoice.id.vn/health/ready
Invoke-RestMethod https://signvoice.id.vn/sign-ai/health
```

Require HTTP 200 and successful readiness/AI responses; open the public UI too.
Anonymous `/api/v1/auth/me` should return 401, not a cached authenticated response.
For a release, use dedicated QA identities for HTTPS login/refresh/logout-all:
revoked access and refresh credentials must fail with 401; check OAuth redirects
use `https://signvoice.id.vn`. Observe for 30 minutes after reopening.
Inspect `.runtime/public-server.log`, `.runtime/public-server.error.log` and AI logs locally; share only sanitized status, hashes and timestamps.

## Deploy a pinned release

1. Obtain the owner's approved full SHA and release ref; take and verify a backup
   of the **current** cluster using the [manual backup procedure](#backup-freshness-and-restore)
   (`run-daily-backup.ps1 -NoPrune`). Remove the public route and stop.
2. Fetch that exact release ref in E, verify its resolved commit against the
   approved full SHA, and advance the clean production checkout to that pin
   (`--ff-only` where applicable). Stop on mismatch, dirty files or divergence.
   **Never `git pull` then start; never deploy the dev head by default.**
3. Run the start command above with the approved full `-ExpectedSha`, omitting
   `-SkipBuild` so backend and relative-origin Flutter web artifacts are rebuilt.
   Require the configuration gate and local health/auth smoke to pass.
4. Verify only loopback listeners on 3001/8001, then restore the single Cloudflare
   route. Run external health/auth checks and observe. Keep the release pin,
   build evidence and sanitized results in the release record.

## Public tunnel

- Named tunnel: `signvoice-production`; Windows service: `Cloudflared`.
- Only public hostname route: `signvoice.id.vn` → `http://127.0.0.1:3001`.
- `TRUST_PROXY=loopback` was verified against the Cloudflare chain using PC
  forged-XFF and phone/4G probes; do not substitute `true` or an arbitrary hop count.
- Conveyor and launcher `-AttachTunnel` are legacy and are not this ingress path.
- After a proxy/topology change, re-probe client-IP handling before reopening.
- Check edge certificate, HTTPS redirect and cache rules; API and `/sign-ai`
  responses must bypass cache. The go-live record left Always Use HTTPS,
  owner browser Google-login acceptance and observation completion open;
  do not assume those later steps passed without new evidence.

## Backup, freshness and restore

- Scripts: `C:/Users/Phuoc Tue/SignVoice-ops/backup-scripts`.
- Scheduled task **SignVoice Daily DB Backup**: daily at **03:00 local**,
  Interactive/current user, no stored password; the owner must be logged on.
  Catch-up is enabled, but execution and failures still need operator checks.
- Encrypted daily dumps: `C:/Users/Phuoc Tue/SignVoice-ops/backups/daily`.
  Retention keeps the union of 7 daily, 4 Sunday and 3 first-of-month successful
  backups; unowned/failed directories are preserved and can increase disk use.
- Check task Last Run Result/history and `SignVoice-ops/evidence/daily-backup.log`,
  `LAST-FAILED` and `LAST-SUCCESS`. Run the read-only freshness check:

```powershell
powershell.exe -NoProfile -File 'C:/Users/Phuoc Tue/SignVoice-ops/backup-scripts/check-backup-freshness.ps1'
```

`FRESH`/exit 0 means the success marker is at most 26 hours old; `STALE`/exit 1
includes missing/invalid markers. This is **not** an automatic alert or proof of
restorability. Investigate stale/failure state; an owner can rerun the reviewed
`run-daily-backup.ps1 -NoPrune` manually and confirm success/freshness afterward.
Keep an encrypted off-machine copy and offline keys separately; these are owner
actions, not guaranteed by the scheduled task.

For a restore drill, use `drill-daily-backup.ps1`: it invokes `restore.ps1` against
a disposable mongod bound only to `127.0.0.1`, verifies archive SHA256/HMAC and
compares all collection counts with the manifest. Prior drill: 26 collections,
5,186 documents matched; independent source content/index equivalence was not
proved. Keep drills on loopback; do not pass `-AllowRemoteTarget` or `-ApproveDrop`
for routine drills. A real production restore needs a separate reviewed plan.

## Incidents and rollback

1. Remove `signvoice.id.vn` from the tunnel's public hostname routes for instant
   unpublish. Do this for auth/revocation failures, 5xx spikes or
   `PROXY_CLIENT_IP_UNAVAILABLE`; preserve sanitized evidence and notify the owner.
2. Check local readiness, listeners, Cloudflared status, database connectivity,
   backup freshness and the expected release/configuration. Do not print secrets.
3. Repair and repeat local checks before restoring the route and external smoke.
4. **Never revert to old database data after writes or revocations**, including
   smoke writes before reopening: this can resurrect sessions/epochs. Roll forward
   on the current cluster; any recovery from a verified current-cluster backup
   requires explicit handling of lost writes/revocations in the recovery plan.

## Secrets location map (paths only; never paste contents)

- `E:/WorkSpace/SignVoice/SignVoice/backend/.env.production.local`
- `E:/WorkSpace/SignVoice/SignVoice/backend/.env.target-cluster.local`
- `E:/WorkSpace/SignVoice/SignVoice/backend/.env.production.pre-move-*.local`
- `E:/WorkSpace/SignVoice/SignVoice/backend/.env.recovery-20261113.local`
- `C:/ProgramData/cloudflared/token`
- `C:/Users/Phuoc Tue/SignVoice-ops/owner-keys/passphrase.key`
- `C:/Users/Phuoc Tue/SignVoice-ops/owner-keys/mac.key`

Source records: Lead task folders `SEC-CLOUDFLARE-TUNNEL/plan.md` (GO-LIVE), `SEC-DB-CLUSTER-MOVE/{plan,final-checklist}.md`, `SEC-DB-DAILY-BACKUP/report.md` and `SEC-LOGOUT-ALL-DEPLOY-PLAN/release-record.md`.
Earlier draft/paused states are superseded by go-live and the installed scheduler definition.
