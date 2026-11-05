"""
Adapter Python per SynthBridge.

È l'UNICO file Python che dovete scrivere: fa da "traduttore" tra l'app e la
libreria dell'algoritmo (installata tramite requirements.txt).

L'app chiama:   generate(data, n_rows, params, info)

  data    pandas.DataFrame con i dati reali.
          Le colonne categoriche hanno dtype "category", le intere "Int64",
          le numeriche "float64", le logiche "boolean". I mancanti sono NA.
  n_rows  numero di righe sintetiche da produrre (int).
  params  dict con i parametri definiti in algorithm.yaml, già col tipo giusto
          (int, float, bool, str, list di int).
  info    dict con:
            info["seed"]                 seed scelto (già impostato per random, numpy, torch)
            info["categorical_columns"]  nomi delle colonne categoriche (incluse le logiche)
            info["numeric_columns"]      nomi delle colonne numeriche (incluse le intere)
            info["integer_columns"]      sottoinsieme delle numeriche che sono intere
            info["run_dir"]              cartella del run: ci potete salvare file extra
            info["progress"](f, msg)     aggiorna la barra di avanzamento (f tra 0 e 1)

Deve restituire un pandas.DataFrame con n_rows righe e LE STESSE COLONNE di data.

Qualunque print() finisce nel log visibile nell'interfaccia.
Qualunque eccezione viene mostrata all'utente con il messaggio d'errore.

Per provarlo senza interfaccia:   Rscript tools/run_algorithm.R <id> iris 200
"""

import pandas as pd


def generate(data: pd.DataFrame, n_rows: int, params: dict, info: dict) -> pd.DataFrame:
    # --- 1. Import della libreria (dentro la funzione: errori più chiari) ----
    # from nome_libreria import Modello

    # --- 2. Preprocessing, se la libreria lo richiede ------------------------
    # Molte librerie vogliono sapere quali colonne sono categoriche:
    #   cat_cols = info["categorical_columns"]

    # --- 3. Addestramento ----------------------------------------------------
    info["progress"](0.1, "addestramento")
    # model = Modello(epochs=params["epochs"], lr=params["learning_rate"], ...)
    # model.fit(data, discrete_columns=cat_cols)

    # --- 4. Campionamento ----------------------------------------------------
    info["progress"](0.9, "campionamento")
    # synthetic = model.sample(n_rows)

    # Segnaposto: ricampiona le righe reali. SOSTITUIRE con l'algoritmo vero!
    synthetic = data.sample(n=n_rows, replace=True, random_state=info["seed"]).reset_index(drop=True)

    # --- 5. Post-processing: stesse colonne, stessi tipi ---------------------
    return synthetic[list(data.columns)]
