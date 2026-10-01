"""Optional YAMNet (AudioSet, 521 classes) scores for comparison.

Needs `pip install tensorflow tensorflow-hub` and network access on first
run (the model is downloaded and cached by tensorflow-hub).
"""

from __future__ import annotations

import csv

import numpy as np

YAMNET_URL = "https://tfhub.dev/google/yamnet/1"
HOP_S = 0.48
# Substrings of AudioSet class names we want to plot.
CLASSES_OF_INTEREST = {
    "toothbrush": ["toothbrush"],
    "water": ["water tap", "sink (filling", "water"],
    "speech": ["speech"],
}

_model = None


def _load():
    global _model
    if _model is None:
        import tensorflow_hub as hub

        _model = hub.load(YAMNET_URL)
    return _model


def class_names() -> list[str]:
    model = _load()
    with open(model.class_map_path().numpy().decode()) as f:
        return [row["display_name"] for row in csv.DictReader(f)]


def yamnet_scores(x: np.ndarray) -> tuple[np.ndarray, dict[str, np.ndarray], dict[str, list[str]]]:
    """Return (frame centre times, {group: max score per frame}, {group: matched class names})."""
    model = _load()
    scores, _embeddings, _spec = model(x.astype(np.float32))
    scores = scores.numpy()
    names = [n.lower() for n in class_names()]
    t = np.arange(scores.shape[0]) * HOP_S + 0.48

    groups, matched = {}, {}
    taken: set[int] = set()
    for group, needles in CLASSES_OF_INTEREST.items():
        idx = [i for i, n in enumerate(names)
               if any(nd in n for nd in needles) and i not in taken]
        taken.update(idx)
        matched[group] = [names[i] for i in idx]
        groups[group] = scores[:, idx].max(axis=1) if idx else np.zeros(len(t))
    return t, groups, matched
