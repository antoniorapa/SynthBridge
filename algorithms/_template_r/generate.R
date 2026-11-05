# Adapter R per SynthBridge.
#
# L'app chiama:  generate(data, n_rows, params, info)
#
#   data    data.frame con i dati reali (categoriche come factor, NA come NA)
#   n_rows  numero di righe sintetiche da produrre
#   params  lista con i parametri di algorithm.yaml, già col tipo giusto
#   info    lista con seed (già impostato con set.seed), categorical_columns,
#           numeric_columns, integer_columns, run_dir, progress(f, msg)
#
# Deve restituire un data.frame con n_rows righe e le stesse colonne di data.
# Prova da console:  Rscript tools/run_algorithm.R <id> iris 200

generate <- function(data, n_rows, params, info) {
  info$progress(0.1, "addestramento")

  # model <- pacchetto::fit(data, iterations = params$iterations)
  # synthetic <- pacchetto::sample(model, n_rows)

  # Segnaposto: ricampiona le righe reali. SOSTITUIRE con l'algoritmo vero!
  synthetic <- data[sample.int(nrow(data), n_rows, replace = TRUE), , drop = FALSE]

  info$progress(1, "fatto")
  synthetic
}
