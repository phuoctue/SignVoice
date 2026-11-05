# Camera regression and retraining revision — 19 October 2026

The existing 181-word model still fails this six-sign webcam regression. This revision does not claim that new weights have been trained or that webcam accuracy is fixed.

## Evidence

- Recording: `Recording 2026-10-19 132829.mp4` (48.43 seconds). The corresponding service trace is `.runtime/camera-replays/20261019T062826Z_6c14b743.npz` (615 frames, 51.06 seconds including time outside the recording).
- The trace confirms `probability_ensemble`, embedding weight 0.5, and 604 browser-GPU observations plus 11 CPU observations. The median service receive rate was 11.5 FPS. Hands appeared in 65.2% of the entire session, including waiting/rest; this is not a measured active-sign detector recall.
- Emitted labels were `không biết` twice, `mèo`, and `giới thiệu`. Both branches ran. Frozen-coordinate diagnostics sometimes put `nhìn` or `bàn tay` first in the embedding branch while the TCN preferred another class. These diagnostic windows are not certified gesture boundaries or a benchmark proving one model superior.
- Source label mapping explicitly aliases KhangCN `xin_chao` / `xin_chào` to `chào`. Spelling equivalence does not certify gesture equivalence across people/regions. No automatic relabeling from model predictions was performed.

## App changes

- With valid current-frame browser landmarks, the service skips duplicate CPU Lucas–Kanade/corner work. OpenCV still handles image conversion where needed, hull/quality diagnostics, and CPU recovery when browser observations are unavailable.
- The browser worker can deliver measured landmark previews before JPEG encoding finishes. The service still receives the matching JPEG and XYZ timestamp together. Older clients opt out of this extra preview message automatically.
- Window deduplication now includes the measured observation mask. A regression test demonstrated that a low-coverage window previously hid an identical-feature window with sufficient measured evidence.
- A future notebook export can carry its ensemble policy inside its checksum-verified configuration. The service checks both model hashes before activating it. The currently selected weights and operating thresholds were not fitted to this recording.
- Service V7 continues to use the selected 181-word export with both models. LM Studio remains disabled for camera recognition.

On an identical 61-packet prerecorded JPEG/XYZ protocol replay, median service processing fell from 5.2 ms to 1.4 ms; p90 fell from 29.4 ms to 4.9 ms. This isolates service processing, not browser detector FPS, webcam accuracy, or APK performance.

## Same Colab notebook, retraining required

Notebook ID: `1Jo-DuBTsrOxbaj8ZLme315iG0v9p7zZW`. No new remote notebook was created. Original downloaded content is retained in the local audit workspace for rollback.

- Original source VAL/TEST groups remain intact. Additional internal validation groups are reserved from source TRAIN, retaining at least four original training recordings per word. On the archive manifest before landmark QC, VAL coverage increases from 29 to 173 of 181 requested words: TRAIN 12,050 → 10,310, VAL 57 → 1,797, source TEST remains 58. Unknown signer IDs remain unknown; these are not verified unseen-person splits.
- Validation groups are further separated into epoch selection and policy calibration. Neither model chooses its epoch using the calibration subset. Per-word coverage is exported as `validation_coverage.csv`.
- Both encoders and the word classifier use label/source/session-balanced sampling. Frequency loss weighting is not stacked on top. Calibration uses source VAL only and reports macro recall, incorrect accepts and causal emitted events.
- Word encoder inputs and prototype construction always use complete sequences, including words classified as low-motion. They no longer silently tile a representative still frame while the deployed word head queries a full sequence. Static tiling remains for ordinary glyphs only.
- TRAIN augmentation keeps pose, wrist, face context and clocks aligned. It samples lower frame rates, short masked hand gaps, face dropout, and actual boundary rests around complete gestures. It never turns an arbitrary partial sign into background or claims synthetic augmentation creates new people.
- TRAIN video extraction uses width 640 and the browser's pinned confidence settings, with a new versioned cache. RGB CPU/GPU detector implementations are still not assumed numerically identical.
- Policy candidates include TCN operating points and probability ensembles. Cosine similarities are converted to a conditional word distribution; the TCN background probability is retained. Candidate promotion requires a source-calibration causal replay check, including accepted/event precision. If no candidate passes, the fixed baseline remains and the report explains the outcome.
- Inactive numeric Multi-VSL/body experiments and duplicated embedded runtimes were removed from this camera run. A single shared source is executed for validation and exported verbatim. The deployed feature schema remains hand/wrist/face; no shoulder or elbow features were silently added.
- Unused DTW word templates are omitted. The geometric template bank is restricted to letters/digits, while neural word heads retain the word vocabulary. TRAIN causal diagnostics are bounded to two deterministic clips per word; full clean-class diagnostics remain.
- Model outputs go into new `rgb_camera_retrain_2026_10_19` / `words_camera_retrain_2026_10_19` folders, preserving old exports. Old notebook outputs/widget state were cleared so old accuracy is not attached to new code.

There are still no new independent real TRAIN sessions or everyday background VAL clips. Background false-accept performance remains unknown. Labels without validation and long clips exceeding the live buffer are reported explicitly.

## Verification and use

- 39 Python service tests, 109 Flutter tests, 8 worker tests, and seven notebook contract tests passed.
- CELL 6 executed one actual optimization step for each model on synthetic coordinates, then saved/reloaded them with exact weights and consistent outputs. These scratch models are not production artifacts.
- CELL 6B was executed against the previous source-VAL feature cache and old weights to test code paths and promotion/fallback. Those results are code validation, not performance of a newly trained model.
- Changed Dart files passed focused analysis and the Flutter web release build succeeded. Whole-repository analysis also encounters old archived Dart snapshots under `ai_service/reports/.../before/` and unrelated lints; those snapshots were not rewritten as part of this fix.
- Remote notebook updates use a content-hash overwrite guard and byte-for-byte readback verification. No Colab training has been launched by this revision.

Reload the existing Colab page, restart its runtime, and run CELL 1 through CELL 9. Review `word_calibration_report.json`, `word_engine_validation.json` and `validation_coverage.csv` before activating the resulting bundle. Keep this recording as frozen regression evidence; do not put it into TRAIN or use it to choose thresholds.

For the app's new browser code, quit the existing Flutter command with `q` and run the same release command again on port 8080, with AI service port 8001. A physical webcam/phone performance check is still required.
