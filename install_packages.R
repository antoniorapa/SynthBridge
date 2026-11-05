# Installa i pacchetti R necessari all'app. Da eseguire una volta:
#   source("install_packages.R")

needed <- c("shiny", "bslib", "DT", "yaml", "jsonlite", "processx", "commonmark")
optional <- c("synthpop")   # usato dall'algoritmo di esempio synthpop_cart

missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing)

ans <- if (interactive()) readline("Installare anche i pacchetti degli algoritmi di esempio (synthpop)? [s/N] ") else "n"
if (tolower(ans) %in% c("s", "si", "sì", "y", "yes")) install.packages(optional)

cat("Fatto. Ora: shiny::runApp()\n")
