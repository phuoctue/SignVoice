# VSL-GH Continuous Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a qualified, signer-disjoint VSL-GH training and streaming-evaluation pipeline that can produce a development-only continuous-gloss bundle without changing SignVoice's existing alphabet, number, or production word recognizers.

**Architecture:** Treat VSL-GH as an untrusted external source, pin and validate every artifact, then parse its continuous annotations into a canonical dataset contract. Train a causal TCN–unidirectional-GRU CTC model, export it to ONNX, and replay complete streams plus frame/hand-loss variants before exposing it behind an opt-in Python service adapter. Flutter integration and production promotion are a separate plan opened only after this candidate passes its gates.

**Tech Stack:** Python 3.11+, pytest, NumPy, MediaPipe Holistic, PyTorch for training, ONNX/ONNX Runtime for portable inference, existing SignVoice WebSocket service.

**Spec:** `docs/superpowers/specs/2026-10-25-vsl-gh-continuous-recognition-design.md`

## Global Constraints

- Keep `letters` and `digits` on the existing recognizer and model bundle.
- Do not delete or overwrite the current word model, dataset, checkpoint, API, or app setting.
- Never train on VSL-GH validation/test signers or use the test split for threshold selection.
- Do not merge labels based only on spelling similarity; every alias is explicit and reviewed.
- Training and live inference must call the same feature implementation.
- Do not claim webcam accuracy from clip-only metrics.
- Do not activate the candidate unless `AI_CONTINUOUS_VSL_BUNDLE` names a complete verified bundle.
- Do not add Flutter dependencies or alter database/business logic in this plan.

## File map

- `scripts/vsl_gh/qualify_source.py`: pin the upstream commit, inventory real artifacts, hash files, and emit a qualification receipt.
- `scripts/vsl_gh/train_continuous.py`: train the causal CTC model from a qualified dataset contract and export a candidate bundle.
- `ai_service/continuous_vsl/source.py`: typed source receipt and integrity validation.
- `ai_service/continuous_vsl/dataset.py`: annotation, split, signer, view, and temporal-boundary parsing.
- `ai_service/continuous_vsl/vocabulary.py`: Unicode normalization and explicit alias mapping.
- `ai_service/continuous_vsl/features.py`: shared TRAIN/live feature conversion and masks.
- `ai_service/continuous_vsl/model.py`: causal TCN–GRU CTC network used by the training script.
- `ai_service/continuous_vsl/decoder.py`: streaming CTC prefix stabilization and event generation.
- `ai_service/continuous_vsl/evaluate.py`: signer-disjoint offline and stream metrics.
- `ai_service/continuous_vsl/runtime.py`: verified ONNX bundle loader and session state.
- `ai_service/continuous_vsl/adapter.py`: opt-in bridge to the existing service result schema.
- `ai_service/tests/fixtures/vsl_gh/`: tiny synthetic repository and annotation fixtures, not training data.
- `ai_service/test_continuous_vsl_*.py`: focused unit and integration tests.

---

### Task 1: Qualify the real VSL-GH source

**Files:**
- Create: `ai_service/continuous_vsl/__init__.py`
- Create: `ai_service/continuous_vsl/source.py`
- Create: `scripts/vsl_gh/qualify_source.py`
- Create: `ai_service/tests/fixtures/vsl_gh/README.md`
- Create: `ai_service/tests/fixtures/vsl_gh/LICENSE`
- Create: `ai_service/tests/fixtures/vsl_gh/data/dataset.json`
- Test: `ai_service/test_continuous_vsl_source.py`

**Interfaces:**
- Produces: `qualify_source(repo: Path, output: Path, expected_commit: str) -> SourceReceipt`
- Produces: `SourceReceipt.load(path: Path) -> SourceReceipt`
- Produces: `SourceReceipt.verify() -> None`
- Receipt fields: `schema`, `commit`, `license_sha256`, `artifacts`, `counts`, `downloadable`, `complete`, `reasons`.

- [ ] **Step 1: Write failing receipt tests**

```python
def test_qualification_refuses_readme_only_repository(tmp_path):
    repo = copy_fixture(tmp_path, "vsl_gh")
    receipt = qualify_source(repo, tmp_path / "receipt.json", "a" * 40)
    assert receipt.complete is False
    assert "missing_videos" in receipt.reasons
    assert "missing_keypoints" in receipt.reasons

def test_receipt_detects_post_qualification_mutation(tmp_path):
    repo = complete_fixture(tmp_path)
    receipt = qualify_source(repo, tmp_path / "receipt.json", "b" * 40)
    next(iter((repo / "data" / "annotations").glob("*.txt"))).write_text("changed")
    with pytest.raises(SourceIntegrityError, match="sha256"):
        SourceReceipt.load(tmp_path / "receipt.json").verify()
```

- [ ] **Step 2: Run the source tests and confirm they fail**

Run: `python -m pytest ai_service/test_continuous_vsl_source.py -q`

Expected: FAIL because `ai_service.continuous_vsl.source` does not exist.

- [ ] **Step 3: Implement immutable qualification**

Implement `SourceArtifact(path: str, bytes: int, sha256: str, role: str)` and `SourceReceipt`. Inventory only files physically present under the pinned checkout. Require `LICENSE`, `data/dataset.json`, annotations, splits, keypoints, and videos; a README declaration cannot satisfy a role. Write JSON atomically with `allow_nan=False`.

CLI:

```powershell
$commit = git -C .runtime/vsl_gh/source rev-parse HEAD
python scripts/vsl_gh/qualify_source.py `
  --repo .runtime/vsl_gh/source `
  --expected-commit $commit `
  --output .runtime/vsl_gh/source_receipt.json
```

Exit `0` only when the receipt is complete; exit `2` with a complete receipt describing missing assets otherwise.

- [ ] **Step 4: Run source tests**

Run: `python -m pytest ai_service/test_continuous_vsl_source.py -q`

Expected: PASS.

- [ ] **Step 5: Clone and qualify upstream without modifying it**

Run:

```powershell
git clone --filter=blob:none https://github.com/nguyentheanh822/Vietnamese-Sign-Language-Translation.git .runtime/vsl_gh/source
$commit = git -C .runtime/vsl_gh/source rev-parse HEAD
python scripts/vsl_gh/qualify_source.py --repo .runtime/vsl_gh/source --expected-commit $commit --output .runtime/vsl_gh/source_receipt.json
```

Expected: either a complete cryptographic inventory or a deterministic receipt proving which advertised assets are absent. Do not continue to Task 2 if `complete` is false.

- [ ] **Step 6: Commit Task 1**

```bash
git add ai_service/continuous_vsl ai_service/test_continuous_vsl_source.py ai_service/tests/fixtures/vsl_gh scripts/vsl_gh/qualify_source.py
git commit -m "feat: qualify VSL-GH source artifacts"
```

### Task 2: Parse continuous annotations and enforce signer-disjoint splits

**Files:**
- Create: `ai_service/continuous_vsl/dataset.py`
- Create: `ai_service/test_continuous_vsl_dataset.py`
- Modify: `ai_service/tests/fixtures/vsl_gh/data/dataset.json`
- Create: `ai_service/tests/fixtures/vsl_gh/data/annotations/SENT001_S01_R01_F.txt`
- Create: `ai_service/tests/fixtures/vsl_gh/data/splits/train.txt`
- Create: `ai_service/tests/fixtures/vsl_gh/data/splits/val.txt`
- Create: `ai_service/tests/fixtures/vsl_gh/data/splits/test.txt`

**Interfaces:**
- Consumes: a verified `SourceReceipt`.
- Produces: `load_dataset(receipt: SourceReceipt) -> DatasetContract`.
- `DatasetContract` contains immutable `SequenceSample` records with `video_id`, `signer_id`, `session_id`, `view`, `split`, `video_path`, `keypoint_path`, `duration_ms`, and ordered `GlossSpan(label, start_ms, end_ms)`.

- [ ] **Step 1: Write failing boundary and leakage tests**

```python
def test_annotation_parser_preserves_order_and_milliseconds(qualified_fixture):
    data = load_dataset(qualified_fixture)
    spans = data.samples[0].glosses
    assert [(s.label, s.start_ms, s.end_ms) for s in spans] == [
        ("TÔI", 10, 860), ("HẸN", 860, 1430)
    ]

def test_signer_overlap_is_rejected(qualified_fixture):
    fixture_add_sample(qualified_fixture, split="val", signer_id="S01")
    with pytest.raises(DatasetContractError, match="signer overlap"):
        load_dataset(qualified_fixture)
```

- [ ] **Step 2: Run dataset tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_dataset.py -q`

Expected: FAIL because the parser is missing.

- [ ] **Step 3: Implement strict parsing**

Parse `Gloss HH:MM:SS.mmm HH:MM:SS.mmm LABEL` records, require monotonic non-overlapping spans inside the measured video duration, and keep frontal/lateral recordings grouped by sentence, signer, and repetition. Reject duplicate IDs, absent files, unknown splits, empty gloss sequences, and signer overlap across train/val/test.

- [ ] **Step 4: Run dataset tests**

Run: `python -m pytest ai_service/test_continuous_vsl_dataset.py -q`

Expected: PASS.

- [ ] **Step 5: Emit the real dataset contract**

Run:

```powershell
python -m ai_service.continuous_vsl.dataset `
  --receipt .runtime/vsl_gh/source_receipt.json `
  --output .runtime/vsl_gh/dataset_contract.json
```

Expected: explicit train/val/test video, signer, view, gloss, and duration counts with zero signer overlap.

- [ ] **Step 6: Commit Task 2**

```bash
git add ai_service/continuous_vsl/dataset.py ai_service/test_continuous_vsl_dataset.py ai_service/tests/fixtures/vsl_gh/data
git commit -m "feat: validate VSL-GH continuous annotations"
```

### Task 3: Normalize vocabulary without unsafe automatic merges

**Files:**
- Create: `ai_service/continuous_vsl/vocabulary.py`
- Create: `ai_service/continuous_vsl/vsl_gh_aliases.json`
- Create: `ai_service/test_continuous_vsl_vocabulary.py`

**Interfaces:**
- Produces: `normalize_gloss(value: str) -> str` using Unicode NFC, trim, and lowercase only.
- Produces: `build_vocabulary(contract: DatasetContract, aliases: Mapping[str, str]) -> VocabularyReport`.
- `VocabularyReport` contains `source_labels`, `canonical_labels`, `explicit_aliases`, `signvoice_overlap`, `unmapped`, and a SHA-256 digest.

- [ ] **Step 1: Write failing normalization tests**

```python
def test_normalization_only_changes_unicode_case_and_spacing():
    assert normalize_gloss("  TÔI ") == "tôi"

def test_similar_names_are_not_merged_without_alias():
    report = build_vocabulary(contract_for("trưa", "buổi trưa"), aliases={})
    assert report.canonical_labels == ["buổi trưa", "trưa"]
```

- [ ] **Step 2: Run tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_vocabulary.py -q`

Expected: FAIL because vocabulary functions are missing.

- [ ] **Step 3: Implement normalization and empty reviewed alias file**

Create `vsl_gh_aliases.json` with schema and an empty `aliases` object. Every future entry must contain `source`, `canonical`, `reviewer`, `evidence`, and `reviewed_at`; reject aliases lacking those fields.

- [ ] **Step 4: Run vocabulary tests and emit overlap report**

Run: `python -m pytest ai_service/test_continuous_vsl_vocabulary.py -q`

Then run:

```powershell
python -m ai_service.continuous_vsl.vocabulary `
  --dataset .runtime/vsl_gh/dataset_contract.json `
  --signvoice-bundle .runtime/current-model/recognizer_config.json `
  --output .runtime/vsl_gh/vocabulary_report.json
```

Expected: PASS and a report that distinguishes exact overlap, reviewed aliases, and unmapped labels.

- [ ] **Step 5: Commit Task 3**

```bash
git add ai_service/continuous_vsl/vocabulary.py ai_service/continuous_vsl/vsl_gh_aliases.json ai_service/test_continuous_vsl_vocabulary.py
git commit -m "feat: add reviewed VSL gloss vocabulary"
```

### Task 4: Build one TRAIN/live feature implementation

**Files:**
- Create: `ai_service/continuous_vsl/features.py`
- Create: `ai_service/test_continuous_vsl_features.py`

**Interfaces:**
- Consumes: the qualified VSL-GH keypoint schema discovered from source code and artifacts.
- Produces: `FeatureSchema(names: tuple[str, ...], dimension: int, sha256: str)`.
- Produces: `extract_frame(result: HolisticResult, schema: FeatureSchema) -> FeatureFrame`.
- Produces: `extract_video(path: Path, schema: FeatureSchema, target_fps: float) -> FeatureSequence`.
- `FeatureSequence.values` has shape `[T, D]`; `presence` has shape `[T, P]`; timestamps are strictly increasing milliseconds.

- [ ] **Step 1: Write failing parity and missing-landmark tests**

```python
def test_video_and_live_paths_match_on_identical_results(frozen_results, schema):
    live = np.stack([extract_frame(r, schema).values for r in frozen_results])
    video = extract_results(frozen_results, schema).values
    np.testing.assert_allclose(live, video, rtol=0, atol=1e-6)

def test_missing_hand_uses_mask_not_invented_coordinates(schema):
    frame = extract_frame(result_without_left_hand(), schema)
    assert frame.presence[schema.presence_index("left_hand")] == 0
    assert np.isfinite(frame.values).all()
```

- [ ] **Step 2: Run tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_features.py -q`

Expected: FAIL because feature extraction is missing.

- [ ] **Step 3: Implement the schema adapter from qualified upstream definitions**

Read landmark indices and normalization from the pinned VSL-GH extractor. Store their names, order, source line digest, normalization constants, masks, and target FPS in `FeatureSchema`; refuse unnamed numeric arrays. Compute motion from measured timestamps and never forward-fill across a gap longer than `250 ms`.

- [ ] **Step 4: Run parity tests**

Run: `python -m pytest ai_service/test_continuous_vsl_features.py -q`

Expected: PASS with maximum TRAIN/live absolute error `<= 1e-6` for identical detector results.

- [ ] **Step 5: Extract a resumable cache**

Run:

```powershell
python -m ai_service.continuous_vsl.features `
  --dataset .runtime/vsl_gh/dataset_contract.json `
  --output .runtime/vsl_gh/features `
  --journal .runtime/vsl_gh/feature_journal.jsonl
```

Expected: one atomic cache per video, source and schema hashes in each file, and a summary that reports missing-hand/frame-gap distributions by split without decoding test labels.

- [ ] **Step 6: Commit Task 4**

```bash
git add ai_service/continuous_vsl/features.py ai_service/test_continuous_vsl_features.py
git commit -m "feat: add shared VSL-GH feature pipeline"
```

### Task 5: Implement and train the causal CTC model

**Files:**
- Create: `ai_service/continuous_vsl/model.py`
- Create: `scripts/vsl_gh/train_continuous.py`
- Create: `ai_service/test_continuous_vsl_model.py`

**Interfaces:**
- Produces: `CausalGlossModel(feature_dim: int, classes: int, channels: int = 192, gru_units: int = 192)`.
- `forward(features, lengths) -> logits` with shape `[batch, time, 1 + gloss_count]`; class `0` is CTC blank.
- Training output: `model.onnx`, `labels.json`, `feature_schema.json`, `model_config.json`, `validation_report.json`, and `bundle_manifest.json`.

- [ ] **Step 1: Write failing shape, gradient, and causality tests**

```python
def test_model_is_causal():
    model = CausalGlossModel(feature_dim=12, classes=5).eval()
    x = torch.randn(1, 20, 12)
    changed = x.clone(); changed[:, 10:] += 100
    torch.testing.assert_close(model(x, [20])[:, :10], model(changed, [20])[:, :10])

def test_ctc_loss_has_finite_gradients():
    model = CausalGlossModel(feature_dim=12, classes=5)
    loss = ctc_training_loss(model, tiny_batch())
    loss.backward()
    assert torch.isfinite(loss)
    assert all(p.grad is None or torch.isfinite(p.grad).all() for p in model.parameters())
```

- [ ] **Step 2: Run model tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_model.py -q`

Expected: FAIL because the model is missing.

- [ ] **Step 3: Implement causal TCN, unidirectional GRU, and CTC loss**

Use left-only padding for every temporal convolution, `batch_first=True` and `bidirectional=False` for GRU, packed sequence lengths, blank index `0`, gradient clipping `1.0`, and deterministic seed `42`. Select checkpoints by signer-disjoint validation gloss error rate, never calibration/test scores.

- [ ] **Step 4: Run model tests**

Run: `python -m pytest ai_service/test_continuous_vsl_model.py -q`

Expected: PASS, including exact causality before the modified future boundary.

- [ ] **Step 5: Run a one-batch CPU smoke train**

Run:

```powershell
python scripts/vsl_gh/train_continuous.py `
  --dataset .runtime/vsl_gh/dataset_contract.json `
  --features .runtime/vsl_gh/features `
  --output .runtime/vsl_gh/smoke_bundle `
  --epochs 1 --max-train-batches 1 --device cpu
```

Expected: complete reloadable bundle; this smoke result is marked `development_only=true` and is never compared as model evidence.

- [ ] **Step 6: Train on GPU with resumable checkpoints**

Run in Colab after uploading the qualified contract and feature cache:

```bash
python scripts/vsl_gh/train_continuous.py \
  --dataset dataset_contract.json \
  --features features \
  --output candidate_bundle \
  --epochs 60 --patience 8 --device cuda
```

Expected: the selected validation checkpoint reloads and produces finite ONNX logits matching PyTorch within `atol=1e-4`.

- [ ] **Step 7: Commit Task 5**

```bash
git add ai_service/continuous_vsl/model.py ai_service/test_continuous_vsl_model.py scripts/vsl_gh/train_continuous.py
git commit -m "feat: train causal continuous VSL model"
```

### Task 6: Add streaming CTC decoding and complete-sequence evaluation

**Files:**
- Create: `ai_service/continuous_vsl/decoder.py`
- Create: `ai_service/continuous_vsl/evaluate.py`
- Create: `ai_service/test_continuous_vsl_decoder.py`
- Create: `ai_service/test_continuous_vsl_evaluate.py`

**Interfaces:**
- Produces: `StreamingCtcDecoder.update(log_probs: np.ndarray, timestamps_ms: np.ndarray) -> DecodeUpdate`.
- `DecodeUpdate` contains immutable `partial_glosses`, newly emitted `final_glosses`, `blank_score`, and `revision`.
- Produces: `evaluate_bundle(bundle: Path, dataset: DatasetContract, variants: tuple[StreamVariant, ...]) -> EvaluationReport`.

- [ ] **Step 1: Write failing blank-collapse, duplicate, and metric tests**

```python
def test_decoder_collapses_repeats_but_allows_repeat_after_blank(labels):
    decoder = StreamingCtcDecoder(labels, stable_ms=300)
    update = decoder.update(log_probs_for([1, 1, 0, 1]), np.array([0, 100, 200, 500]))
    assert [g.label for g in update.final_glosses] == [labels[1], labels[1]]

def test_evaluation_counts_insertions_deletions_and_substitutions():
    counts = edit_counts(["tôi", "chào"], ["tôi", "nhìn", "rau"])
    assert counts == EditCounts(insertions=1, deletions=0, substitutions=1, correct=1)
```

- [ ] **Step 2: Run decoder/evaluation tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_decoder.py ai_service/test_continuous_vsl_evaluate.py -q`

Expected: FAIL because decoder and evaluator are missing.

- [ ] **Step 3: Implement prefix stabilization and edit metrics**

Finalization requires the same non-blank prefix to remain stable for `300 ms`, followed by either blank probability `>= 0.60` or a different stable prefix. Report gloss error rate, exact sequence rate, insertions, deletions, substitutions, duplicate emissions, median/p95 first-final latency, and per-gloss recall. Values are configuration fields persisted in the bundle, not hidden constants.

- [ ] **Step 4: Implement stream variants**

Evaluate, without retraining:

```python
variants = (
    StreamVariant("normal"),
    StreamVariant("drop_frames_20pct", drop_every=5),
    StreamVariant("one_hand_gap_150ms", one_hand_gap_ms=150),
    StreamVariant("timestamp_gap_300ms", timestamp_gap_ms=300),
    StreamVariant("cadence_10fps", target_fps=10),
)
```

Each report keeps video, signer, view, and variant IDs and never pools test into validation.

- [ ] **Step 5: Run tests and evaluate validation only**

Run:

```powershell
python -m pytest ai_service/test_continuous_vsl_decoder.py ai_service/test_continuous_vsl_evaluate.py -q
python -m ai_service.continuous_vsl.evaluate --bundle .runtime/vsl_gh/candidate_bundle --dataset .runtime/vsl_gh/dataset_contract.json --split val --output .runtime/vsl_gh/validation_stream_report.json
```

Expected: tests PASS and a validation report with all five variants and no test metrics.

- [ ] **Step 6: Freeze policy, then open test once**

Write the chosen decoder configuration and its validation-report hash into the bundle manifest, make it immutable, then run:

```powershell
python -m ai_service.continuous_vsl.evaluate --bundle .runtime/vsl_gh/candidate_bundle --dataset .runtime/vsl_gh/dataset_contract.json --split test --output .runtime/vsl_gh/final_test_report.json
```

Expected: one signer-disjoint final report; later tuning creates a new candidate and does not overwrite this report.

- [ ] **Step 7: Commit Task 6**

```bash
git add ai_service/continuous_vsl/decoder.py ai_service/continuous_vsl/evaluate.py ai_service/test_continuous_vsl_decoder.py ai_service/test_continuous_vsl_evaluate.py
git commit -m "feat: evaluate continuous VSL streams"
```

### Task 7: Add a development-only AI service adapter

**Files:**
- Create: `ai_service/continuous_vsl/runtime.py`
- Create: `ai_service/continuous_vsl/adapter.py`
- Create: `ai_service/test_continuous_vsl_runtime.py`
- Modify: `ai_service/engine.py`
- Modify: `ai_service/test_recognition_delivery.py`

**Interfaces:**
- Consumes: `AI_CONTINUOUS_VSL_BUNDLE`, absent by default.
- Produces: `ContinuousVslRuntime.load(bundle: Path) -> ContinuousVslRuntime` with checksum and schema validation.
- Produces: `ContinuousVslSession.process(feature_frame, timestamp_ms) -> dict` containing `continuous` and zero or more backward-compatible `events`.
- `Engine.info()` adds `continuous_vsl_available`, `continuous_vsl_enabled`, `continuous_vsl_bundle_sha256`.

- [ ] **Step 1: Write failing mode-isolation and tamper tests**

```python
def test_candidate_is_disabled_without_explicit_bundle(monkeypatch, model_dir):
    monkeypatch.delenv("AI_CONTINUOUS_VSL_BUNDLE", raising=False)
    engine = Engine(model_dir)
    assert engine.info()["continuous_vsl_enabled"] is False

def test_digits_and_letters_never_enter_continuous_runtime(engine_with_candidate):
    assert engine_with_candidate.session("digits").continuous is None
    assert engine_with_candidate.session("letters").continuous is None

def test_runtime_refuses_tampered_onnx(candidate_bundle):
    (candidate_bundle / "model.onnx").write_bytes(b"tampered")
    with pytest.raises(BundleIntegrityError, match="sha256"):
        ContinuousVslRuntime.load(candidate_bundle)
```

- [ ] **Step 2: Run adapter tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_runtime.py ai_service/test_recognition_delivery.py -q`

Expected: FAIL because the opt-in runtime does not exist.

- [ ] **Step 3: Implement verified ONNX loading and words-only routing**

Load the candidate only when the environment variable is set. Keep existing session construction for `letters`, `digits`, and default production execution. In candidate development mode, route `words` feature frames through `ContinuousVslSession`; copy final glosses to incrementing `events` IDs while including the full `continuous` object.

- [ ] **Step 4: Run adapter and existing recognition tests**

Run:

```powershell
python -m pytest ai_service/test_continuous_vsl_runtime.py ai_service/test_recognition_delivery.py ai_service/test_recognition_worker.py -q
```

Expected: PASS; old tests observe unchanged results without the environment variable.

- [ ] **Step 5: Commit Task 7**

```bash
git add ai_service/continuous_vsl/runtime.py ai_service/continuous_vsl/adapter.py ai_service/test_continuous_vsl_runtime.py ai_service/engine.py ai_service/test_recognition_delivery.py
git commit -m "feat: add opt-in continuous VSL runtime"
```

### Task 8: Verify Web/Android protocol compatibility without switching production

**Files:**
- Modify: `test/camera_diagnostic_test.dart`
- Modify: `test/sign_sequence_panel_test.dart`
- Create: `ai_service/test_continuous_vsl_protocol.py`
- Create: `docs/VSL_GH_CONTINUOUS_TESTING.md`

**Interfaces:**
- Consumes: existing `events` delivery in `LiveCameraScreen` and optional `continuous` diagnostics.
- Produces: no production setting change; documents the explicit development launch command only.

- [ ] **Step 1: Add protocol fixtures with two final gloss events**

```dart
final result = {
  'type': 'result',
  'events': [
    {'id': 1, 'label': 'tôi'},
    {'id': 2, 'label': 'chào'},
  ],
  'continuous': {
    'partial_glosses': [],
    'final_glosses': [
      {'label': 'tôi', 'start_ms': 100, 'end_ms': 700, 'score': .9},
      {'label': 'chào', 'start_ms': 800, 'end_ms': 1500, 'score': .88},
    ],
    'revision': 2,
  },
};
```

Assert that the current event consumer appends each event once and that an identical repeated message does not speak or append it again.

- [ ] **Step 2: Run tests and verify any new assertion fails first**

Run: `flutter test test/camera_diagnostic_test.dart test/sign_sequence_panel_test.dart`

Expected: the newly added continuous fixture test fails if delivery is not idempotent; existing tests remain green.

- [ ] **Step 3: Make the smallest compatibility adjustment if required**

Do not redesign the screen. Reuse the existing monotonically increasing event-ID guard. Ignore `partial_glosses` in user-facing text during this phase; include them only in exported diagnostics.

- [ ] **Step 4: Run Python, Dart, and JavaScript regression suites**

Run:

```powershell
python -m pytest ai_service/test_continuous_vsl_*.py ai_service/test_recognition_delivery.py ai_service/test_recognition_worker.py -q
flutter test test/camera_diagnostic_test.dart test/sign_sequence_panel_test.dart test/digit_stream_test.dart
node --test test_js/signvoice_hand_worker.test.cjs
```

Expected: all PASS, especially the unchanged number/alphabet stream tests.

- [ ] **Step 5: Document development launch and rollback**

Document exactly:

```powershell
$env:AI_CONTINUOUS_VSL_BUNDLE='E:\WorkSpace\SignVoice\SignVoice\.runtime\vsl_gh\candidate_bundle'
.\Chay_AI_Service.bat
```

Rollback is removing `AI_CONTINUOUS_VSL_BUNDLE` and restarting the service. State that the command is development-only and does not promote the model.

- [ ] **Step 6: Commit Task 8**

```bash
git add test/camera_diagnostic_test.dart test/sign_sequence_panel_test.dart ai_service/test_continuous_vsl_protocol.py docs/VSL_GH_CONTINUOUS_TESTING.md
git commit -m "test: verify continuous gloss delivery"
```

### Task 9: Record the promotion decision

**Files:**
- Create: `scripts/vsl_gh/promotion_report.py`
- Create: `ai_service/test_continuous_vsl_promotion.py`
- Create: `.runtime/vsl_gh/promotion_report.json` (generated and ignored, never committed)

**Interfaces:**
- Produces: `build_promotion_report(validation, final_test, webcam, background, latency, regressions) -> PromotionReport`.
- `PromotionReport.promotable` is false unless every required evidence input is measured and passed.

- [ ] **Step 1: Write failing conservative-gate tests**

```python
def test_missing_webcam_or_background_blocks_promotion(valid_reports):
    report = build_promotion_report(**valid_reports, webcam=None, background=None)
    assert report.promotable is False
    assert report.reasons == ["webcam_not_measured", "background_not_measured"]

def test_letter_or_digit_regression_blocks_promotion(valid_reports):
    report = build_promotion_report(**valid_reports, regressions={"letters": True, "digits": False})
    assert report.promotable is False
    assert "digit_regression" in report.reasons
```

- [ ] **Step 2: Run promotion tests and confirm failure**

Run: `python -m pytest ai_service/test_continuous_vsl_promotion.py -q`

Expected: FAIL because promotion reporting is missing.

- [ ] **Step 3: Implement evidence-only promotion reporting**

Require measured validation, final test, webcam, background false events/minute, Web/Android median and p95 latency, feature parity, stream variants, and unchanged letter/digit tests. The tool reports evidence and reasons; it never edits app configuration.

- [ ] **Step 4: Run all continuous VSL tests and generate report**

Run:

```powershell
python -m pytest ai_service/test_continuous_vsl_*.py -q
python scripts/vsl_gh/promotion_report.py --evidence .runtime/vsl_gh --output .runtime/vsl_gh/promotion_report.json
```

Expected: tests PASS. Until real webcam and background evidence exist, the report must say `promotable=false` with explicit missing-evidence reasons.

- [ ] **Step 5: Commit Task 9**

```bash
git add scripts/vsl_gh/promotion_report.py ai_service/test_continuous_vsl_promotion.py
git commit -m "feat: gate continuous VSL promotion on evidence"
```

## Completion checkpoint

This plan is complete when source qualification, dataset parsing, feature parity,
causal CTC training, stream evaluation, and the opt-in adapter all pass their
tests, and a promotion report exists. A negative source receipt or
`promotable=false` is a valid, honest result; it must not be bypassed by enabling
the candidate in the production app.

If `promotable=true`, write a separate bounded integration plan for switching
the production `words` mode and displaying stable partial/final sequences. If it
is false, use the recorded reasons to choose one corrective experiment without
changing the production model.

