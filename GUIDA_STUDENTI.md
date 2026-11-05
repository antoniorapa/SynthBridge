# Aggiungere un algoritmo a SynthBridge

Il vostro compito è collegare un algoritmo di generazione di dati sintetici all'app. Non dovete scrivere interfacce né conoscere Shiny: dovete preparare **una cartella** con tre file.

```
algorithms/<vostro_id>/
  algorithm.yaml      chi è l'algoritmo e quali parametri ha   (YAML)
  requirements.txt    le librerie Python che gli servono       (testo)
  adapter.py          la funzione generate()                   (Python, ~30 righe)
```

Se l'algoritmo esiste già come pacchetto R, al posto di `requirements.txt` e `adapter.py` usate `generate.R` (vedi `algorithms/_template_r`).

## I passi

Tutti i comandi vanno lanciati dalla cartella del progetto, nel terminale (in RStudio: scheda *Terminal*). Da console R si può fare lo stesso con `args <- c(...); source("tools/....R")`.

**1. Create la cartella**

```bash
Rscript tools/new_algorithm.R tabddpm
```

L'id deve essere in minuscolo, senza spazi (`tabddpm`, `ctgan_v2`, `great_llm`).

**2. Descrivete l'algoritmo in `algorithm.yaml`**

Nome, descrizione, riferimento all'articolo e soprattutto i **parametri**. Ogni parametro diventa automaticamente un controllo nell'interfaccia:

```yaml
params:
  - name: epochs            # nome con cui lo leggerete in Python: params["epochs"]
    label: "Epoche"         # testo mostrato nell'interfaccia
    type: integer           # integer | numeric | logical | choice | string | integer_list
    default: 300
    min: 1
    max: 5000
    help: "Una riga di spiegazione."
    advanced: true          # facoltativo: lo nasconde in "Parametri avanzati"
```

Esponete i parametri che contano davvero (quelli discussi nell'articolo), non tutti quelli della libreria. Mettete `advanced: true` su quelli che un utente normale non dovrebbe toccare.

L'interfaccia si può usare in italiano o in inglese. Per tradurre anche i vostri testi, scrivete `name`, `description`, `label` e `help` come mappa per lingua; se manca l'inglese viene mostrato l'italiano:

```yaml
    label: {it: "Epoche", en: "Epochs"}
    help:
      it: "Numero di passaggi sul dataset."
      en: "Number of passes over the dataset."
```

**3. Elencate le dipendenze in `requirements.txt`**

Una per riga, come per `pip`. Se il codice originale richiede versioni precise, fissatele (`torch==2.1.2`). Se l'algoritmo è solo su GitHub:

```
git+https://github.com/autore/repo.git
```

**4. Preparate l'ambiente Python**

```bash
Rscript tools/setup_env.R tabddpm
```

Crea `envs/tabddpm/` e ci installa le dipendenze. Va fatto una volta, e di nuovo con `--force` ogni volta che cambiate `requirements.txt`. Il vostro ambiente è separato da quello degli altri gruppi: potete usare le versioni che vi servono senza rompere nulla.

**5. Scrivete `generate()` in `adapter.py`**

```python
def generate(data, n_rows, params, info):
    from libreria import Modello

    model = Modello(epochs=params["epochs"])
    model.fit(data, discrete_columns=info["categorical_columns"])
    info["progress"](0.9, "campionamento")
    return model.sample(n_rows)
```

Cosa ricevete:

| argomento | contenuto |
|---|---|
| `data` | `pandas.DataFrame` con i dati reali; categoriche già in `category` |
| `n_rows` | quante righe generare |
| `params` | dizionario con i parametri di `algorithm.yaml`, già del tipo giusto |
| `info["categorical_columns"]`, `info["numeric_columns"]`, `info["integer_columns"]` | liste di nomi di colonna |
| `info["seed"]` | il seed (già impostato per `random`, `numpy` e `torch`) |
| `info["progress"](frazione, messaggio)` | aggiorna la barra di avanzamento |
| `info["run_dir"]` | cartella del run, se volete salvare file extra (es. il modello) |

Cosa dovete restituire: un `DataFrame` con `n_rows` righe e **le stesse colonne** di `data`.

Tutto ciò che stampate con `print()` compare nel log dell'interfaccia; qualunque eccezione viene mostrata con il suo messaggio.

**6. Provate da console, prima che nell'interfaccia**

```bash
Rscript tools/run_algorithm.R tabddpm iris 200
Rscript tools/run_algorithm.R tabddpm mtcars 500 epochs=5      # sovrascrive un parametro
Rscript tools/run_algorithm.R tabddpm dati/miei.csv 1000
```

È il modo più veloce per fare debug: vedete il log completo e il traceback Python. Ogni esecuzione lascia una cartella in `runs/` con `input.csv`, `job.json` (parametri), `log.txt` e il risultato.

**7. Controllate e aprite l'app**

```bash
Rscript tools/check_algorithms.R tabddpm
```

Poi `shiny::runApp()`: il vostro algoritmo compare nel menu. Se lo modificate mentre l'app è aperta, scheda **Algoritmi → Ricarica**.

## Esempi da copiare

- `algorithms/gmm_sklearn` – adapter completo con preprocessing a mano (one-hot, standardizzazione) e decodifica.
- `algorithms/sdv_ctgan` – adapter verso una libreria esterna, con traduzione dei parametri e gestione delle differenze tra versioni.
- `algorithms/synthpop_cart` – algoritmo R.

## Problemi frequenti

**"L'ambiente Python non esiste ancora"** – non avete eseguito il passo 4, oppure è fallito: guardate `envs/<python_env>.setup.log`.

**`ModuleNotFoundError`** – la libreria manca da `requirements.txt`, oppure l'avete aggiunta dopo aver creato l'ambiente: `Rscript tools/setup_env.R <id> --force`.

**"Nel risultato mancano le colonne"** – la libreria ha rinominato o eliminato colonne (succede con il one-hot). Ricostruitele prima del `return`.

**La libreria non accetta i tipi `category` o `Int64`** – convertite: `data.astype({c: "object" for c in info["categorical_columns"]})` oppure `data[c].astype("float64")`.

**La libreria vuole un file e non un DataFrame** – salvatelo in `info["run_dir"]` e passate il percorso.

**Il codice ufficiale è uno script e non una libreria** – copiate i file `.py` necessari dentro la vostra cartella: `adapter.py` può importarli direttamente (`from model import TabDDPM`). Citate sempre la fonte e la licenza in `algorithm.yaml`.

**L'addestramento è lentissimo** – mettete come default valori piccoli (poche epoche) adatti a una prova in aula; chi vuole risultati migliori li alza dall'interfaccia.

## Cosa consegnare

La sola cartella `algorithms/<vostro_id>/`, con:

1. `algorithm.yaml` con descrizione, riferimento bibliografico, autori e parametri documentati (`help`), possibilmente in italiano e inglese;
2. `requirements.txt` con versioni fissate;
3. `adapter.py` (o `generate.R`) funzionante con `iris`, `mtcars` e `airquality` (che contiene NA);
4. un breve `NOTE.md`: scelte fatte, limiti, tempi di esecuzione osservati.
