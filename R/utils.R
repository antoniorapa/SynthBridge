# Funzioni di servizio usate in tutta l'app.

`%||%` <- function(a, b) if (is.null(a)) b else a

# Cartella radice del progetto (dove sta app.R). Impostata da app.R / tools.
project_root <- function() getOption("synthbridge.root", getwd())

project_path <- function(...) file.path(project_root(), ...)

load_config <- function() {
  cfg <- yaml::read_yaml(project_path("config.yaml"))
  cfg$runs_dir <- project_path(cfg$runs_dir %||% "runs")
  cfg$python$envs_dir <- project_path(cfg$python$envs_dir %||% "envs")
  lang <- tolower(cfg$language %||% "it")
  cfg$language <- if (lang %in% LANGS) lang else "it"
  options(synthbridge.lang = cfg$language)   # lingua di default per console e processi figli
  cfg
}

is_windows <- function() .Platform$OS.type == "windows"

rscript_path <- function() {
  file.path(R.home("bin"), if (is_windows()) "Rscript.exe" else "Rscript")
}

write_json_file <- function(obj, path) {
  jsonlite::write_json(obj, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
}

read_json_safely <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
}

# Ultime n righe di un file di log (per mostrarle nell'interfaccia).
tail_file <- function(path, n = 40) {
  if (!file.exists(path)) return("")
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character())
  paste(utils::tail(lines, n), collapse = "\n")
}

# Tipo "logico" di ogni colonna: è ciò che arriva agli algoritmi come schema.
column_type <- function(x) {
  if (is.logical(x)) return("logical")
  if (is.integer(x)) return("integer")
  if (is.numeric(x)) return("numeric")
  "categorical"   # factor, character, date convertite in testo...
}

data_schema <- function(df) {
  lapply(names(df), function(n) list(name = n, type = column_type(df[[n]])))
}

# Riporta i dati sintetici letti da CSV agli stessi tipi dei dati reali.
coerce_like <- function(synth, real) {
  for (n in intersect(names(real), names(synth))) {
    x <- real[[n]]
    y <- synth[[n]]
    synth[[n]] <- if (is.factor(x)) {
      factor(as.character(y), levels = union(levels(x), unique(as.character(y))))
    } else if (is.logical(x)) {
      as.logical(y)
    } else if (is.integer(x)) {
      as.integer(round(suppressWarnings(as.numeric(y))))
    } else if (is.numeric(x)) {
      suppressWarnings(as.numeric(y))
    } else {
      as.character(y)
    }
  }
  synth
}

# Prepara un data.frame "pulito" per gli algoritmi: character -> factor.
normalize_data <- function(df) {
  df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
  for (n in names(df)) {
    x <- df[[n]]
    if (is.character(x) || inherits(x, c("Date", "POSIXt"))) df[[n]] <- factor(as.character(x))
  }
  rownames(df) <- NULL
  df
}
