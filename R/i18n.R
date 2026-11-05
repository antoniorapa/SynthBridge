# Traduzioni dell'interfaccia (italiano / inglese).
#
#   tr("chiave", lang, ...)     testo nella lingua `lang` (con sprintf se ci sono argomenti)
#   tr_ui("chiave", ...)        per l'interfaccia statica: mette nel DOM tutte le lingue,
#                               il CSS mostra solo quella attiva. Cambiare lingua quindi
#                               non ridisegna i controlli e non perde i valori inseriti.
#   loc(x, lang)                campi di algorithm.yaml: testo semplice oppure mappa
#                               per lingua, es.  label: {it: "Epoche", en: "Epochs"}
#   loc_ui(x)                   come tr_ui() ma per un campo di algorithm.yaml
#
# Per aggiungere una lingua: aggiungerla a LANGS e una colonna a ogni voce di I18N
# (le voci senza traduzione ricadono sull'italiano).

LANGS <- c("it", "en")

I18N <- list(
  # --- barra e schede
  tagline            = c(it = "dati sintetici · R + Python", en = "synthetic data · R + Python"),
  language           = c(it = "Lingua", en = "Language"),
  nav_generate       = c(it = "Genera", en = "Generate"),
  nav_evaluate       = c(it = "Valuta", en = "Evaluate"),
  nav_algorithms     = c(it = "Algoritmi", en = "Algorithms"),
  nav_history        = c(it = "Storico", en = "History"),

  # --- Genera
  step_data          = c(it = "1 · Dati", en = "1 · Data"),
  step_algorithm     = c(it = "2 · Algoritmo", en = "2 · Algorithm"),
  step_params        = c(it = "3 · Parametri", en = "3 · Parameters"),
  src_example        = c(it = "Esempio", en = "Example"),
  src_upload         = c(it = "Carica CSV", en = "Upload CSV"),
  browse             = c(it = "Sfoglia…", en = "Browse…"),
  no_file            = c(it = "nessun file", en = "no file selected"),
  csv_sep            = c(it = "Separatore", en = "Separator"),
  sep_comma          = c(it = "virgola", en = "comma"),
  sep_semicolon      = c(it = "punto e virgola", en = "semicolon"),
  sep_tab            = c(it = "tab", en = "tab"),
  csv_dec            = c(it = "Decimali", en = "Decimal mark"),
  dec_point          = c(it = "punto", en = "point"),
  dec_comma          = c(it = "virgola", en = "comma"),
  ds_mixed           = c(it = "misto", en = "mixed"),
  ds_numeric         = c(it = "numerico", en = "numeric"),
  ds_categorical     = c(it = "categorico", en = "categorical"),
  ds_with_na         = c(it = "con NA", en = "with NA"),
  reset_params       = c(it = "Ripristina valori di default", en = "Reset to defaults"),
  n_rows             = c(it = "Righe sintetiche", en = "Synthetic rows"),
  seed               = c(it = "Seed", en = "Seed"),
  run                = c(it = "Genera", en = "Generate"),
  cancel             = c(it = "Interrompi", en = "Stop"),
  execution          = c(it = "Esecuzione", en = "Run"),
  download_csv       = c(it = "Scarica CSV", en = "Download CSV"),
  download_prefix    = c(it = "sintetico_", en = "synthetic_"),
  real_title         = c(it = "Dati reali · %s · %d righe × %d colonne", en = "Real data · %s · %d rows × %d columns"),
  synth_title        = c(it = "Dati sintetici", en = "Synthetic data"),
  synth_title_full   = c(it = "Dati sintetici · %s · %d righe · %s", en = "Synthetic data · %s · %d rows · %s"),
  reference          = c(it = "riferimento", en = "reference"),
  setup_env          = c(it = "Prepara ambiente", en = "Set up environment"),

  # --- stato dell'esecuzione
  no_runs_yet        = c(it = "Nessuna esecuzione ancora.", en = "No runs yet."),
  running_for        = c(it = " In esecuzione da %.0f s", en = " Running for %.0f s"),
  setup_running      = c(it = " Preparazione ambiente Python (%.0f s)…", en = " Setting up the Python environment (%.0f s)…"),
  setup_done         = c(it = " Ambiente pronto.", en = " Environment ready."),
  setup_failed       = c(it = " Preparazione dell'ambiente fallita.", en = " Environment setup failed."),
  completed_in       = c(it = " Completato in %.1f s", en = " Completed in %.1f s"),
  cancelled          = c(it = " Interrotto.", en = " Stopped."),

  # --- notifiche
  n_loaded           = c(it = "%d algoritmi caricati", en = "%d algorithms loaded"),
  n_with_errors      = c(it = ", %d con errori (vedi sotto)", en = ", %d with errors (see below)"),
  setup_already      = c(it = "Una preparazione è già in corso.", en = "An environment setup is already in progress."),
  setup_started      = c(it = "Preparazione dell'ambiente avviata: può richiedere qualche minuto.",
                         en = "Environment setup started: it may take a few minutes."),
  setup_ok_notif     = c(it = "Ambiente pronto.", en = "Environment ready."),
  setup_fail_notif   = c(it = "Preparazione fallita: guarda il log a destra.", en = "Setup failed: see the log on the right."),
  csv_unreadable     = c(it = "CSV non leggibile: %s", en = "Cannot read the CSV: %s"),
  job_busy           = c(it = "C'è già un'esecuzione in corso.", en = "A run is already in progress."),
  invalid_params     = c(it = "Parametri non validi", en = "Invalid parameters"),
  invalid_n_rows     = c(it = "Numero di righe non valido.", en = "Invalid number of rows."),
  done_notif         = c(it = "Fatto: %d righe in %.1f s", en = "Done: %d rows in %.1f s"),
  run_no_output      = c(it = "Questo run non ha prodotto dati sintetici.", en = "This run did not produce synthetic data."),

  # --- Valuta
  eval_empty         = c(it = "Genera dei dati (o apri un run dallo Storico) per vedere il confronto con i dati reali.",
                         en = "Generate some data (or open a run from History) to compare it with the real data."),
  vb_dist_title      = c(it = "Distanza media dalle marginali", en = "Mean distance from the marginals"),
  vb_dist_help       = c(it = "KS per numeriche, TVD per categoriche. 0 = identiche.",
                         en = "KS for numeric, TVD for categorical columns. 0 = identical."),
  vb_cor_title       = c(it = "Errore medio sulle correlazioni", en = "Mean correlation error"),
  vb_cor_help        = c(it = "Media di |cor reale − cor sintetica|.", en = "Mean of |real cor − synthetic cor|."),
  vb_copy_title      = c(it = "Copie esatte di righe reali", en = "Exact copies of real rows"),
  vb_copy_help       = c(it = "Quota di righe sintetiche identiche a una reale.",
                         en = "Share of synthetic rows identical to a real one."),
  not_available      = c(it = "n/d", en = "n/a"),
  card_marginal      = c(it = "Distribuzione per colonna", en = "Distribution by column"),
  card_cor           = c(it = "Correlazioni", en = "Correlations"),
  card_fidelity      = c(it = "Dettaglio per colonna", en = "Per-column detail"),
  # colonne della tabella di fedeltà
  ft_column          = c(it = "colonna", en = "column"),
  ft_type            = c(it = "tipo", en = "type"),
  ft_mean_real       = c(it = "media_reale", en = "mean_real"),
  ft_mean_synth      = c(it = "media_sint", en = "mean_synth"),
  ft_sd_real         = c(it = "sd_reale", en = "sd_real"),
  ft_sd_synth        = c(it = "sd_sint", en = "sd_synth"),
  ft_metric          = c(it = "metrica", en = "metric"),
  ft_distance        = c(it = "distanza", en = "distance"),
  ft_na_real         = c(it = "na_reale", en = "na_real"),
  ft_na_synth        = c(it = "na_sint", en = "na_synth"),
  type_numeric       = c(it = "numerica", en = "numeric"),
  type_categorical   = c(it = "categorica", en = "categorical"),
  # grafici
  plot_density       = c(it = "densità", en = "density"),
  plot_proportion    = c(it = "proporzione", en = "proportion"),
  plot_real          = c(it = "reale", en = "real"),
  plot_synthetic     = c(it = "sintetico", en = "synthetic"),
  plot_cor_title     = c(it = "|correlazione reale - correlazione sintetica|", en = "|real correlation - synthetic correlation|"),
  plot_need_two_num  = c(it = "Servono almeno due colonne numeriche.", en = "At least two numeric columns are needed."),

  # --- Algoritmi
  alg_registered     = c(it = "Algoritmi registrati", en = "Registered algorithms"),
  reload             = c(it = "Ricarica", en = "Reload"),
  alg_help           = c(it = "Ogni cartella in algorithms/ con un file algorithm.yaml compare qui. Dopo aver modificato un algoritmo premi Ricarica: non serve riavviare l'app.",
                         en = "Every folder in algorithms/ with an algorithm.yaml file shows up here. After editing an algorithm press Reload: there is no need to restart the app."),
  no_valid_alg       = c(it = "Nessun algoritmo valido trovato.", en = "No valid algorithm found."),
  errors_card        = c(it = "Cartelle con errori (%d) - non compaiono nel menu", en = "Folders with errors (%d) - not shown in the menu"),
  col_message        = c(it = "messaggio", en = "message"),
  col_name           = c(it = "nome", en = "name"),
  col_env            = c(it = "ambiente", en = "environment"),
  col_params         = c(it = "parametri", en = "parameters"),
  col_authors        = c(it = "autori", en = "authors"),
  col_ready          = c(it = "pronto", en = "ready"),
  yes                = c(it = "sì", en = "yes"),
  no                 = c(it = "no", en = "no"),

  # --- Storico
  runs_title         = c(it = "Esecuzioni passate", en = "Past runs"),
  refresh            = c(it = "Aggiorna", en = "Refresh"),
  open_in_eval       = c(it = "Apri in Valuta", en = "Open in Evaluate"),
  run_folder         = c(it = "Cartella: ", en = "Folder: "),
  col_when           = c(it = "quando", en = "when"),
  col_algorithm      = c(it = "algoritmo", en = "algorithm"),
  col_dataset        = c(it = "dataset", en = "dataset"),
  col_rows           = c(it = "righe", en = "rows"),
  col_outcome        = c(it = "esito", en = "outcome"),
  col_seconds        = c(it = "secondi", en = "seconds"),
  outcome_running    = c(it = "in corso / interrotto", en = "running / interrupted"),
  outcome_ok         = c(it = "ok", en = "ok"),
  outcome_error      = c(it = "errore", en = "error"),

  # --- parametri (R/params_ui.R)
  no_params          = c(it = "Questo algoritmo non ha parametri.", en = "This algorithm has no parameters."),
  advanced_params    = c(it = "Parametri avanzati (%d)", en = "Advanced parameters (%d)"),
  err_missing_value  = c(it = "valore mancante", en = "missing value"),
  err_not_integer    = c(it = "deve essere un intero", en = "must be an integer"),
  err_int_list       = c(it = "scrivi interi separati da virgole, es. 256, 256", en = "enter integers separated by commas, e.g. 256, 256"),
  err_min            = c(it = "deve essere >= %s", en = "must be >= %s"),
  err_max            = c(it = "deve essere <= %s", en = "must be <= %s"),

  # --- validazione di algorithm.yaml (R/registry.R)
  v_no_yaml          = c(it = "manca il file algorithm.yaml", en = "algorithm.yaml is missing"),
  v_bad_yaml         = c(it = "algorithm.yaml non è YAML valido: %s", en = "algorithm.yaml is not valid YAML: %s"),
  v_unexpected       = c(it = "errore inatteso: %s", en = "unexpected error: %s"),
  v_dup_id           = c(it = "id duplicato '%s'", en = "duplicate id '%s'"),
  v_no_name          = c(it = "campo 'name' mancante", en = "missing 'name' field"),
  v_text_field       = c(it = "campo '%s': deve essere un testo oppure una mappa per lingua, es. {it: \"...\", en: \"...\"}",
                         en = "field '%s': must be a string or a per-language map, e.g. {it: \"...\", en: \"...\"}"),
  v_backend          = c(it = "campo 'backend' deve essere uno tra: %s", en = "field 'backend' must be one of: %s"),
  v_entry            = c(it = "il file '%s' indicato in 'entry' non esiste", en = "the file '%s' given in 'entry' does not exist"),
  v_requirements     = c(it = "manca requirements.txt (può anche essere vuoto)", en = "requirements.txt is missing (it may be empty)"),
  v_param_index      = c(it = "params[%d]", en = "params[%d]"),
  v_param_where      = c(it = "parametro '%s'", en = "parameter '%s'"),
  v_param_no_name    = c(it = "%s senza 'name'", en = "%s has no 'name'"),
  v_param_ident      = c(it = "%s: il nome deve essere un identificatore (lettere, cifre, _)", en = "%s: the name must be an identifier (letters, digits, _)"),
  v_param_dup        = c(it = "%s: nome duplicato", en = "%s: duplicate name"),
  v_param_type       = c(it = "%s: 'type' deve essere uno tra %s", en = "%s: 'type' must be one of %s"),
  v_param_default    = c(it = "%s: manca 'default'", en = "%s: missing 'default'"),
  v_choice_empty     = c(it = "%s: un 'choice' deve avere 'choices'", en = "%s: a 'choice' needs 'choices'"),
  v_choice_default   = c(it = "%s: 'default' non è tra le 'choices'", en = "%s: 'default' is not among the 'choices'"),
  v_default_num      = c(it = "%s: 'default' deve essere un numero", en = "%s: 'default' must be a number"),
  v_default_min      = c(it = "%s: 'default' < 'min'", en = "%s: 'default' < 'min'"),
  v_default_max      = c(it = "%s: 'default' > 'max'", en = "%s: 'default' > 'max'"),

  # --- prontezza degli algoritmi
  r_missing_pkgs     = c(it = "Pacchetti R mancanti: %s. Esegui install.packages(c(%s))", en = "Missing R packages: %s. Run install.packages(c(%s))"),
  r_ready            = c(it = "Algoritmo R pronto.", en = "R algorithm ready."),
  py_ready           = c(it = "Ambiente Python '%s' pronto.", en = "Python environment '%s' ready."),
  py_missing         = c(it = "L'ambiente Python '%s' non esiste ancora: premi 'Prepara ambiente' (serve una volta sola).",
                         en = "The Python environment '%s' does not exist yet: press 'Set up environment' (needed only once)."),

  # --- esecuzione (R/runner.R) e ambienti (R/python_env.R)
  py_env_not_ready   = c(it = "Ambiente Python non pronto per '%s'", en = "Python environment not ready for '%s'"),
  timeout            = c(it = "Interrotto dopo %s minuti (timeout_minutes in config.yaml).", en = "Stopped after %s minutes (timeout_minutes in config.yaml)."),
  no_result          = c(it = "Il processo è terminato (codice %s) senza produrre risultati. Guarda il log.",
                         en = "The process exited (code %s) without producing results. Check the log."),
  cancelled_by_user  = c(it = "Interrotto dall'utente", en = "Stopped by the user"),
  no_python          = c(it = "Nessun interprete Python trovato. Installa Python 3.10+ oppure indica il percorso in config.yaml (python.base_interpreter).",
                         en = "No Python interpreter found. Install Python 3.10+ or set its path in config.yaml (python.base_interpreter)."),
  base_interp_missing = c(it = "python.base_interpreter in config.yaml non esiste: %s", en = "python.base_interpreter in config.yaml does not exist: %s"),
  cmd_failed         = c(it = "Comando fallito (codice %s): %s", en = "Command failed (code %s): %s"),
  env_ready_at       = c(it = "Ambiente pronto: %s", en = "Environment ready: %s"),
  setup_r_nothing    = c(it = "%s: algoritmo R, niente da fare", en = "%s: R algorithm, nothing to do"),
  setup_header       = c(it = "=== %s -> ambiente '%s' ===", en = "=== %s -> environment '%s' ==="),

  # --- DataTables
  dt_search          = c(it = "Cerca:", en = "Search:"),
  dt_info            = c(it = "Righe da _START_ a _END_ di _TOTAL_", en = "Showing _START_ to _END_ of _TOTAL_ rows"),
  dt_info_empty      = c(it = "Nessuna riga", en = "No rows"),
  dt_info_filtered   = c(it = "(filtrate da _MAX_ totali)", en = "(filtered from _MAX_ total)"),
  dt_zero            = c(it = "Nessun risultato", en = "No matching rows"),
  dt_empty           = c(it = "Nessun dato", en = "No data"),
  dt_length          = c(it = "Mostra _MENU_ righe", en = "Show _MENU_ rows"),
  dt_previous        = c(it = "Precedente", en = "Previous"),
  dt_next            = c(it = "Successiva", en = "Next")
)

# Lingua di default fuori dall'interfaccia (console, processi figli):
# variabile d'ambiente SYNTHBRIDGE_LANG > `language` di config.yaml > italiano.
default_lang <- function() {
  env <- tolower(Sys.getenv("SYNTHBRIDGE_LANG"))
  if (env %in% LANGS) return(env)
  opt <- tolower(getOption("synthbridge.lang", "it"))
  if (opt %in% LANGS) opt else "it"
}

valid_lang <- function(lang) if (isTRUE(lang %in% LANGS)) lang else default_lang()

tr <- function(key, lang = default_lang(), ...) {
  entry <- I18N[[key]]
  if (is.null(entry)) return(key)   # chiave mancante: meglio vederla che bloccare l'app
  s <- if (!is.na(entry[lang])) entry[[lang]] else entry[[1]]
  if (...length()) sprintf(s, ...) else s
}

# Messaggi "da tradurre più tardi": il registro degli algoritmi li produce al
# caricamento, l'interfaccia li mostra nella lingua scelta da chi guarda.
i18n_msg <- function(key, ...) structure(list(key = key, args = list(...)), class = "i18n_msg")

format_msg <- function(m, lang = default_lang()) {
  if (!inherits(m, "i18n_msg")) return(as.character(m))
  args <- lapply(m$args, function(a) if (inherits(a, "i18n_msg")) format_msg(a, lang) else a)
  do.call(tr, c(list(m$key, lang), args))
}

format_msgs <- function(msgs, lang = default_lang()) {
  paste(vapply(msgs, format_msg, character(1), lang = lang), collapse = "\n")
}

# --- campi multilingua di algorithm.yaml -------------------------------------

is_localized <- function(x) is.list(x) && !is.null(names(x))

loc <- function(x, lang = default_lang()) {
  if (is.null(x)) return(NULL)
  if (is_localized(x)) {
    v <- x[[lang]] %||% x[["it"]] %||% x[["en"]] %||% x[[1]]
    return(as.character(v))
  }
  as.character(unlist(x))
}

# --- interfaccia statica ------------------------------------------------------

i18n_spans <- function(texts, block = FALSE) {
  wrap <- if (block) htmltools::tags$div else htmltools::tags$span
  htmltools::tagList(lapply(LANGS, function(l) wrap(class = paste0("i18n i18n-", l), lang = l, texts[[l]])))
}

tr_ui <- function(key, ...) i18n_spans(setNames(lapply(LANGS, function(l) tr(key, l, ...)), LANGS))

loc_ui <- function(x) {
  if (!is_localized(x)) return(loc(x))
  i18n_spans(setNames(lapply(LANGS, function(l) loc(x, l)), LANGS))
}

# Placeholder di un campo di testo (non può contenere HTML): lo aggiorna il JS.
i18n_placeholder <- function(tag, key, selector = "input.form-control") {
  attrs <- c(list(`data-i18n-placeholder` = ""),
             setNames(lapply(LANGS, function(l) tr(key, l)), paste0("data-placeholder-", LANGS)))
  do.call(htmltools::tagAppendAttributes, c(list(tag), attrs, list(.cssSelector = selector)))
}

lang_switch <- function() {
  htmltools::tags$div(class = "btn-group btn-group-sm sb-lang", role = "group", `aria-label` = "Lingua / Language",
    lapply(LANGS, function(l) htmltools::tags$button(type = "button", class = "btn", `data-set-lang` = l, toupper(l)))
  )
}

# CSS e JS del cambio lingua. La lingua scelta resta nel browser (localStorage);
# si può forzare anche dall'indirizzo: ...?lang=en
i18n_head <- function(default) {
  css <- paste(vapply(LANGS, function(l) {
    sprintf('html[data-lang="%s"] .i18n:not(.i18n-%s) { display: none !important; }', l, l)
  }, character(1)), collapse = "\n")
  js <- sprintf('
(function () {
  var LANGS = %s, DEFAULT = "%s", KEY = "synthbridge.lang";
  function initial() {
    try { var q = new URLSearchParams(window.location.search).get("lang"); if (LANGS.indexOf(q) >= 0) return q; } catch (e) {}
    try { var s = window.localStorage.getItem(KEY); if (LANGS.indexOf(s) >= 0) return s; } catch (e) {}
    return DEFAULT;
  }
  var current = initial();
  function apply(lang) {
    current = lang;
    var html = document.documentElement;
    html.setAttribute("data-lang", lang);
    html.setAttribute("lang", lang);
    document.querySelectorAll("[data-i18n-placeholder]").forEach(function (el) {
      var p = el.getAttribute("data-placeholder-" + lang);
      if (p !== null) el.setAttribute("placeholder", p);
    });
    document.querySelectorAll("[data-set-lang]").forEach(function (b) {
      var on = b.getAttribute("data-set-lang") === lang;
      b.classList.toggle("active", on);
      b.setAttribute("aria-pressed", on ? "true" : "false");
    });
  }
  apply(current);   // prima che la pagina compaia: niente sfarfallio
  document.addEventListener("click", function (e) {
    var b = e.target.closest && e.target.closest("[data-set-lang]");
    if (!b) return;
    e.preventDefault();
    var lang = b.getAttribute("data-set-lang");
    try { window.localStorage.setItem(KEY, lang); } catch (err) {}
    apply(lang);
    if (window.Shiny && window.Shiny.setInputValue) window.Shiny.setInputValue("lang", lang);
  });
  document.addEventListener("DOMContentLoaded", function () {
    apply(current);
    if (window.jQuery) window.jQuery(document).on("shiny:connected", function () {
      window.Shiny.setInputValue("lang", current);
    });
  });
})();', jsonlite::toJSON(LANGS), default)
  htmltools::tags$head(htmltools::tags$style(htmltools::HTML(css)), htmltools::tags$script(htmltools::HTML(js)))
}

# Testi delle tabelle DT.
dt_language <- function(lang) list(
  search = tr("dt_search", lang), info = tr("dt_info", lang), infoEmpty = tr("dt_info_empty", lang),
  infoFiltered = tr("dt_info_filtered", lang), zeroRecords = tr("dt_zero", lang),
  emptyTable = tr("dt_empty", lang), lengthMenu = tr("dt_length", lang),
  paginate = list(previous = tr("dt_previous", lang), `next` = tr("dt_next", lang))
)
