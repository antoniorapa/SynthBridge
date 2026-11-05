"""Adapter per GaussianCopulaSynthesizer della libreria SDV."""

import pandas as pd


def build_metadata(data: pd.DataFrame, info: dict):
    try:  # SDV >= 1.15
        from sdv.metadata import Metadata
        md = Metadata.detect_from_dataframe(data=data, table_name="data")
        update = lambda col, sdtype: md.update_column(column_name=col, sdtype=sdtype, table_name="data")
    except ImportError:
        from sdv.metadata import SingleTableMetadata
        md = SingleTableMetadata()
        md.detect_from_dataframe(data)
        update = lambda col, sdtype: md.update_column(column_name=col, sdtype=sdtype)
    for c in info["categorical_columns"]:
        update(c, "categorical")
    for c in info["numeric_columns"]:
        update(c, "numerical")
    return md


def generate(data: pd.DataFrame, n_rows: int, params: dict, info: dict) -> pd.DataFrame:
    from sdv.single_table import GaussianCopulaSynthesizer

    synth = GaussianCopulaSynthesizer(
        build_metadata(data, info),
        default_distribution=params["default_distribution"],
        enforce_min_max_values=params["enforce_min_max_values"],
    )
    info["progress"](0.1, "stima della copula")
    synth.fit(data)
    info["progress"](0.9, "campionamento")
    return synth.sample(num_rows=n_rows)
