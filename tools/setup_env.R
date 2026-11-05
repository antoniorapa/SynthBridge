# Crea l'ambiente Python di un algoritmo (o di tutti) e installa requirements.txt.
#
#   Rscript tools/setup_env.R sdv_ctgan            # uno
#   Rscript tools/setup_env.R sdv_ctgan --force    # ricrea da zero
#   Rscript tools/setup_env.R --all                # tutti gli algoritmi Python
#
# Lo stesso script viene lanciato dal pulsante "Prepara ambiente" dell'interfaccia.

local({ f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
        source(file.path(if (length(f)) dirname(gsub("~+~", " ", sub("^--file=", "", f[1]), fixed = TRUE)) else "tools", "_load.R")) })

a <- cli_args()
force <- "--force" %in% a
cfg <- load_config()

specs <- if ("--all" %in% a) {
  Filter(function(s) s$backend == "python", load_algorithms()$algorithms)
} else {
  ids <- setdiff(a, c("--force", "--all"))
  if (!length(ids)) stop("Uso: Rscript tools/setup_env.R <id> [--force]  oppure  --all", call. = FALSE)
  lapply(ids, find_algorithm)
}

# un ambiente condiviso va preparato una volta sola
done <- character()
for (s in specs) {
  if (s$backend != "python") { cat(tr("setup_r_nothing", default_lang(), s$id), "\n"); next }
  if (s$python_env %in% done) next
  cat("\n", tr("setup_header", default_lang(), s$id, s$python_env), "\n", sep = "")
  setup_python_env(s, cfg, force = force)
  done <- c(done, s$python_env)
}
