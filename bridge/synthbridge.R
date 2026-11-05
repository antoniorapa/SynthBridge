# synthbridge.R - ponte di SynthBridge per gli algoritmi scritti in R.
#
# NON va modificato dagli studenti. Gemello di synthbridge.py: stesso contratto
# su file, così l'app tratta algoritmi R e Python nello stesso modo e anche gli
# algoritmi R girano in un processo separato (l'interfaccia non si blocca).
#
#   Rscript synthbridge.R <algorithm_dir> <run_dir>
#
# La funzione dello studente ha sempre questa firma:
#   generate <- function(data, n_rows, params, info) { ...; data.frame }
#
# La lingua dei messaggi arriva dall'app nella variabile d'ambiente SYNTHBRIDGE_LANG (it | en).

`%||%` <- function(a, b) if (is.null(a)) b else a   # in base R solo dalla 4.4

MESSAGES <- list(
  it = c(missing_file = "Il file '%s' non esiste in %s",
         missing_fn = "In '%s' manca la funzione %s(data, n_rows, params, info)",
         start = "Avvio %s() su %d righe x %d colonne",
         not_df = "generate() deve restituire un data.frame, non %s",
         missing_cols = "Nel risultato mancano le colonne: %s",
         done = "Completato: %d righe sintetiche in %.1fs",
         error = "ERRORE: "),
  en = c(missing_file = "File '%s' not found in %s",
         missing_fn = "'%s' does not define %s(data, n_rows, params, info)",
         start = "Running %s() on %d rows x %d columns",
         not_df = "generate() must return a data.frame, not %s",
         missing_cols = "Columns missing from the result: %s",
         done = "Completed: %d synthetic rows in %.1fs",
         error = "ERROR: ")
)
LANG <- tolower(Sys.getenv("SYNTHBRIDGE_LANG", "it"))
if (!LANG %in% names(MESSAGES)) LANG <- "it"
tr <- function(key, ...) sprintf(MESSAGES[[LANG]][[key]], ...)

args <- commandArgs(trailingOnly = TRUE)
algorithm_dir <- normalizePath(args[1])
run_dir <- normalizePath(args[2])
status_path <- file.path(run_dir, "status.json")
progress_path <- file.path(run_dir, "progress.json")
t0 <- Sys.time()

write_json_atomic <- function(obj, path) {
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null")
  file.rename(tmp, path)
}

progress <- function(fraction, message = "") {
  write_json_atomic(list(fraction = fraction, message = message), progress_path)
  cat(sprintf("[progress] %d%% %s\n", as.integer(round(100 * fraction)), message))
  flush(stdout())   # stdout è un file: senza flush il log arriva all'app solo alla fine
}

apply_schema <- function(df, schema) {
  for (col in schema) {
    if (!col$name %in% names(df)) next
    x <- df[[col$name]]
    df[[col$name]] <- switch(col$type,
      categorical = factor(x),
      integer     = as.integer(x),
      numeric     = as.numeric(x),
      logical     = as.logical(x),
      x
    )
  }
  df
}

trace <- NULL   # pila delle chiamate nel punto dell'errore (non in quello del gestore)

result <- tryCatch(withCallingHandlers({
  job <- jsonlite::read_json(file.path(run_dir, "job.json"), simplifyVector = FALSE)
  data <- utils::read.csv(file.path(run_dir, "input.csv"), stringsAsFactors = FALSE, check.names = FALSE,
                          fileEncoding = "UTF-8")
  data <- apply_schema(data, job$schema)
  if (!is.null(job$seed)) set.seed(job$seed)

  types <- vapply(job$schema, function(c) c$type, character(1))
  names_ <- vapply(job$schema, function(c) c$name, character(1))
  info <- list(
    seed = job$seed,
    run_dir = run_dir,
    schema = job$schema,
    categorical_columns = names_[types %in% c("categorical", "logical")],
    numeric_columns = names_[types %in% c("numeric", "integer")],
    integer_columns = names_[types == "integer"],
    progress = progress
  )

  entry <- file.path(algorithm_dir, job$entry %||% "generate.R")
  if (!file.exists(entry)) stop(tr("missing_file", basename(entry), algorithm_dir))
  env <- new.env(parent = globalenv())
  old_wd <- setwd(algorithm_dir)        # l'adapter può fare source() di file suoi
  tryCatch(sys.source(entry, envir = env), finally = setwd(old_wd))
  fname <- job$`function` %||% "generate"
  if (!exists(fname, envir = env, inherits = FALSE)) stop(tr("missing_fn", basename(entry), fname))

  cat(tr("start", fname, nrow(data), ncol(data)), "\n", sep = "")
  out <- get(fname, envir = env)(data, as.integer(job$n_rows), job$params, info)

  if (!is.data.frame(out)) stop(tr("not_df", class(out)[1]))
  missing <- setdiff(names(data), names(out))
  if (length(missing)) stop(tr("missing_cols", paste(missing, collapse = ", ")))
  out <- out[, names(data), drop = FALSE]

  utils::write.csv(out, file.path(run_dir, "synthetic.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
  write_json_atomic(list(ok = TRUE, elapsed = elapsed, n_rows = nrow(out)), status_path)
  cat(tr("done", nrow(out), elapsed), "\n", sep = "")
  0L
}, error = function(e) trace <<- sys.calls()), error = function(e) {
  msg <- conditionMessage(e)
  calls <- paste(utils::capture.output(print(trace)), collapse = "\n")
  message(tr("error"), msg)
  write_json_atomic(list(
    ok = FALSE, error = msg, traceback = calls,
    elapsed = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
  ), status_path)
  1L
})

quit(status = result, save = "no")
