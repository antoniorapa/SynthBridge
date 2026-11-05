# SynthBridge

Applicazione Shiny per eseguire e confrontare algoritmi di generazione di dati sintetici tabellari (data augmentation). L'interfaccia e l'orchestrazione sono in R; ogni algoritmo può essere scritto in R o in Python ed è un "plugin" in una cartella a sé. L'interfaccia è in italiano e in inglese.

## Avvio rapido

```r
source("install_packages.R")   # una volta
shiny::runApp()
```

Funzionano subito, senza Python, i due algoritmi R: *Marginali indipendenti* (base R) e *synthpop · CART* (richiede il pacchetto `synthpop`). Per quelli Python serve Python ≥ 3.10 nel PATH: alla prima scelta l'interfaccia mostra il pulsante **Prepara ambiente**, oppure da terminale:

```bash
Rscript tools/setup_env.R --all
```

Se è installato [uv](https://docs.astral.sh/uv/) viene usato al posto di pip (molto più veloce, e permette di scegliere la versione di Python con `python_version`).

## Come è fatto

```
app.R                  interfaccia (Genera · Valuta · Algoritmi · Storico)
config.yaml            lingua di default, interprete Python, cartelle, timeout
R/
  registry.R           legge e valida algorithms/*/algorithm.yaml
  params_ui.R          YAML dei parametri -> controlli Shiny -> valori tipizzati
  runner.R             avvia i run in background, li controlla, li rilegge
  python_env.R         un ambiente virtuale per algoritmo (o per gruppo)
  evaluation.R         metriche di base reale vs sintetico
  i18n.R               testi dell'interfaccia in italiano e inglese
bridge/
  synthbridge.py       esegue adapter.py nell'ambiente dell'algoritmo
  synthbridge.R        equivalente per gli algoritmi R
algorithms/
  _template_python/    copiati da tools/new_algorithm.R
  _template_r/
  independent_marginals/   baseline, R
  synthpop_cart/           R, pacchetto synthpop
  gmm_sklearn/             Python leggero, per provare il ponte
  sdv_ctgan/               Python, SDV (ambiente "sdv" condiviso)
  sdv_gaussian_copula/     Python, SDV (stesso ambiente)
tools/                 script da console per gli studenti
envs/  runs/           generati, esclusi da git
```

### Perché un processo separato e non reticulate

Gli algoritmi dello stato dell'arte hanno dipendenze incompatibili tra loro (versioni diverse di torch, pandas, numpy). Con reticulate la sessione R può caricare un solo interprete Python alla volta, quindi un solo insieme di dipendenze. Qui invece ogni algoritmo dichiara un `python_env`, l'app crea un ambiente virtuale per ciascuno e lancia l'algoritmo con *quell'*interprete, comunicando via file:

```
R  scrive  runs/<run>/input.csv + job.json
          └─> envs/<env>/bin/python bridge/synthbridge.py ...
Py scrive  runs/<run>/synthetic.csv + status.json (+ progress.json, log.txt)
R  legge   e mostra
```

Vantaggi pratici: l'interfaccia non si blocca durante l'addestramento, un crash dell'algoritmo non fa cadere l'app, un run si può interrompere, e ogni run resta su disco (input, parametri, log, output) ed è riapribile dallo Storico. Gli algoritmi R passano dallo stesso meccanismo, quindi l'app non distingue i due casi.

Gli studenti non scrivono codice Shiny né toccano il ponte: per ogni algoritmo scrivono un `algorithm.yaml` (metadati e parametri, da cui l'interfaccia si genera da sola) e una funzione `generate(data, n_rows, params, info)` di poche decine di righe.

## Lingua (italiano / inglese)

I pulsanti **IT / EN** in alto a destra cambiano la lingua al volo, senza perdere i dati e i parametri inseriti; la scelta resta salvata nel browser. La lingua di partenza è `language` in `config.yaml`, e si può forzare dall'indirizzo con `?lang=en`.

- I testi dell'app sono tutti in [R/i18n.R](R/i18n.R): una voce per testo, con le colonne `it` e `en`. Le voci senza traduzione ricadono sull'italiano; per aggiungere una lingua basta aggiungerla a `LANGS` e alle voci.
- Negli `algorithm.yaml` i campi `name`, `description`, `label` e `help` possono essere un testo semplice (uguale nelle due lingue) oppure una mappa per lingua: `label: {it: "Epoche", en: "Epochs"}`.
- Anche i messaggi dei ponti (log del run) seguono la lingua scelta: l'app la passa ai processi figli nella variabile d'ambiente `SYNTHBRIDGE_LANG`.
- Gli script in `tools/` usano `language` di `config.yaml` per i messaggi condivisi con l'app; i loro testi propri sono in italiano.

## Configurazione per l'aula

- **Python di base**: in `config.yaml`, `python.base_interpreter` (default: cerca `python3`, `python`, `py`). Su Windows conviene installare Python da python.org con "Add to PATH", oppure indicare il percorso completo.
- **torch**: SDV installa torch con CUDA (alcuni GB). Sulle macchine senza GPU conviene la versione CPU: vedi il commento in `algorithms/sdv_ctgan/requirements.txt`.
- **Ambienti condivisi**: algoritmi con le stesse dipendenze possono usare lo stesso `python_env` (come i due SDV), con `requirements.txt` identici. Il primo che viene preparato crea l'ambiente per tutti.
- **Timeout**: `timeout_minutes` in `config.yaml`.
- **Server condiviso**: con Shiny Server o Posit Connect, `envs/` va preparato prima (`tools/setup_env.R --all`) e la cartella `runs/` deve essere scrivibile dall'utente del servizio.

## Organizzazione del lavoro degli studenti

Un algoritmo = una cartella = un gruppo. I gruppi non toccano file comuni, quindi con git ognuno lavora su un branch e le pull request non vanno in conflitto. `Rscript tools/check_algorithms.R` restituisce codice d'errore se un `algorithm.yaml` non è valido e si può usare come controllo automatico (es. GitHub Actions).

Le istruzioni per loro sono in [GUIDA_STUDENTI.md](GUIDA_STUDENTI.md).

## Stato

Provati end-to-end, in italiano e in inglese: l'interfaccia (generazione, valutazione, storico, cambio lingua), il ponte Python (`gmm_sklearn` su iris, mtcars, airquality, esoph) e il ponte R (`independent_marginals`). Non sono stati eseguiti `synthpop_cart` (richiede il pacchetto `synthpop`) e gli adapter SDV, che seguono l'API documentata di SDV 1.x ma non sono stati eseguiti; l'adapter CTGAN filtra comunque gli argomenti non supportati dalla versione installata.

## Estensioni possibili

- Metriche più ricche in `R/evaluation.R`: utilità ML (train on synthetic, test on real), distanza dal record reale più vicino, oppure chiamando `sdmetrics` tramite lo stesso ponte.
- Più run in parallelo (oggi uno alla volta per sessione).
- Supporto GPU / coda di job su un server di laboratorio.
