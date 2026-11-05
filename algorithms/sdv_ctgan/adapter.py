"""Adapter per CTGANSynthesizer della libreria SDV.

Schema tipico di un adapter verso una libreria esterna:
  1. tradurre i parametri dell'interfaccia negli argomenti della libreria
  2. costruire i metadati / preprocessare
  3. fit + sample
"""

import inspect

import pandas as pd


def build_metadata(data: pd.DataFrame, info: dict):
    """Metadati SDV, forzando i tipi che conosciamo dallo schema dell'app."""
    try:  # SDV >= 1.15
        from sdv.metadata import Metadata
        md = Metadata.detect_from_dataframe(data=data, table_name="data")
        update = lambda col, sdtype: md.update_column(column_name=col, sdtype=sdtype, table_name="data")
    except ImportError:  # SDV più vecchio
        from sdv.metadata import SingleTableMetadata
        md = SingleTableMetadata()
        md.detect_from_dataframe(data)
        update = lambda col, sdtype: md.update_column(column_name=col, sdtype=sdtype)
    for c in info["categorical_columns"]:
        update(c, "categorical")
    for c in info["numeric_columns"]:
        update(c, "numerical")
    return md


def supported_kwargs(cls, kwargs: dict) -> dict:
    """Tiene solo gli argomenti che questa versione della libreria accetta.

    Le API cambiano tra versioni (es. `cuda` -> `enable_gpu`): così l'adapter
    non si rompe, e nel log si vede cosa è stato ignorato.
    """
    accepted = inspect.signature(cls.__init__).parameters
    kept = {k: v for k, v in kwargs.items() if k in accepted}
    dropped = sorted(set(kwargs) - set(kept))
    if dropped:
        print(f"[avviso] argomenti non supportati da {cls.__name__} in questa versione: {dropped}", flush=True)
    return kept


def generate(data: pd.DataFrame, n_rows: int, params: dict, info: dict) -> pd.DataFrame:
    from sdv.single_table import CTGANSynthesizer

    if params["batch_size"] % params["pac"] != 0:
        raise ValueError(f"batch_size ({params['batch_size']}) deve essere multiplo di pac ({params['pac']})")

    metadata = build_metadata(data, info)
    kwargs = supported_kwargs(CTGANSynthesizer, dict(
        epochs=params["epochs"],
        batch_size=params["batch_size"],
        embedding_dim=params["embedding_dim"],
        generator_dim=tuple(params["generator_dim"]),
        discriminator_dim=tuple(params["discriminator_dim"]),
        generator_lr=params["generator_lr"],
        discriminator_lr=params["discriminator_lr"],
        pac=params["pac"],
        cuda=params["use_gpu"],          # versioni meno recenti
        enable_gpu=params["use_gpu"],    # versioni più recenti
        verbose=True,
    ))

    info["progress"](0.05, f"addestramento CTGAN ({params['epochs']} epoche)")
    synth = CTGANSynthesizer(metadata, **kwargs)
    synth.fit(data)
    info["progress"](0.95, "campionamento")
    return synth.sample(num_rows=n_rows)
