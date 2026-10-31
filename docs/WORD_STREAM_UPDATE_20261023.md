# Word stream update — 23 October 2026

Two delivery/scheduling defects are fixed in source. No recognition threshold,
word model, detector model or letter/digit policy was changed.

## Changes

- A word worker batch can end with empty observations after a visible hand.
  Previously only the last observation could run inference, so this batch ran
  no inference. The worker now permits at most one prediction at the newest
  measured hand within 250 ms of the batch end. It processes every observation,
  including the empty tail, in its original order and clock. The runtime still
  enforces the existing prediction interval, gap, readiness and dwell rules.
  Letter/digit/all modes retain their previous scheduling.
- A newly completed word can arrive after hands have left the displayed frame.
  Delivery now permits that actual completion for at most 250 ms, only when its
  label matches the reliable output and its event timestamp matches the last
  prediction. Event keys prevent duplicate delivery. Old results and held glyphs
  are not revived by this path.
- Opt-in diagnostics save the scheduler version and the exact prediction mask.
  Replay accepts the old scheduler for old records and validates the new mask
  deterministically for new records. The change does not fabricate observations.

## Verification

16 tests passed across recognition worker, delivery, diagnostic replay and socket
modules, including a real threaded worker batch ending with empty frames, exact
journal masks, old-format replay, stale-result rejection and duplicate delivery.

Separately, 4 tests passed for the new Colab window fine-tune objective and
selection guard. Both arms passed a discarded real-checkpoint gradient step and
save/reload probe. These are code checks, not webcam accuracy measurements.

## Colab

The existing notebook was updated in place with **7. WORD.FIX**:
https://colab.research.google.com/drive/1nLWClL4dpY5qy44cXiITOrTGw98Ds3V1

Current RAM: run WORD.FIX only. Lost RAM: 0R → DATA.CHECK → WORD.FIX. Choose GPU.
Do not rerun AE.RUN, TRACE, CADENCE or VIEW.COMPARE for this step.

The cell mines confident wrong causal windows from fixed retained TRAIN parents
across all active classes, then runs one six-epoch paired fine-tune and fixed-policy
stream evaluation. Candidate adds a complementary probability loss; control has
weight zero with the same positive/auxiliary inputs, augmentation and budget.
The frozen model is also evaluated. It never assigns partial windows to background
or changes the user's review decisions. A single seed on reused calibration data
cannot establish deployment superiority; the cell does not activate a model.

The notebook readback was byte-identical after upload and all prior code/output
cells were preserved. A backup exists on Drive before the update. Full Colab GPU
execution has not been performed by the agent.

## Apply the service source change

The running service was not restarted. A tool policy rejection prevented checking
the local service's health, so its current RAM version was not verified.

Stop the previous AI process with Ctrl+C in its terminal, then from the project:

```powershell
.\Chay_AI_Service.bat
```

This loads the stream code with the already selected bundle. It does not load the
experimental WORD.FIX checkpoint. The changes do not demonstrate better hand
detector FPS or solve the classifier's incorrect word ranking by themselves.
