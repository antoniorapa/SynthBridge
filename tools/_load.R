# Carica il codice dell'app per gli script in tools/.
# Funziona sia con "Rscript tools/xxx.R" sia con source() da RStudio
# (in quel caso la directory di lavoro deve essere la cartella del progetto).

local({
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- if (length(file_arg)) {
    dirname(dirname(normalizePath(gsub("~+~", " ", sub("^--file=", "", file_arg[1]), fixed = TRUE), winslash = "/")))  # Rscript codifica gli spazi come ~+~
  } else {
    getwd()
  }
  if (!file.exists(file.path(root, "app.R"))) {
    stop("Non trovo app.R in ", root, ": lancia lo script dalla cartella del progetto.")
  }
  options(synthbridge.root = root)
  for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) {
    sys.source(f, envir = globalenv())
  }
  invisible(load_config())   # imposta anche la lingua di default (config.yaml: language)
})

# argomenti da riga di comando; da RStudio si può definire `args` prima del source()
cli_args <- function() {
  if (exists("args", envir = globalenv(), inherits = FALSE) && is.character(get("args", envir = globalenv()))) {
    return(get("args", envir = globalenv()))
  }
  commandArgs(trailingOnly = TRUE)
}

find_algorithm <- function(id) {
  reg <- load_algorithms()
  if (!is.null(reg$errors[[id]])) stop("algorithms/", id, " ha errori:\n", format_msgs(reg$errors[[id]]), call. = FALSE)
  spec <- reg$algorithms[[id]]
  if (is.null(spec)) stop("Algoritmo '", id, "' non trovato. Disponibili: ",
                          paste(names(reg$algorithms), collapse = ", "), call. = FALSE)
  spec
}
