"""Probability ensemble bound to one verified Colab export.

Cosines are converted to a conditional word distribution before mixing. The
TCN's background mass is preserved; prototype similarity cannot erase it.
"""
import json
from pathlib import Path
import numpy as np


def softmax(values):
    values = np.asarray(values, np.float64)
    values = values - values.max(axis=-1, keepdims=True)
    exp = np.exp(values)
    return (exp / exp.sum(axis=-1, keepdims=True)).astype(np.float32)


class ProbabilityEnsemble:
    def __init__(self, policy):
        self.policy = dict(policy)
        self.tcn_weight = float(policy['tcn_weight'])
        self.tcn_temperature = float(policy['tcn_temperature'])
        self.embedding_temperature = float(policy['embedding_temperature'])
        if not (0 < self.tcn_weight < 1 and
                np.isfinite(self.tcn_temperature) and self.tcn_temperature > 0 and
                np.isfinite(self.embedding_temperature) and self.embedding_temperature > 0):
            raise ValueError('Ensemble requires both models and positive finite temperatures')

    def __call__(self, tcn, cosine):
        tcn, cosine = np.asarray(tcn, np.float32), np.asarray(cosine, np.float32)
        if (tcn.ndim != 2 or cosine.shape != (len(tcn), tcn.shape[1]-1) or
                not np.isfinite(tcn).all() or not np.isfinite(cosine).all() or
                np.any(tcn < 0) or not np.allclose(tcn.sum(axis=1), 1, atol=1e-3)):
            raise ValueError('Invalid paired model outputs')
        calibrated = softmax(np.log(np.maximum(tcn, 1e-12)) / self.tcn_temperature)
        conditional = softmax(cosine / self.embedding_temperature)
        background = calibrated[:, -1:]
        words = (self.tcn_weight * calibrated[:, :-1] +
                 (1-self.tcn_weight) * (1-background) * conditional)
        return np.concatenate([words, background], axis=1)


def load_ensemble(path, manifest_hash, model_hashes, names):
    path = Path(path)
    if not path.is_file():
        return None
    policy = json.loads(path.read_text(encoding='utf8'))
    if (policy.get('version') != 'paired_probability_ensemble_v1' or
            policy.get('manifest_sha256') != manifest_hash or
            policy.get('model_hashes') != model_hashes or policy.get('labels') != list(names)):
        return None  # Another export must use its own reviewed operating policy.
    return ProbabilityEnsemble(policy)


def embedded_ensemble(config, model_hashes):
    """New notebook exports carry their policy in the checksum-verified config."""
    if config.get('deployment_engine') != 'probability_ensemble':
        return None
    parameters = config.get('ensemble', {})
    if parameters.get('model_hashes') != model_hashes:
        raise ValueError('Exported ensemble does not match both loaded model hashes')
    return ProbabilityEnsemble(dict(parameters, decision_policy=dict(config['policy']),
        calibration=dict(config.get('calibration', {}))))
