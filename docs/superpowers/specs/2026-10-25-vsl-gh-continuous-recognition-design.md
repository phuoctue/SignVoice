# VSL-GH continuous recognition design

## Objective

Add a Vietnamese continuous-sign recognition path based on VSL-GH. Keep the
existing SignVoice number and alphabet recognizers unchanged. Replace the old
word/phrase recognizer only after the new path passes offline, stream, webcam,
background, and latency checks.

The target output is an ordered gloss stream with timestamps, not one label per
clip. This work must not claim sentence-level webcam accuracy from clip-only
metrics.

## Scope and safety boundary

- `digits` and `letters` continue to use the existing runtime and model bundle.
- `words` becomes the future continuous-VSL mode. Until promotion, the app keeps
  using its current word runtime and exposes the candidate only in an explicit
  development configuration.
- No existing model, dataset, checkpoint, API, or app setting is deleted or
  overwritten during development.
- The existing 10,118-word training collection may supplement VSL-GH after label
  mapping and provenance checks, but it is not silently mixed into VSL-GH.
- Audit/test signers and clips never enter training, calibration, threshold
  selection, or label review.

## Source qualification

The first stage treats the public VSL-GH repository as an untrusted input. It
must produce a machine-readable receipt containing:

- pinned repository commit and MIT license checksum;
- actual downloadable video, annotation, keypoint, split, and checkpoint files;
- file count, byte count, and SHA-256 hashes;
- the declared signer-disjoint train/validation/test split;
- a normalized gloss vocabulary and overlap report against SignVoice labels;
- rejected or missing files with explicit reasons.

README claims are not sufficient. If the advertised media or keypoints are not
downloadable, the pipeline stops without manufacturing substitute data.

## Data preparation

VSL-GH sentence recordings are segmented only from their published temporal
annotations. The continuous training view preserves full sentences and their
gloss sequences; isolated segments are generated only as an auxiliary view.

Normalization rules:

- Unicode NFC and a checked alias table; no automatic merge based only on a
  similar Vietnamese name;
- preserve signer, session, camera view, source file, and temporal boundaries;
- retain frontal and lateral views as separate observations of the same signing
  event and keep their grouping in all splits;
- measure missing hands, missing pose/face landmarks, timestamp gaps, and frame
  rate rather than filling them without a mask;
- convert training and live input through the same feature implementation and
  verify parity on identical video pixels.

## Model

The first candidate is a causal temporal encoder with a CTC gloss head:

1. MediaPipe Holistic-compatible hand, upper-body, and selected face geometry;
2. explicit landmark-presence masks and first-order motion features;
3. causal TCN followed by a unidirectional GRU;
4. CTC blank plus the verified VSL-GH gloss vocabulary;
5. prefix decoding that can emit stable partial and final glosses online.

This architecture is chosen over a bidirectional sentence model because live
webcam inference cannot depend on future frames. VSL-GH reference models remain
comparison baselines; they do not automatically become the production model.

Training checkpoints are selected on signer-disjoint validation gloss error
rate. The untouched signer-disjoint test set is opened once after the candidate
and decoding policy are frozen.

## Runtime and API

The Python AI service owns the first implementation so Web and Android use the
same model and preprocessing. On-device conversion is a later optimization,
not a prerequisite for correctness.

The existing WebSocket result remains backwards compatible. Continuous mode
adds:

```json
{
  "continuous": {
    "partial_glosses": [{"label": "tôi", "start_ms": 120, "score": 0.81}],
    "final_glosses": [{"label": "tôi", "start_ms": 120, "end_ms": 740, "score": 0.88}],
    "blank_score": 0.73,
    "revision": 4
  },
  "events": [{"id": 12, "label": "tôi"}]
}
```

Final gloss events continue through the existing `events` field so the current
Flutter UI can append and speak results without an immediate screen rewrite.
Partial glosses are diagnostic until their stability is established.

Mode routing is explicit:

- `letters` and `digits`: unchanged existing recognizer;
- `words`: continuous VSL candidate when development mode is enabled;
- `all`: not enabled for the candidate until mode switching has a tested rule.

## Evaluation and promotion gates

The candidate is not promoted from development mode unless all of these are
reported:

1. signer-disjoint validation and final test gloss error rate;
2. replay of complete continuous videos with insertion, deletion, substitution,
   duplicate-event, and time-to-finalize counts;
3. identical-pixel TRAIN/live feature parity within a predeclared tolerance;
4. regression tests for frame loss, one-hand gaps, timestamp gaps, and camera
   cadence changes;
5. real webcam sessions from people not used for tuning;
6. real non-signing background exposure and false events per minute;
7. median and p95 detector, model, transport, and end-to-end latency on Web and
   Android;
8. no regression to the existing alphabet and number modes.

No threshold is selected from the untouched test set. Failure of a gate keeps
the old runtime active and records the reason.

## Implementation boundaries

The work is split into independently testable stages:

1. source acquisition and integrity receipt;
2. annotation/vocabulary/split validation;
3. deterministic feature extraction with TRAIN/live parity tests;
4. causal CTC training and offline evaluation;
5. stream replay and robustness evaluation;
6. development-only AI-service adapter;
7. Flutter rendering of final gloss events;
8. Web and Android latency/background acceptance.

Each stage writes a resumable manifest and may not assume the next stage passed.
The active app model changes only in the final promotion stage.

