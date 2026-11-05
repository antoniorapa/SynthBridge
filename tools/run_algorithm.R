# Esegue un algoritmo SENZA interfaccia: il modo più rapido per fare debug.
#
#   Rscript tools/run_algorithm.R <id> [dataset] [n_righe] [param=valore ...]
#
#   Rscript tools/run_algorithm.R gmm_sklearn
#   Rscript tools/run_algorithm.R gmm_sklearn mtcars 500
#   Rscript tools/run_algorithm.R sdv_ctgan dati/miei.csv 1000 epochs=5 batch_size=100
#
# dataset: nome di un dataset di R (iris, mtcars, airquality, ...) o percorso di un CSV.
# Da RStudio:  args <- c("gmm_sklearn", "iris", "200"); source("tools/run_algorithm.R")

local({ f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
        source(file.path(if (length(f)) dirname(gsub("~+~", " ", sub("^--file=", "", f[1]), fixed = TRUE)) else "tools", "_load.R")) })

a <- cli_args()
if (length(a) < 1) stop("Uso: Rscript tools/run_algorithm.R <id> [dataset] [n_righe] [param=valore ...]", call. = FALSE)

overrides <- a[grepl("=", a, fixed = TRUE)]
pos <- a[!grepl("=", a, fixed = TRUE)]
id <- pos[1]
dataset <- if (length(pos) >= 2) pos[2] else "iris"
n_rows <- if (length(pos) >= 3) as.integer(pos[3]) else NA

data <- if (file.exists(dataset)) {
  utils::read.csv(dataset, stringsAsFactors = TRUE, check.names = FALSE)
} else {
  get(dataset, envir = asNamespace("datasets"))
}
data <- normalize_data(data)
if (is.na(n_rows)) n_rows <- nrow(data)

spec <- find_algorithm(id)
cfg <- load_config()
r <- algorithm_ready(spec, cfg)
if (!r$ok) stop(r$msg, call. = FALSE)

# parametri: default di algorithm.yaml, sovrascritti da param=valore
params <- default_params(spec)
for (o in overrides) {
  k <- sub("=.*$", "", o); v <- sub("^[^=]*=", "", o)
  p <- Find(function(x) x$name == k, spec$params)
  if (is.null(p)) stop("Parametro sconosciuto: ", k, call. = FALSE)
  params[[k]] <- switch(p$type,
    integer = as.integer(v), numeric = as.numeric(v), logical = as.logical(toupper(v)),
    integer_list = as.list(as.integer(strsplit(v, ",")[[1]])),
    choice = if (is.numeric(unlist(p$choices))) as.numeric(v) else v,
    v)
}

cat(sprintf("Algoritmo: %s (%s)\nDati: %s, %d x %d -> %d righe sintetiche\nParametri: %s\n\n",
            loc(spec$name), spec$backend, dataset, nrow(data), ncol(data), n_rows,
            jsonlite::toJSON(params, auto_unbox = TRUE)))

synth <- run_algorithm_sync(spec, data, params, n_rows = n_rows, cfg = cfg)

cat("\n--- prime righe dei dati sintetici ---\n")
print(utils::head(synth))
cat("\n--- confronto per colonna ---\n")
print(localize_fidelity(fidelity_table(data, synth)[, c("column", "type", "metric", "distance")]), row.names = FALSE)
