"""Gaussian Mixture su dati misti (one-hot per le categoriche)."""

import numpy as np
import pandas as pd
from sklearn.mixture import GaussianMixture


def generate(data: pd.DataFrame, n_rows: int, params: dict, info: dict) -> pd.DataFrame:
    cat_cols = info["categorical_columns"]
    num_cols = info["numeric_columns"]

    # 1. codifica: numeriche standardizzate (NA -> mediana), categoriche one-hot
    num = data[num_cols].astype("float64")
    num = num.fillna(num.median())
    mean, std = num.mean(), num.std().replace(0, 1).fillna(1)
    z = (num - mean) / std
    if cat_cols:
        onehot = pd.get_dummies(data[cat_cols].astype("string").fillna("<NA>"), prefix_sep="=@=", dtype=float)
    else:  # dataset tutto numerico (es. mtcars): get_dummies fallirebbe su zero colonne
        onehot = pd.DataFrame(index=data.index)
    X = pd.concat([z, onehot], axis=1)

    # 2. modello
    info["progress"](0.1, "addestramento GMM")
    gmm = GaussianMixture(
        n_components=min(params["n_components"], len(X)),
        covariance_type=params["covariance_type"],
        max_iter=params["max_iter"],
        reg_covar=params["reg_covar"],
        random_state=info["seed"],
    ).fit(X.to_numpy())

    # 3. campionamento e decodifica
    info["progress"](0.8, "campionamento")
    sample, _ = gmm.sample(n_rows)
    S = pd.DataFrame(sample, columns=X.columns)
    out = pd.DataFrame(index=range(n_rows))
    for c in num_cols:
        out[c] = S[c] * std[c] + mean[c]
        if c in info["integer_columns"]:
            out[c] = out[c].round().astype("Int64")
    for c in cat_cols:
        block = [k for k in onehot.columns if k.startswith(c + "=@=")]
        labels = [k.split("=@=", 1)[1] for k in block]
        out[c] = np.array(labels, dtype=object)[S[block].to_numpy().argmax(axis=1)]
        out[c] = out[c].replace("<NA>", pd.NA)

    # la permutazione rimescola le righe (gmm.sample le ordina per componente)
    rng = np.random.default_rng(info["seed"])
    return out.iloc[rng.permutation(n_rows)].reset_index(drop=True)
