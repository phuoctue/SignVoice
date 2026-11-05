# Track coverage and matched orientation training

Keep TCN180 reference checkpoint, TRAIN/epoch/calibration IDs and recognition policy fixed. Do not deploy to public or train on webcam recordings.

1. Regression first: require periodic current-pixel verification of tracks of every size; preserve moving/revalidated real hands, expire old evidence, bound pending jobs, leave glyph/default profiles unchanged. Replace the size-only trigger without raising its threshold. Use existing recorded VIDEO + same-pixel IMAGE fixtures and exact guard code for regression.
2. Separate verification coverage from rejection confidence: accumulate missing evidence only for a spatially stable track across completed checks; current detections recover immediately on fresh confirmation. Record coverage and failures truthfully. A re-detection does not prove ownership by the main signer.
3. Inventory the actual nghe/điếc TRAIN and heldout data and its review status. Keep unverified labels visibly unverified. Reuse cached aligned features where checksum/runtime match.
4. Build matched control/candidate training: same examples, steps, seed and checkpoint; only candidate adds consistent horizontal reflection of supported TRAIN views, before temporal features. Preserve missing-hand masks, face anchors, signed wrist coordinates and time. Do not mirror all classes blindly or change thresholds. Retain other-class supervision to limit forgetting.
5. Evaluate unchanged reference, control and candidate on the same fixed source heldout cohort and frozen webcam recordings as development probes. Report target confusions, wrong events, losses of previously correct results, latency and reload parity. Never promote from these development probes alone.
6. If the necessary full TRAIN cache/checkpoints are only on Drive, provide a checksum-bound runnable training entrypoint instead of inventing data or silently reducing this to a nghe-only fit. Keep exact execution status explicit.
