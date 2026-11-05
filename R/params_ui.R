# Traduce la sezione `params:` di algorithm.yaml in controlli Shiny e,
# al momento dell'esecuzione, rilegge i valori con il tipo giusto.
#
# Tipi supportati:
#   integer       -> numericInput a passo 1           (min, max, step)
#   numeric       -> numericInput                     (min, max, step)
#   logical       -> checkbox
#   choice        -> menu a tendina                   (choices)
#   string        -> casella di testo
#   integer_list  -> testo "256, 256" -> c(256, 256)  (es. dimensioni dei layer)
#
# Campi comuni: label, help, advanced (true = finisce in "Parametri avanzati").
# label e help possono essere un testo o una mappa per lingua: {it: "...", en: "..."}.
# Le etichette contengono tutte le lingue (vedi R/i18n.R): cambiare lingua non
# ridisegna il form, quindi i valori inseriti non si perdono.

param_input_id <- function(spec, p) paste0("param__", spec$id, "__", p$name)

param_input <- function(spec, p) {
  id <- param_input_id(spec, p)
  label <- loc_ui(p$label %||% p$name)
  ctrl <- switch(p$type,
    integer = numericInput(id, label, value = p$default, min = p$min %||% NA, max = p$max %||% NA, step = p$step %||% 1),
    numeric = numericInput(id, label, value = p$default, min = p$min %||% NA, max = p$max %||% NA, step = p$step %||% NA),
    logical = checkboxInput(id, label, value = isTRUE(p$default)),
    choice  = selectInput(id, label, choices = unlist(p$choices), selected = p$default),
    string  = textInput(id, label, value = as.character(p$default)),
    integer_list = textInput(id, label, value = paste(unlist(p$default), collapse = ", "))
  )
  if (!is.null(p$help)) {
    ctrl <- tagList(ctrl, tags$div(class = "form-text param-help", loc_ui(p$help)))
  }
  tags$div(class = "param-block", ctrl)
}

params_panel <- function(spec) {
  if (!length(spec$params)) return(tags$p(class = "text-muted", tr_ui("no_params")))
  adv <- vapply(spec$params, function(p) isTRUE(p$advanced), logical(1))
  basic <- lapply(spec$params[!adv], function(p) param_input(spec, p))
  advanced <- lapply(spec$params[adv], function(p) param_input(spec, p))
  tagList(
    basic,
    if (length(advanced)) tags$details(
      class = "advanced-params",
      tags$summary(tr_ui("advanced_params", length(advanced))),
      advanced
    )
  )
}

# Legge i valori dall'interfaccia. Restituisce list(values = ..., errors = ...).
collect_params <- function(spec, input, lang = default_lang()) {
  values <- list()
  errors <- character()
  for (p in spec$params) {
    raw <- input[[param_input_id(spec, p)]]
    label <- loc(p$label %||% p$name, lang)
    v <- tryCatch(switch(p$type,
      integer = {
        if (is.null(raw) || is.na(raw)) stop(tr("err_missing_value", lang))
        if (raw != round(raw)) stop(tr("err_not_integer", lang))
        as.integer(raw)
      },
      numeric = {
        if (is.null(raw) || is.na(raw)) stop(tr("err_missing_value", lang))
        as.numeric(raw)
      },
      logical = isTRUE(raw),
      choice  = {
        # se le choices sono numeri, restituisci un numero
        if (is.numeric(unlist(p$choices))) as.numeric(raw) else as.character(raw)
      },
      string  = as.character(raw %||% ""),
      integer_list = {
        parts <- trimws(strsplit(raw %||% "", ",")[[1]])
        parts <- parts[nzchar(parts)]
        nums <- suppressWarnings(as.integer(parts))
        if (!length(nums) || anyNA(nums)) stop(tr("err_int_list", lang))
        as.list(nums)   # lista => resta un array JSON anche con un solo elemento
      }
    ), error = function(e) { errors <<- c(errors, sprintf("%s: %s", label, conditionMessage(e))); NULL })

    if (is.numeric(v) && length(v) == 1) {
      if (!is.null(p$min) && v < p$min) errors <- c(errors, sprintf("%s: %s", label, tr("err_min", lang, p$min)))
      if (!is.null(p$max) && v > p$max) errors <- c(errors, sprintf("%s: %s", label, tr("err_max", lang, p$max)))
    }
    if (!is.null(v)) values[[p$name]] <- v
  }
  list(values = values, errors = errors)
}

# Valori di default (per l'uso da console, senza interfaccia).
default_params <- function(spec) {
  out <- list()
  for (p in spec$params) {
    out[[p$name]] <- switch(p$type,
      integer = as.integer(p$default),
      integer_list = as.list(as.integer(unlist(p$default))),
      p$default
    )
  }
  out
}
