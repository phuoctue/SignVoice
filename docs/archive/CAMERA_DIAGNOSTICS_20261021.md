# Camera diagnostics — 21 October 2026

## Close the context/sampler training experiment

The existing app model and policy remain unchanged. The sampler experiments do not provide consistent evidence of improvement across the two seeds. Failure to meet the gate means insufficient evidence, not proof that context or sampling cannot help.

Calibration development set: 587 videos. C/W/N = correct/wrong/no final result. These are development results, not independent webcam accuracy.

| Run | C | W | N | Accepted precision | Wrong events |
|---|---:|---:|---:|---:|---:|
| Reference 42 | 341 | 30 | 216 | 91.91% | 59 |
| Sampler 42 | 338 | 29 | 220 | 92.10% | 50 |
| Reference 137 | 323 | 34 | 230 | 90.48% | 59 |
| Sampler 137 | 334 | 32 | 221 | 91.26% | 56 |

Epoch VAL (667 videos) wrong events: reference 42 **76 → 79** with sampler; reference 137 **78 → 48**. The direction is inconsistent. Reference 137's 78 is close to reference 42's 76, so this metric alone does not establish that reference 137 is an outlier. Precision also moves in opposite directions (89.80% → 87.25%; 88.78% → 92.51%).

Reference 42/137 calibration final-label disagreement: **156/587 (26.58%)**, correctness disagreement **122** (52 gains, 70 losses). Reference 42/sampler 42: **132/587 (22.49%)**, correctness disagreement **97** (47 gains, 50 losses). This is a noise anchor, not a robust variance estimate from two seeds. Event-sequence disagreement also includes timing differences.

Sampler macro-recall deltas on calibration:

- Seed 42: −1.1344 percentage points, CI95 [−4.5690, +2.1937].
- Seed 137: +2.4760 points, CI95 [−1.6441, +5.7803]; 57 gains/46 losses, descriptive McNemar p=0.32448.

Neither CI excludes zero. Neither run meets the calibration precision floor of 95%. Seed 42 also has the previously documented parent-ordering caveat. Do not infer mechanisms from the 97 changed clips: 61 short qualified chains, 33 never-qualified and 3 never-top describe the *failing side* of each comparison. Causal semantic/window-boundary information remains missing.

Evidence: the verified AB/AC/AD outputs in `notebook_evidence_20261020` in the Colab review workspace. Journal/cohort/metric checks covered 1,254 rows; this review did not independently rehash every underlying trace file. No final audit was opened for this camera work.

The selected **app** bundle resolved on disk before this change is `ai_service/models/181_2026_10_19_camera640`, manifest SHA256 `af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`, TCN SHA256 `09b1bb7a6459e4cf1d6df2dc48860df1a57b41ec87927ac439af46d033a2343b`. This is distinct from the frozen Colab reference checkpoint. A service already running in RAM may differ; the diagnostic handshake records the identity actually used by that connection. No bundle selection, weights, thresholds, dwell or ensemble weights are changed here.

## Recording a short diagnostic

After the updated frontend and service have been started normally:

1. Open camera settings. Enable **Ghi chẩn đoán cục bộ**, then **Lưu**. This creates a fresh connection and clears the previous in-memory recording. It does not bypass the camera permission screen.
2. Perform a short 10–20 second sequence, including a brief rest and changing from one to two hands. These clips are development diagnostics, not heldout evaluation.
3. Open settings, turn recording off and press **Lưu**. Reopen settings and select **Xuất bản ghi JSON**. Export before navigating away from the camera screen.
4. Web downloads `signvoice-camera-diagnostic.json`. Android saves into the app's local temporary directory and displays its exact path; use Android Studio **Device Explorer** to retrieve it. Temporary exports are not automatically uploaded or shared.
5. **Xóa bản ghi cục bộ** removes the RAM recording and disables recording. Downloaded/exported copies must be deleted separately in Downloads/Device Explorer. A new connection while recording clears the previous RAM recording to prevent mixing model identities.

Recording is off by default and is not saved in preferences. New diagnostic code writes no service files; it retains bounded in-memory feature batches and sends them over the existing authenticated camera connection to that same client. Existing separately configured `AI_TRACE_DIR` server tracing is independent of this feature. Raw video/images, OAuth tokens, server URLs and account information are not included by the recorder. Landmark coordinates and recognized text are still personal data; share exports deliberately.

Bounds: 600 worker batches or 6 MB serialized worker data; 6,000 client entries or approximately 12 MB client string storage. At the limit, `truncated=true`; replay refuses such exports. Record shorter if necessary. Instrumentation adds serialization/network cost, so use unrecorded sessions as the performance control.

## What the file can establish

- Exact feature vectors consumed **after** foreground filtering, tracking and face-context selection, capture timestamps, worker generation and the `allow_prediction` mask of every consumed batch.
- Full smoothed class-score vectors, completed event history, candidate/dwell/latch/threshold state and window diagnostics available from the pinned runtime. This app's `StableDecision` does not currently expose an explicit rejection-reason trace: `rejection_reason_available=false` marks this, rather than turning an absent field into an empty list interpreted as success. This recording supplies state for further diagnosis; it must not be called a complete per-gate causal trace.
- Model file hashes, effective config/policy, ensemble policy and service/runtime/worker code hashes.
- Available local detector FPS, initialization/detection duration, handedness scores (not detection confidence), sent image dimensions/rotation/encoding duration, receipt/publication times, service drops and worker overruns.
- Missing detection confidence is explicitly null, not invented. No sensor FPS or frame-drop count is inferred from transport FPS.

Replay checks **worker features → recognizer decision/events**. It does not independently rerun pixels → landmarks, service event-delivery adaptation, browser rendering, or physical camera timing. Those remain separate checks. Passing replay is not a claim of sign correctness or generalization.

From the project root in PowerShell, using the exact bundle/code recorded by that session:

```powershell
.\ai_service\.venv\Scripts\python.exe -m ai_service.diagnostic_replay "C:\path\signvoice-camera-diagnostic.json" --model-dir ".\ai_service\models\181_2026_10_19_camera640"
```

The tool refuses model/config/code mismatch, missing/reordered batches and truncated exports. Numeric score tolerance is preregistered: `atol=2e-5`, `rtol=5e-4`; confirmed label, reliability/readiness and completed event label/order/frame must match exactly. No recognition thresholds are changed to make replay pass. On failure, investigate the first mismatching batch before measuring recognition gains.

Latency summaries report sample counts, median and p95. Client RTT uses the same client monotonic clock and counts only the first result per sent image; it includes queueing and service work, **not** one-way network time. Capture IDs are not subtracted from another device's wall clock. Local detection, encoding and worker batches use their own duration measurements. UI delay ends at Flutter's post-frame callback, not at physical screen illumination. Copied service-stage values on delayed publications are raw diagnostics rather than independent new processing measurements. No phone performance claim is made until a physical target device is measured.

## Independent capture stays separate

Lock a new manifest before evaluation: six priority signs (chào, nghe, nhìn, rau, bàn tay, cứu), at least 30 valid clips/sign, five new people, two sessions/person, three repetitions/sign/session (180 total). TRAIN and heldout people must be disjoint; retain signer/session IDs and independent semantic review. Prioritize missing calibration/audit words when expanding. Once used to tune, a heldout set becomes development regression data and needs a new untouched final set.

Real non-signing background calibration and audit use disjoint people, each with at least 1,800 seconds, three people, six sessions, 300 seconds/person, 120 seconds/session and two sessions/person; maximum valid frame gap 0.25 s. Report exclusions and accepted exposure. Promotion requires the registered false-event upper bound ≤0.10/minute and the other existing gates. These data have not been collected by this implementation. Keep them locked; do not tune policies from the already exposed videos.

Next evidence needed: an exported short recording from the actual app, successful identity-matched replay, then median/p95 stage measurements on the target phone and PC. Only a demonstrated technical fault should lead to one targeted pipeline fix and regression test. No additional training or automatic policy promotion is warranted by this implementation alone.
