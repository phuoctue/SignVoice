# Fixed component comparison — registered 22 October 2026

Purpose: compare complete recognition streams from the **currently selected app bundle**, and replay known TRAIN examples of rau through that same feature/runtime path. This does not train a model, open a final audit, select deployment policy or change the running service.

## Frozen inputs

- Model bundle: `ai_service/models/181_2026_10_19_camera640`, manifest SHA256 `af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`.
- Calibration development: the exact **297 video IDs / 157 labels** listed in this model's `word_validation_stream.rows`. There are no IDs shared with its 11,519 recorded training video IDs. This is distinct from the later Colab reference's 587-clip calibration set.
- TRAIN diagnostic: all **34 rau clips** present in that model's recorded training IDs, 33 namwu and one user dictionary clip. These do not contribute to calibration metrics.
- Source mapping: the previously saved `previous_source_split_manifest.csv`; each selected label must match the label recorded in the app model. No aliases or semantic relabeling.
- RGB source archive: `SignVoice_Dataset_ToanBo_MoRong_2026-10-16.zip`. All 331 members were found. Each video's SHA1 must match the manifest content hash before extraction; SHA256 is also saved.
- The exact cohort, labels, sources, groups, model/config/code hashes and evaluator hash are written to `contract.json` before evaluation. No selection based on the new results. Smoke uses a separate directory and fixed ten-clip subset, and is not evidence of improvement.

## Input stream

Re-extract source RGB with the pinned runtime: source frame clock, causal sampling up to 15 Hz, width 640 with aspect ratio retained, no mirroring, CPU VIDEO MediaPipe detector, two-hand target, foreground filter, tracked hand slots and measured synchronous face context. Optical-flow assistance is off. Existing old feature caches are not imported.

All variants consume exactly the same newly extracted pose/wrist/context/timestamp arrays, including no-hand samples. Models share memoized neural outputs for identical inputs; window selection, smoothing, readiness, dwell and completed events are recomputed separately for each variant. A repeated-reference control at the end must match all per-observation smoothed vectors (`atol=2e-5`, `rtol=5e-4`), event histories, prediction-step counts and rejection counts. A failed control stops the run.

This is a canonical offline stream comparison. CPU detection and synchronous context are not identical to Chrome GPU detection and the app's asynchronous context worker. Re-extracted reference numbers must therefore not be presented as reproducing the original exported calibration figures or as app/desktop pixel-extraction parity. Extraction cache identity and SHA256 are stored per clip. Offline wall time is not a phone latency measurement.

## Registered variants

All use the current decision policy: `min_score=min_dynamic_score=0.60`, `min_margin=min_dynamic_margin=0.20`, `word_dwell=0.30` seconds, current mode-specific prediction cadence and current temperatures. No score, margin, dwell or temperature search.

1. `reference`: unchanged probability ensemble, TCN weight 0.50.
2. `tcn_words`: calibrated TCN distribution, including its background class.
3. `embedding_words_tcn_background`: embedding conditional word distribution scaled by `(1 − TCN background)`, retaining the TCN background mass. This is **not** an embedding-only background detector.
4. `embedding75`: same ensemble with fixed TCN weight 0.25 / embedding share 0.75, motivated by the exposed camera observations. This is a development hypothesis, not an independently chosen optimum.

Both neural models may still be executed internally to share calculations; component variants here compare word scores, not inference cost or proposed mobile packaging.

## Reading the results

Per clip: prediction is the last completed `LiveSession` event, or None. Preserve full emitted event histories. Report correct / wrong / no event, accepted precision, coverage, macro recall over labels actually represented, wrong events and consecutive duplicate events. First correct time is measured from the source clip start, not annotated gesture onset. Never present it as physical-camera latency.

Keep calibration, calibration excluding unverified chào/KhangCN, and TRAIN rau diagnostics separate. Include per-label counts and source breakdown; 24 unsupported-by-calibration words, including bàn tay, cannot be evaluated here. Lack of independently verified signer IDs means source/group clustering is not signer holdout.

Paired uncertainty: 2,000 seeded cluster resamples using a linearized macro-recall difference with fixed class weights and centered per-class residuals. This avoids discarding almost every replicate when rare labels disappear from a resample. The interval remains descriptive on repeatedly exposed development data; it is not a claim about new signers. Record gained/lost clips and precision/wrong-event deltas alongside the interval.

No automatic winner or promotion. In particular, a positive macro-recall delta cannot override more wrong events, a calibration precision floor below 95%, missing word coverage, uncertain labels or absent real-background evaluation. No false accepts/minute can be measured without real non-signing background. All variants remain development-only even if a point estimate looks better.

## Reproducibility and recovery

Implementation: `ai_service/evaluate_fixed_components.py`. Two isolated worker processes maximum; the primary process alone appends the result journal. Features and progress are saved per video. Re-running the same command resumes verified journal entries. Code, cohort or model changes require a new output directory. Intermediate results are incomplete and must not drive conclusions.

Smoke output: `.runtime/component-comparison-20261022/smoke-final/`.
Full output: `.runtime/component-comparison-20261022/full/`.
The old smoke directories are engineering runs, not additional model evidence.

From the repository root in PowerShell:

```powershell
.\ai_service\.venv\Scripts\python.exe -m ai_service.evaluate_fixed_components --model-dir ".\ai_service\models\181_2026_10_19_camera640" --archive "E:\WorkSpace\SignVoice\SignVoice_Dataset_ToanBo_MoRong_2026-10-16.zip" --manifest "C:\Users\Phuoc Tue\Documents\Codex\2026-10-08\https-colab-research-google-com-drive\notebook_audit_20261020\previous_source_split_manifest.csv" --output ".runtime\component-comparison-20261022\full"
```
