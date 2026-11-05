# Crea una nuova cartella algoritmo partendo dal template.
#
#   Rscript tools/new_algorithm.R tabddpm            # Python (default)
#   Rscript tools/new_algorithm.R arf_forest r       # R
#
# Da RStudio:  args <- c("tabddpm"); source("tools/new_algorithm.R")

local({ f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
        source(file.path(if (length(f)) dirname(gsub("~+~", " ", sub("^--file=", "", f[1]), fixed = TRUE)) else "tools", "_load.R")) })

a <- cli_args()
if (length(a) < 1) stop("Uso: Rscript tools/new_algorithm.R <id> [python|r]", call. = FALSE)
id <- a[1]
backend <- if (length(a) >= 2) tolower(a[2]) else "python"

if (!grepl("^[a-z][a-z0-9_]*$", id)) {
  stop("L'id deve contenere solo minuscole, cifre e _ e iniziare con una lettera (es. ctgan_v2).", call. = FALSE)
}
if (!backend %in% c("python", "r")) stop("Il backend deve essere 'python' o 'r'.", call. = FALSE)

src <- project_path("algorithms", paste0("_template_", backend))
dst <- project_path("algorithms", id)
if (dir.exists(dst)) stop("Esiste già: ", dst, call. = FALSE)

dir.create(dst)
file.copy(list.files(src, full.names = TRUE), dst)
yaml_path <- file.path(dst, "algorithm.yaml")
writeLines(gsub("__ID__", id, readLines(yaml_path, warn = FALSE)), yaml_path)

cat("Creato", dst, "\n\n")
cat("Prossimi passi:\n")
cat("  1. modifica algorithm.yaml (nome, descrizione, parametri)\n")
if (backend == "python") {
  cat("  2. elenca le dipendenze in requirements.txt\n")
  cat("  3. scrivi generate() in adapter.py\n")
  cat("  4. Rscript tools/setup_env.R", id, "\n")
} else {
  cat("  2. elenca i pacchetti in r_packages e installali\n")
  cat("  3. scrivi generate() in generate.R\n")
}
cat("  5. Rscript tools/run_algorithm.R", id, "iris 200\n")
