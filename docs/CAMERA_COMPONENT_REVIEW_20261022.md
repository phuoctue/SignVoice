# Camera component review — 22 October 2026

This is a development diagnosis of `Recording 2026-10-21 235518.mp4` and its matching JSON, not a training run or independent accuracy evaluation. No model, threshold, ensemble weight, app runtime or public service was changed by this component inspection.

Input JSON SHA256: `688c8a7787214c0a3d5ec7c90c7b289f8e4e9859b58bbd3125ff78b47cf58695`. Selected model manifest: `af23aa8892a736db57dedf4ac0e688cdc22da1fbe160dfbcd937e05da2f8609b`.

## Method and unchanged-output control

The offline observer wraps the active probability-fusion callable, returning the **same original output array**. A Python profiler reads model-head locals after calculation to identify the selected candidate, its actual trimmed time interval, masks, both component outputs and competing windows. No oracle window replaces the selected window.

The recorded 231 worker batches are replayed with their original timestamps, generation resets and prediction masks. All 231 match the recorded scores, decisions and completed event histories at the registered tolerances (`atol=2e-5`, `rtol=5e-4`). The observer saw 37 real word-head inference calls. This is an instrumentation null control, not proof of semantic correctness or pixel-to-feature parity.

## Component ranking on the same selected windows

Approximate gesture intervals were taken from the visible sequence and the user's stated order. Counts below are **prediction windows within one exposed video**, not independent samples, accuracy percentages, or claims of generalization. Standing first is also not sufficient to emit a result: score, margin, readiness and dwell still apply.

| Intended word | Selected windows | TCN ranks it first | Embedding ranks it first | Current fused result ranks it first |
|---|---:|---:|---:|---:|
| chào | 10 | 0 | 3 | 0 |
| nghe | 4 | 0 | 3 | 0 |
| nhìn | 10 | 4 | 5 | 5 |
| rau | 13 | 0 | 0 | 0 |

For example, at capture time 10.191 s, embedding ranks nghe first: cosine 0.6103, transformed word distribution 0.3651. TCN ranks nghe fifth with 0.0290 and ranks điếc first. The fused nghe score is 0.1970, rank two. This establishes loss of target rank in fusion for this window; it does **not** establish that embedding alone would satisfy the current 0.60 score threshold or safely emit nghe.

At 7.215 s, embedding ranks chào first (cosine 0.5744; transformed distribution 0.2927), while TCN ranks it fourth (0.0667). Fusion leaves chào second at 0.1797. Both models are running; embedding is neither disabled nor simply replaced by TCN.

For rau, neither component ranks the intended word first on any candidate in the inspected interval, including unselected candidates. Its highest fused score across all candidates is only 0.1463. This does not support a universal fix by increasing embedding's weight or changing dwell. No target was blocked by the pair/motion mask on the selected windows of these four intervals.

Cosine scores and class-distribution scores have different scales. A cosine of 0.61 is not an independently validated 61% probability of correctness. Do not compare their absolute values as though they had the same meaning.

## The two nhìn peaks

| Capture time | Selected measured interval | TCN nhìn | Embedding transformed nhìn | Fused nhìn | Qualified |
|---|---|---:|---:|---:|---|
| 14.175 s | 12.463–14.175 s, 16 frames | 0.5697 | 0.6599 | 0.6148 | yes |
| 14.481 s | 12.463–14.481 s, 19 frames | 0.0290 | 0.4879 | 0.2585 | no |
| 15.695 s | 12.816–15.695 s, 27 frames | 0.5410 | 0.7571 | 0.6491 | yes |
| 15.999 s | 13.023–15.999 s, 27 frames | 0.4269 | 0.6395 | 0.5332 | no |

The first peak is lost as the same-start interval extends by 0.306 s: TCN changes its winner to bệnh while embedding still ranks nhìn first. The second peak is followed by a slightly shifted suffix, with both models still ranking nhìn first but the fused score below 0.60. At both following steps there is **no other currently evaluated candidate** that remains eligible at the existing thresholds. Thus these examples are not a demonstrated bug where the selector ignores an eligible correct candidate. Reusing the previous high score would reuse old evidence, not repair the current measurement.

The record supports score/window instability followed by dwell reset. It cannot tell whether the neural model's sensitivity is caused by training diversity, real landmark errors, gesture variation, resampling, or timing without another controlled comparison. There is no basis here for a universal dwell reduction.

## Comparison with the supplied desktop script

The source examined is `E:/WorkSpace/SignVoice/test_camera.py`, SHA256 `c0a456a6525878303e0cb8e94358e0ce69e2454a9baba2772b2f265e2a64f847`.

AST bodies match for `HandSlotTracker`, `features_from_result`, `normalize_pose`, `gesture_interval`, `word_temporal_features`, `GestureBuffer` and `StableDecision`. `prepare_sign_sequence` differs by the app's explicit observed-hand mask support. Applying both implementations to all **128 candidate sequences** from this replay gives exactly equal pose/wrist arrays; no mask corrections were needed on these candidates. This narrows one suspected difference but does not compare the actual raw MediaPipe observations from web versus desktop.

`TemporalWordHead` differs materially: the supplied desktop script mixes TCN softmax and cosine directly and scales background by the TCN share. The app uses a temperature-based probability ensemble and preserves the background mass. The supplied script also identifies its extractor as `stable_two_hand_v5`; the app bundle uses `stable_two_hand_v6_camera640`. The old script's `TRACKED_PIPELINES` does not include this v6 identifier. Its default model directory currently has no `recognizer_config.json`. Therefore earlier desktop performance cannot be treated as a same-bundle, same-runtime baseline without verifying its original launch options and model files.

As a limited arithmetic diagnostic, the old formula was computed on the **same current selected windows**, same current 0.5 weight and same component outputs. It ranks the target first 0/10 for chào, 0/4 for nghe, 4/10 for nhìn and 0/13 for rau. This is not a complete old-desktop replay because the old formula could select different windows. It nevertheless gives no evidence that simply copying that formula back would solve these four signs.

## Decision and next bounded experiment

Keep the running app unchanged. The strongest observations are partial rank loss during fusion for chào/nghe, time instability for nhìn and weak ranking in both components for rau. These are different problems; one weight or threshold change is unlikely to address all four based on this evidence.

The next useful **offline** comparison is a preregistered component/ensemble evaluation on a fixed development cohort, measuring complete streams, wrong events, coverage and stability at the same operating constraints. Keep epoch and repeatedly viewed calibration results labeled development. Any fusion or temporal rule change must be evaluated across all supported words and background before promotion; these four exposed intervals cannot choose deployment weights. For rau, review dataset sign variants and compare a known training clip through the same stream before diagnosing a model-capacity problem or retraining. No additional user recording is needed merely to repeat this inspection.

Physical camera FPS and end-to-end extraction parity remain separate questions. The screen recording contains overlays and is not an unbiased raw-camera input. No independent webcam or background accuracy claim is made.

## Reproduce

From the project root in PowerShell:

```powershell
.\ai_service\.venv\Scripts\python.exe -m ai_service.inspect_camera_components "C:\Users\Phuoc Tue\Downloads\signvoice-camera-diagnostic.json" --model-dir ".\ai_service\models\181_2026_10_19_camera640" --desktop "E:\WorkSpace\SignVoice\test_camera.py" --output ".runtime\camera-diagnostics\20261021-second-capture\components.json"
```

Local outputs: `components.json` (every candidate), `component-summary.json` (phase counts), and `selected-components.csv` (selected candidate timeline). The executable validates model/config/code identity first and refuses a replay-control failure. Helper tests cover unchanged fusion output, detached observations, involutive slot exchange and rank/score preservation.
