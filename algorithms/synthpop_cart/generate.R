# Adapter per synthpop::syn().
# Esempio di algoritmo "nello stato dell'arte" già disponibile in R.

generate <- function(data, n_rows, params, info) {
  visit <- seq_along(data)
  if (isTRUE(params$visit_reversed)) visit <- rev(visit)

  # synthpop non gestisce bene le colonne logiche: le trattiamo come fattori
  logical_cols <- names(data)[vapply(data, is.logical, logical(1))]
  for (n in logical_cols) data[[n]] <- factor(data[[n]])

  args <- list(
    data,
    method = params$method,
    k = n_rows,
    visit.sequence = visit,
    seed = info$seed %||% "sample",
    print.flag = TRUE
  )
  # i parametri specifici di un metodo si passano come <metodo>.<parametro>
  if (params$method %in% c("cart", "ctree")) {
    args[[paste0(params$method, ".minbucket")]] <- params$minbucket
  }

  info$progress(0.1, "addestramento modelli")
  fit <- do.call(synthpop::syn, args)
  info$progress(1, "fatto")

  out <- fit$syn
  for (n in logical_cols) out[[n]] <- as.logical(as.character(out[[n]]))
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a
