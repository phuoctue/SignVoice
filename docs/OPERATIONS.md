# SignVoice production operations

Operator reference as of 2026-11-17; run on the production Windows host. This does not authorize deployment or restore.

## Current production

- Checkout E: `E:/WorkSpace/SignVoice/SignVoice`.
- Approved release: `c08ebd111763ba475a78de27a3b07e399c03c2fb` (`c08ebd1`),
  ref `gitlab/release/guest-v1-c08ebd111763`.
- The approved release provides `-LocalOnly`, `-AttachTunnel` and `-ExpectedSha`.
  Deploy only the accepted full release SHA, never an unreviewed dev head.
- Backend + web: `127.0.0.1:3001`; AI: `127.0.0.1:8001`, accessed publicly only
  through the backend `/sign-ai` gateway. Never route directly to 8001.
- Production loads `backend/.env.production.local`, with no fallback to the dev
  `backend/.env` (which points to loopback MongoDB). `npm start` is not the
  production launch procedure; setting only `NODE_ENV=production` is insufficient.
- Database: owner's Atlas M0 cluster, database `signvoice`; no Atlas snapshots
  or point-in-time recovery. Writes since the last usable dump may be lost.

## Start and stop

Use checkout E, not a development worktree. The following launcher command is for a transient local verification session using the verified build. After acceptance, finish the scheduled handoff below; production processes must not remain children of an Orca worker terminal:

```powershell
Set-Location 'E:/WorkSpace/SignVoice/SignVoice'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/start-public-server.ps1 `
  -LocalOnly -SkipBuild -Port 3001 -AiPort 8001 `
  -PublicOrigin https://signvoice.id.vn -TrustProxy loopback `
  -ExpectedSha c08ebd111763ba475a78de27a3b07e399c03c2fb
```

The launcher requires a clean checkout at the full expected SHA and validates
production configuration. `-SkipBuild` reuses artifacts; a matching HEAD alone
does not prove those artifacts were built from that SHA.

Before maintenance, create maintenance.flag as described below and wait for any wrapper to settle, then stop. The Cloudflare route may remain published during an accepted short window (returning 502), or the owner can remove it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/stop-public-server.ps1
```

Do not use `-Local` (that selects development state). The stop command handles
the managed API/AI processes; it does **not** stop the separate Cloudflared
Windows service. As a Windows convenience (not a recorded deployment step), an
elevated owner session can use `Stop-Service Cloudflared` / `Start-Service Cloudflared`.
Cloudflared autostarts after reboot; an existing route stays published and returns
502 until the app server is ready. App recovery is provided by the scheduled task below after this Windows account logs on.
Check local health before restoring any route removed for maintenance.

## Guest v1 environment additions

The production environment adds these keys by name: `SESSION_CHAIN_MODE`,
`SESSION_CHAIN_CONTROL_DB`, `SESSION_CHAIN_CONTROL_COLLECTION`,
`GUEST_LEDGER_DIRECTORY`, `GUEST_LEDGER_HMAC_KEY` and `GUEST_CLEANUP_ENABLED`.
Keep the ledger and owner key outside the repository and backup directory with owner-only ACLs.
Reuse the saved owner key across restarts; never print it or pass it in command arguments.
Cleanup, legacy-retention activation and strict session-chain transitions require separate owner approval.

## Autostart

Owner-managed scripts live at `C:/Users/Phuoc Tue/SignVoice-ops/autostart` with owner-only ACLs.
The owner registers `SignVoice Production Autostart` after review using `register-autostart-task.ps1`.
The interactive-user task stores no password, runs 90 seconds after logon and every 15 minutes,
with StartWhenAvailable and IgnoreNew. After reboot this Windows account must log on;
pre-logon availability is not provided. Other logon/account modes need a separate credential and key-access review.

`pin.json` is the single deploy-updated release pin: accepted full SHA, LocalOnly=true, SkipBuild=true,
ports 3001/8001, origin https://signvoice.id.vn and TrustProxy=loopback.
The wrapper targets only `E:/WorkSpace/SignVoice/SignVoice`, never pulls or builds, and refuses
a dirty or wrong-SHA checkout before cleanup/start. Validate a sibling temporary JSON with
`Read-AutostartPin` from autostart-core.ps1, then replace atomically on the same volume with
`[IO.File]::Replace($temporaryPin,$pinPath,$backupPin)` using an explicit retained backup path.

Before a planned stop/deploy:

```powershell
$root = 'C:/Users/Phuoc Tue/SignVoice-ops/autostart'
New-Item -ItemType File -Path (Join-Path $root 'maintenance.flag') -Force
```

Wait for any running wrapper and its file lock to settle before stopping production.
The flag prevents recovery but cannot cancel an in-flight launcher. Build and run local smoke
at the accepted pin, update pin.json while keeping SkipBuild=true, then stop that transient runtime.
Finish through the enabled scheduled task, rather than leaving services attached to the worker terminal:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/stop-public-server.ps1
Remove-Item -LiteralPath (Join-Path $root 'maintenance.flag')
schtasks /Run /TN "SignVoice Production Autostart"
```

Require fresh STARTED in evidence/autostart.log, API/AI health 200, and listener ancestry independent
of the worker shell before public smoke and observation. Apply the same scheduled handoff to rollback.
Both API readiness and proxied AI health 200 yield ALREADY_RUNNING without a launch.
Network wait is bounded to 180 seconds, followed by at most two launch attempts with bounded
health polling, backoff and managed cleanup. Use internal bounded waits: PT0S on task and both
triggers, AllowHardTerminate=false. Do not force-End the task or add Scheduler kill-on-expiry limits.
Verify the app survives launcher completion and the next 15-minute watchdog tick logs ALREADY_RUNNING.

`check-autostart.ps1` prints task state/result, historical success/failure markers and health.
evidence/autostart.log, LAST-SUCCESS and LAST-FAILED contain UTC timestamps and fixed stage codes;
child output is discarded. `start-production.ps1 -CheckAlreadyRunningOnly` is an enforced read-only probe.
Logs are unrotated; archive them during maintenance as needed. `unregister-autostart-task.ps1` removes
scheduling without stopping the app. Cloudflared remains its independent Windows service.

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
   (`run-daily-backup.ps1 -NoPrune`). Set maintenance.flag and stop; the public route may remain published during the accepted window.
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

## Synthetic guests and cleanup

Each cleanup summary includes `runId`, `startedAt` and `endedAt` (UTC wall clock); candidate failures include only that run ID, user ID, error name and MongoDB error code, never error messages or stacks. A driver operation deadline or server `MaxTimeMSExpired` (code 50) reports `stopped` with an incomplete backlog census rather than a candidate failure; an interrupted candidate keeps the previous cursor for retry. Each stopped run emits `Guest cleanup ALERT: run stopped` with only `runId`, `considered` and `deleted`, so operators can monitor repeated stops. The 30-second budget and certified-drain requirement still apply.

`GUEST_SYNTHETIC_REGISTRY_FILE` is an absolute JSON file path, loaded into a new snapshot at each enabled cleanup run (unset means no exemptions). Production value: `C:/Users/Phuoc Tue/SignVoice-ops/kplus-s/registry.json`. The format is an array of `{ "alias": "G-QA", "kind": "guest", "userId": "0123456789abcdef01234567", "status": "active" }`, or the existing K+S envelope `{ "accounts": [ ... ] }`. All four fields are required strings; kind is `guest` or `permanent`, and userId is 24 hexadecimal characters. Extra fields/metadata are ignored and never logged. Only `guest` entries with status exactly `active` qualify.

An invalid, unreadable, missing, relative-path or oversized (>64 KB) configured file aborts the entire run **before any deletion or media retry**, emits a sanitized ALERT and reports failure; it never falls back to an empty registry. An active registered guest is exempt from cleanup while durable `T_s` is absent or server time is strictly before `T_s+30m`; at and after that boundary it follows ordinary cleanup eligibility. Access/trial/deadline checks remain unchanged. Run summaries count `syntheticExempt`; dry-run reports use category `synthetic_exempt`, without a new lifecycle event.

An explicitly empty registry path is invalid. If the loaded registry contains any active guest, cleanup and dry-run validate and snapshot `T_s` before any writes; a failed control read aborts the whole run with zero deletions and sanitized reason `SYNTHETIC_TRANSITION_UNAVAILABLE` (registry failures use `SYNTHETIC_REGISTRY_INVALID`). Control errors never mean "not exempt".

The dry-run CLI accepts `--synthetic-registry '<absolute-path>'` (or the same environment variable) and uses the same loader/evaluator. Supply the existing nonsecret `SESSION_CHAIN_MODE` and `SESSION_CHAIN_CONTROL_*` settings for the target's control namespace (plus the accepted transition identity/policy settings in enforcement mode); for a DB copy, point only at its copied control namespace. No application `.env` is loaded by the operator script. Using the protected prompt helper below, from `backend/`:

```powershell
Invoke-GuestOp scripts/guest-cleanup-dry-run.ts @('--synthetic-registry','C:/Users/Phuoc Tue/SignVoice-ops/kplus-s/registry.json')
# A remote authenticated COPY also requires --allow-copy matching its copy_* database.
```

## Guest data after a DB restore (manual, v1)

Recovery checklist for an owner-approved restore, **after this v1 code is released**; not permission to execute on production. Rehearse on a disposable loopback copy first. Use a protected operator terminal, outside transcripts, from `backend/`. No reconciliation tool is supplied. URI/HMAC secrets enter only a hidden prompt and the child's stdin:

```powershell
function Invoke-GuestOp([string]$Entry, [string[]]$CliArgs) {
  $secret = Read-Host 'Explicit operator DB URI (or ledger HMAC for verification)' -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
  try {
    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) | node node_modules/tsx/dist/cli.mjs $Entry @CliArgs
    if ($LASTEXITCODE -ne 0) { throw 'Operation incomplete; keep ingress closed' }
  } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secret.Dispose() }
}
```

1. **Close ingress, stop/fence every API/AI writer, job and ledger exporter, including old hosts.** Record backup UTC, its expiry, and certified last possible write time R. Once the DB is reachable, read the control version with the authenticated shell below and pause/drain (use `0` only for a missing control):

   ```powershell
   Invoke-GuestOp scripts/guest-cleanup-control.ts @('pause','--expected-version','<version>','--reason','restore','--operator','<alias>','--wait-drain')
   ```

   Lease expiry alone never proves drain. A crashed/stalled holder blocks certification: establish that its process and transactions have exited, then, while all writers remain fenced, unset **that exact** lease using the step 4 operator wrapper with `await db.collection('guest_cleanup_control').updateOne({_id:'guest-cleanup',paused:true,'lease.holder':'<certified-dead-holder>'},{$unset:{lease:''}},{writeConcern:{w:'majority',j:true}})` and repeat pause/drain with the new observed version. Never remove a live holder. Re-pause the restored control after loading the backup; its state/lease may also have rolled back.

2. **Invalidate ALL restored session authority before reopening**, preserving session rows, epochs and chain tombstones. Require `revoked` output and zero remaining ACTIVE rows; repeat after any subsequent restore:

   ```powershell
   Invoke-GuestOp scripts/guest-restore-invalidate-sessions.ts @('--confirm','--writers-stopped')
   $env:GUEST_GRANTS_PAUSED = 'true'
   ```

   Set `GUEST_GRANTS_PAUSED=true` in **every instance's authoritative launch configuration** before starting it. Keep it set for at least 24 hours after the **actual** reopening UTC, even if the process restarts. It blocks all fresh identities and replacements; known per-device cooldowns still apply later. No automatic timer clears it. Only after that recorded UTC+24h may the owner clear it (`$env:GUEST_GRANTS_PAUSED='false'`, update the same launch configuration, restart all instances through the approved release procedure). A shell variable does not change an already running process.

3. **Verify the external ledger outside the restored DB/dumps.** Fence old exporters and retain originals/checkpoints/locks as evidence. Use protected working copies; substitute the copy directory and stream UUID below. This existing verifier checks sequence, hash chain and HMAC and rebuilds the working checkpoint; enter the HMAC at the hidden prompt:

   ```powershell
   $verify = @'
   (async () => {
     const {readOperatorUri} = require('./scripts/guest-cleanup-operator');
     const {verifyGuestLedger} = require('./src/services/guest-ledger-file.service');
     console.log(JSON.stringify(await verifyGuestLedger('C:/approved-ledger-audit', await readOperatorUri(), '<stream-uuid>')));
   })().catch(() => { console.error('Ledger verification failed; stay closed'); process.exitCode=1; });
   '@
   Invoke-GuestOp '-e' @($verify)
   ```

   Record verified coverage watermark W, sequence/hash and file SHA256. Verify every relevant stream; highest event timestamp is not coverage. Events after W may be lost. If there is a gap, hold every guest granted within seven days before the backup UTC, plus unknown-date and synthetic guests, until resolved. If verified lifecycle coverage starts after the backup, or no W is verified, hold **all** restored guests. Also include any broader cohort required by W−7d (use the earlier of backup UTC and W as the seven-day anchor). Do not infer a lost conversion from guest content.

4. **Replay the verified post-backup evidence manually, in sequence.** Use the existing Node/tsx dependencies and authenticated connection helper. This wrapper initially reads the control version; replace that one statement with **one reviewed operation** below per invocation, supplying the URI at the hidden prompt:

   ```powershell
   $manual = @'
   (async () => {
     const {operatorDatabase,readOperatorUri}=require('./scripts/guest-cleanup-operator');
     const {ObjectId}=require('mongoose').mongo;
     const {client,db}=await operatorDatabase(await readOperatorUri());
     try { console.log(JSON.stringify(await db.collection('guest_cleanup_control').findOne({_id:'guest-cleanup'}))); }
     finally { await client.close(); }
   })().catch(() => { console.error('Manual operation incomplete; stay closed'); process.exitCode=1; });
   '@
   Invoke-GuestOp '-e' @($manual)
   ```

   ```javascript
   // If absent after restore, reinsert the ORIGINAL activation receipt; never restart its seven-day clock:
   await db.collection('guest_retention_activation').insertOne({_id:'legacy-retention',activatedAt:new Date('<original-official-activation>')},{writeConcern:{w:'majority',j:true}});
   // For each verified CONVERTED event whose sameUserId is restored as a guest:
   await db.collection('users').updateOne({_id:new ObjectId('<sameUserId>'),isGuest:true},{$set:{status:'SUSPENDED'}},{writeConcern:{w:'majority',j:true}});
   // Apply the same SUSPENDED hold to every uncertain ID from step 3; keep an external ID/reason/backup-expiry manifest.
   // For each verified GRANTED event (substitute its payload, never a device/install key):
   await db.collection('guest_trials').updateOne({deviceHash:'<deviceHash>'},{$max:{startedAt:new Date('<lastGrantedAt>')},$set:{legacyFallbackDisabledAt:new Date()},$setOnInsert:{lastGrantRequestHash:'<requestHash>'}},{upsert:true,writeConcern:{w:'majority',j:true}});
   // Fence sequence reuse: AFTER all old exporters are stopped, choose a fresh UUID for this recovery.
   await db.collection('guest_lifecycle_counter').updateOne({_id:'lifecycle'},{$set:{streamEpoch:'<new-stream-uuid>',sequence:0,activatedAt:new Date(),exportedSequence:0},$unset:{exportedHash:'',coveredAt:'',lastBarrierAt:'',lastBarrierSequence:''}},{writeConcern:{w:'majority',j:true}});
   ```

   Keep cleanup paused and ingress closed while **any** hold remains: SUSPENDED denies authentication but does not by itself exclude a row from cleanup. Missing original activation evidence also holds the unknown legacy cohort; do not run the activation command again to give it seven more days. Preserve actual permanent users; a restored guest with a known conversion needs manual enrollment recovery, not guest deletion. Resolve every held row before reopening, or delete only at the owner's explicit recovery decision, always before its containing backup expires (RS3). Record decisions externally; never keep an unresolved cohort indefinitely. Keep old stream outbox rows/evidence; never restart an old stream against a rolled-back counter.

   For a verified DISCARDED/EXPIRED_CLEANED ID still present as an unconverted guest (or an owner-approved terminal deletion), use the **same locked deletion primitive**, one reviewed ID at a time. Set an empty disposable configuration file to avoid loading application secrets; this command does not use production config defaults:

   ```powershell
   $recoveryConfig = New-TemporaryFile
   $priorEnvFile = $env:SIGNVOICE_ENV_FILE
   $env:SIGNVOICE_ENV_FILE = $recoveryConfig.FullName
   $deleteKnown = @'
   (async () => {
     const m=require('mongoose'); m.set('autoCreate',false); m.set('autoIndex',false);
     const {operatorDatabase,readOperatorUri}=require('./scripts/guest-cleanup-operator');
     const {client}=await operatorDatabase(await readOperatorUri()); m.connection.setClient(client);
     try {
       const {User}=require('./src/models/User.model');
       const {deleteGuestOwnedData,guestDataVersionFilter}=require('./src/services/guest-data.service');
       const {sessionEpoch,userEpochFilter}=require('./src/services/session-fence.service');
       const {ensureGuestOutbox,appendGuestEvent}=require('./src/services/guest-lifecycle-outbox.service');
       await ensureGuestOutbox();
       await m.connection.transaction(async s => {
         const u=await User.findById('<reviewed-guestUserId>').select('+dataVersion +sessionRevocationEpoch +guestTrialId +guestGrantedAt').session(s);
         if (!u) return; if (!u.isGuest || u.guestConvertedAt) throw new Error('Permanent/converted: stop');
         const v=u.dataVersion, epoch=sessionEpoch(u.sessionRevocationEpoch);
         if (!Number.isSafeInteger(v) || v<0 || v>=Number.MAX_SAFE_INTEGER) throw new Error('Invalid version');
         const locked=await User.updateOne({_id:u._id,isGuest:true,guestConvertedAt:{$exists:false},...guestDataVersionFilter(v),...userEpochFilter(epoch)},{$inc:{dataVersion:1}},{session:s});
         if (!locked.matchedCount) throw new Error('Changed: stop');
         await deleteGuestOwnedData(u,v,epoch,s);
         await appendGuestEvent('DISCARDED',{guestUserId:String(u._id),guestGrantedAt:u.guestGrantedAt?.toISOString()??null,dataVersion:v,committedAt:new Date().toISOString()},s);
       },{writeConcern:{w:'majority',j:true},timeoutMS:30000});
       await require('./src/services/guest-media-cleanup.service').retryGuestMediaCleanup('<reviewed-guestUserId>');
     } finally { await m.disconnect(); }
   })().catch(() => { console.error('Replay incomplete; stay closed'); process.exitCode=1; });
   '@
   try { Invoke-GuestOp '-e' @($deleteKnown) }
   finally { Remove-Item -LiteralPath $recoveryConfig.FullName; $env:SIGNVOICE_ENV_FILE = $priorEnvFile }
   ```

5. **Dry-run and record counts/list before resuming cleanup.** Resolve holds first; authenticate probes must show old access/refresh credentials rejected, unaffected permanent accounts able to log in afresh, expired/private data denied, and fresh guest grants returning 503. Require owner approval of the recovered cohort and list/counts, a new externally exported/verified stream, and a configured off-machine ledger sink before reopening. Resume with current CAS version only when those gates pass:

   ```powershell
   Invoke-GuestOp scripts/guest-cleanup-dry-run.ts @() # explicit loopback target; zero writes
   # For an explicitly named authenticated remote COPY only:
   Invoke-GuestOp scripts/guest-cleanup-dry-run.ts @('--allow-copy','copy_<approved-name>')
   Invoke-GuestOp scripts/guest-cleanup-control.ts @('resume','--expected-version','<version>','--reason','recovery-approved','--operator','<alias>')
   ```

6. **Torn ledger tail (R2-S2): never edit the signed prefix to make verification pass.** With exporters fenced, preserve the entire original JSONL, checkpoint and SHA256. In a new protected audit directory, copy the signed checkpoint and **exactly** its `checkpoint.offset` bytes into `<stream-uuid>.jsonl`; save all remaining bytes separately for audit. Verify that prefix using step 3 and require the returned sequence/hash to equal the copied signed checkpoint. Only after that succeeds and the owner approves may the operator truncate the original at that exact offset, flush it and re-run the verifier on the resulting copy; otherwise stay closed. Exact byte operations (Node REPL, paths/offset from the approved checkpoint; originals are backed up first):

   ```javascript
   const fs=require('node:fs'), file='C:/approved-ledger/<stream-uuid>.jsonl', audit='C:/approved-ledger-audit';
   const saved=JSON.parse(fs.readFileSync('C:/approved-ledger/<stream-uuid>.checkpoint.json','utf8')).checkpoint;
   const bytes=fs.readFileSync(file); // shortcut: copy must fit RAM; use a reviewed streaming copy for larger ledgers
   if (!Number.isSafeInteger(saved.offset)||saved.offset<0||saved.offset>bytes.length) throw new Error('Invalid offset');
   fs.writeFileSync(audit+'/<stream-uuid>.jsonl',bytes.subarray(0,saved.offset),{flag:'wx'});
   fs.writeFileSync(audit+'/removed-tail.bin',bytes.subarray(saved.offset),{flag:'wx'});
   fs.copyFileSync('C:/approved-ledger/<stream-uuid>.checkpoint.json',audit+'/<stream-uuid>.checkpoint.json',fs.constants.COPYFILE_EXCL);
   // STOP: run step 3 on this audit directory, compare its sequence/hash to saved, and obtain approval.
   // Only THEN, in the same fenced recovery, using the same verified saved.offset:
   const fd=fs.openSync(file,'r+'); try { fs.ftruncateSync(fd,saved.offset); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
   ```

Users without a valid credential cannot receive the legacy retention notice; do not claim universal notification. Live logical deletion and media retries do not erase backup copies. Events beyond the last verified watermark remain an honest recovery-loss limit; missing verification, unresolved holds, an unproved writer stop, or a failed session fence keeps the service closed.

## Guest ledger lock recovery

The ledger automatically archives a parseable lock only when its hostname matches this machine and the OS reports its PID absent (`ESRCH`); live or reused PIDs, foreign hosts and unreadable/legacy locks fail closed. For an empty, unparsable or legacy `.guest-ledger.lock`, first verify that **no backend Node process is running from the checkout**, including Task Scheduler/autostart, then rename it to `.guest-ledger.lock.stale-<UTC>-<random>` in the same directory; never delete it. Preserve existing `.stale-*` evidence. A crash during takeover may leave an audit-path reservation and the original lock: after the same process check, archive the original under a fresh name before restarting. SIGINT/SIGTERM already stop the exporter and release its owned lock through the server shutdown path; a hard kill relies on dead-owner recovery.

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
