"""
synthbridge.py - ponte di SynthBridge tra l'app R e un algoritmo scritto in Python.

NON va modificato dagli studenti. Viene lanciato dall'app R in un processo
separato, con l'interprete Python dell'ambiente virtuale dell'algoritmo:

    <env>/bin/python synthbridge.py --algorithm-dir algorithms/xxx --run-dir runs/yyy

Contratto basato su file (tutto dentro --run-dir):
    input.csv      dati reali, scritti da R
    job.json       {"entry": "adapter.py", "function": "generate",
                    "n_rows": 1000, "seed": 42, "params": {...},
                    "schema": [{"name": "Species", "type": "categorical"}, ...]}
  ->
    synthetic.csv  dati sintetici prodotti dall'algoritmo
    status.json    {"ok": true/false, "error": "...", "traceback": "...", "elapsed": 12.3}
    progress.json  (facoltativo) {"fraction": 0.4, "message": "epoca 40/100"}

La funzione dello studente ha sempre questa firma:

    def generate(data: pd.DataFrame, n_rows: int, params: dict, info: dict) -> pd.DataFrame

La lingua dei messaggi arriva dall'app nella variabile d'ambiente SYNTHBRIDGE_LANG (it | en).
"""

import argparse
import importlib.util
import json
import os
import random
import sys
import time
import traceback

MESSAGES = {
    "it": {
        "missing_file": "Il file '{entry}' non esiste in {dir}",
        "missing_fn": "In '{entry}' manca la funzione '{fn}(data, n_rows, params, info)'",
        "start": "Avvio {fn}() su {rows} righe x {cols} colonne",
        "not_df": "generate() deve restituire un pandas.DataFrame, non {type}",
        "missing_cols": "Nel risultato mancano le colonne: {cols}",
        "done": "Completato: {rows} righe sintetiche in {secs:.1f}s",
    },
    "en": {
        "missing_file": "File '{entry}' not found in {dir}",
        "missing_fn": "'{entry}' does not define '{fn}(data, n_rows, params, info)'",
        "start": "Running {fn}() on {rows} rows x {cols} columns",
        "not_df": "generate() must return a pandas.DataFrame, not {type}",
        "missing_cols": "Columns missing from the result: {cols}",
        "done": "Completed: {rows} synthetic rows in {secs:.1f}s",
    },
}
LANG = os.environ.get("SYNTHBRIDGE_LANG", "it").lower()
if LANG not in MESSAGES:
    LANG = "it"


def tr(key, **kwargs):
    return MESSAGES[LANG][key].format(**kwargs)


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, default=str)
    os.replace(tmp, path)  # scrittura atomica: R non legge mai un file a metà


def set_seed(seed):
    if seed is None:
        return
    random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)
    try:
        import numpy as np
        np.random.seed(seed)
    except ImportError:
        pass
    try:
        import torch  # solo se l'ambiente lo ha già
        torch.manual_seed(seed)
    except ImportError:
        pass


def apply_schema(df, schema):
    """Ripristina i tipi che il CSV ha perso (fattori R -> category pandas)."""
    import pandas as pd
    for col in schema:
        name, kind = col["name"], col["type"]
        if name not in df.columns:
            continue
        if kind == "categorical":
            df[name] = df[name].astype("string").astype("category")
        elif kind == "integer":
            df[name] = pd.to_numeric(df[name], errors="coerce").astype("Int64")
        elif kind == "numeric":
            df[name] = pd.to_numeric(df[name], errors="coerce").astype("float64")
        elif kind == "logical":
            df[name] = df[name].map({"TRUE": True, "FALSE": False, True: True, False: False}).astype("boolean")
    return df


def load_function(algorithm_dir, entry, function):
    path = os.path.join(algorithm_dir, entry)
    if not os.path.exists(path):
        raise FileNotFoundError(tr("missing_file", entry=entry, dir=algorithm_dir))
    # la cartella dell'algoritmo va nel path, così l'adapter può importare suoi moduli
    sys.path.insert(0, os.path.abspath(algorithm_dir))
    spec = importlib.util.spec_from_file_location("synthbridge_adapter", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, function):
        raise AttributeError(tr("missing_fn", entry=entry, fn=function))
    return getattr(module, function)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--algorithm-dir", required=True)
    ap.add_argument("--run-dir", required=True)
    args = ap.parse_args()

    run_dir = os.path.abspath(args.run_dir)
    status_path = os.path.join(run_dir, "status.json")
    progress_path = os.path.join(run_dir, "progress.json")
    t0 = time.time()

    def progress(fraction, message=""):
        """Gli adapter possono chiamare info['progress'](0.5, 'epoca 50/100')."""
        write_json(progress_path, {"fraction": float(fraction), "message": str(message)})
        print(f"[progress] {fraction:.0%} {message}", flush=True)

    try:
        import pandas as pd

        with open(os.path.join(run_dir, "job.json"), encoding="utf-8") as f:
            job = json.load(f)

        data = pd.read_csv(os.path.join(run_dir, "input.csv"), keep_default_na=True)
        data = apply_schema(data, job.get("schema", []))
        set_seed(job.get("seed"))

        schema = job.get("schema", [])
        info = {
            "seed": job.get("seed"),
            "run_dir": run_dir,
            "schema": schema,
            "categorical_columns": [c["name"] for c in schema if c["type"] in ("categorical", "logical")],
            "numeric_columns": [c["name"] for c in schema if c["type"] in ("numeric", "integer")],
            "integer_columns": [c["name"] for c in schema if c["type"] == "integer"],
            "progress": progress,
        }

        fn = load_function(args.algorithm_dir, job.get("entry", "adapter.py"), job.get("function", "generate"))
        print(tr("start", fn=job.get("function", "generate"), rows=len(data), cols=data.shape[1]), flush=True)
        result = fn(data, int(job["n_rows"]), job.get("params", {}), info)

        if not isinstance(result, pd.DataFrame):
            raise TypeError(tr("not_df", type=type(result).__name__))
        missing = [c for c in data.columns if c not in result.columns]
        if missing:
            raise ValueError(tr("missing_cols", cols=missing))
        result = result[list(data.columns)]  # stesso ordine dei dati reali

        result.to_csv(os.path.join(run_dir, "synthetic.csv"), index=False)
        write_json(status_path, {"ok": True, "elapsed": round(time.time() - t0, 2), "n_rows": len(result)})
        print(tr("done", rows=len(result), secs=time.time() - t0), flush=True)
        return 0

    except Exception as e:  # noqa: BLE001 - vogliamo riportare all'app qualunque errore
        tb = traceback.format_exc()
        print(tb, file=sys.stderr, flush=True)
        write_json(status_path, {
            "ok": False,
            "error": f"{type(e).__name__}: {e}",
            "traceback": tb,
            "elapsed": round(time.time() - t0, 2),
        })
        return 1


if __name__ == "__main__":
    sys.exit(main())
