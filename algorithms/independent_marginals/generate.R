# Baseline: ogni colonna campionata in modo indipendente.

generate <- function(data, n_rows, params, info) {
  out <- lapply(names(data), function(col) {
    x <- data[[col]]
    pool <- if (isTRUE(params$keep_na)) x else x[!is.na(x)]
    if (!length(pool)) pool <- x   # colonna tutta NA: restano NA
    y <- pool[sample.int(length(pool), n_rows, replace = TRUE)]

    if (is.numeric(x) && params$jitter > 0) {
      s <- stats::sd(x, na.rm = TRUE)
      if (is.finite(s) && s > 0) y <- y + stats::rnorm(n_rows, 0, params$jitter * s)
      if (col %in% info$integer_columns) y <- round(y)
    }
    y
  })
  names(out) <- names(data)
  info$progress(1, "fatto")
  as.data.frame(out, check.names = FALSE)
}
