# Controlla tutti gli algoritmi (o uno solo) e dice cosa non va.
#
#   Rscript tools/check_algorithms.R            # tutti
#   Rscript tools/check_algorithms.R sdv_ctgan  # uno solo

local({ f <- grep("^--file=", commandArgs(FALSE), value = TRUE)
        source(file.path(if (length(f)) dirname(gsub("~+~", " ", sub("^--file=", "", f[1]), fixed = TRUE)) else "tools", "_load.R")) })

cfg <- load_config()
reg <- load_algorithms()
only <- cli_args()

ids <- union(names(reg$algorithms), names(reg$errors))
if (length(only)) ids <- intersect(ids, only)
if (!length(ids)) stop("Nessun algoritmo da controllare.", call. = FALSE)

n_bad <- 0
for (id in sort(ids)) {
  if (!is.null(reg$errors[[id]])) {
    n_bad <- n_bad + 1
    cat(sprintf("[ERRORE] %s\n", id))
    cat(paste0("         - ", vapply(reg$errors[[id]], format_msg, character(1)), collapse = "\n"), "\n")
    next
  }
  s <- reg$algorithms[[id]]
  r <- algorithm_ready(s, cfg)
  cat(sprintf("[%s] %-24s %-7s %d parametri   %s\n",
              if (r$ok) "  OK  " else "DA FARE", id, s$backend, length(s$params),
              if (r$ok) "" else r$msg))
}
cat(sprintf("\n%d algoritmi, %d con errori.\n", length(ids), n_bad))
if (n_bad) quit(status = 1, save = "no")
