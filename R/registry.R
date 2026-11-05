# Registro degli algoritmi.
#
# Ogni sottocartella di algorithms/ con un file algorithm.yaml è un algoritmo.
# Le cartelle che iniziano con "_" (es. _template_python) vengono ignorate.
#
# Gli errori di validazione sono conservati come i18n_msg (vedi R/i18n.R) e
# tradotti solo quando vengono mostrati: format_msgs(reg$errors[[id]], lang).

PARAM_TYPES <- c("integer", "numeric", "logical", "choice", "string", "integer_list")
BACKENDS <- c("python", "r")

load_algorithms <- function(dir = project_path("algorithms")) {
  dirs <- list.dirs(dir, recursive = FALSE, full.names = TRUE)
  dirs <- dirs[!startsWith(basename(dirs), "_")]
  algorithms <- list()
  errors <- list()
  for (d in sort(dirs)) {
    res <- tryCatch(read_algorithm(d),
      algorithm_invalid = function(e) e,
      error = function(e) structure(list(problems = list(i18n_msg("v_unexpected", conditionMessage(e)))),
                                    class = "algorithm_invalid")
    )
    if (inherits(res, "algorithm_invalid")) {
      errors[[basename(d)]] <- res$problems
    } else if (!is.null(algorithms[[res$id]])) {
      errors[[basename(d)]] <- list(i18n_msg("v_dup_id", res$id))
    } else {
      algorithms[[res$id]] <- res
    }
  }
  list(algorithms = algorithms, errors = errors)
}

algorithm_invalid <- function(problems) {
  structure(class = c("algorithm_invalid", "error", "condition"),
            list(message = format_msgs(problems), call = NULL, problems = problems))
}

read_algorithm <- function(path) {
  f <- file.path(path, "algorithm.yaml")
  if (!file.exists(f)) stop(algorithm_invalid(list(i18n_msg("v_no_yaml"))))
  spec <- tryCatch(yaml::read_yaml(f), error = function(e) {
    stop(algorithm_invalid(list(i18n_msg("v_bad_yaml", conditionMessage(e)))))
  })
  spec$path <- normalizePath(path, winslash = "/")
  spec$id <- spec$id %||% basename(path)
  spec$backend <- tolower(spec$backend %||% "")
  spec$entry <- spec$entry %||% if (spec$backend == "r") "generate.R" else "adapter.py"
  spec$`function` <- spec$`function` %||% "generate"
  spec$python_env <- spec$python_env %||% spec$id
  spec$params <- spec$params %||% list()
  spec$description <- spec$description %||% ""
  problems <- validate_algorithm(spec)
  if (length(problems)) stop(algorithm_invalid(problems))
  spec
}

# Testo semplice oppure mappa per lingua con valori testuali: {it: "...", en: "..."}.
is_text_field <- function(x) {
  if (is_localized(x)) return(length(x) > 0 && all(vapply(x, function(v) is.character(v) && length(v) == 1, logical(1))))
  is.character(x) && length(x) == 1
}

# Restituisce una lista di i18n_msg (vuota = tutto ok).
validate_algorithm <- function(spec) {
  p <- list()
  add <- function(key, ...) p[[length(p) + 1]] <<- i18n_msg(key, ...)

  if (is.null(spec$name) || !is_text_field(spec$name) || !nzchar(loc(spec$name, "it"))) add("v_no_name")
  if (!is_text_field(spec$description)) add("v_text_field", "description")
  if (!spec$backend %in% BACKENDS) add("v_backend", paste(BACKENDS, collapse = ", "))
  if (!file.exists(file.path(spec$path, spec$entry))) add("v_entry", spec$entry)
  if (spec$backend == "python" && !file.exists(file.path(spec$path, "requirements.txt"))) add("v_requirements")

  seen <- character()
  for (i in seq_along(spec$params)) {
    pr <- spec$params[[i]]
    if (is.null(pr$name)) { add("v_param_no_name", i18n_msg("v_param_index", i)); next }
    where <- i18n_msg("v_param_where", pr$name)
    if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", pr$name)) add("v_param_ident", where)
    if (pr$name %in% seen) add("v_param_dup", where)
    seen <- c(seen, pr$name)
    for (field in c("label", "help")) {
      if (!is.null(pr[[field]]) && !is_text_field(pr[[field]])) add("v_text_field", paste0(pr$name, ".", field))
    }
    if (!isTRUE(pr$type %in% PARAM_TYPES)) {
      add("v_param_type", where, paste(PARAM_TYPES, collapse = ", "))
      next
    }
    if (is.null(pr$default)) add("v_param_default", where)
    if (pr$type == "choice") {
      if (length(pr$choices) == 0) add("v_choice_empty", where)
      else if (!is.null(pr$default) && !as.character(pr$default) %in% as.character(unlist(pr$choices))) {
        add("v_choice_default", where)
      }
    }
    if (pr$type %in% c("integer", "numeric") && !is.null(pr$default)) {
      if (!is.numeric(pr$default)) add("v_default_num", where)
      else {
        if (!is.null(pr$min) && pr$default < pr$min) add("v_default_min", where)
        if (!is.null(pr$max) && pr$default > pr$max) add("v_default_max", where)
      }
    }
  }
  p
}

# Pacchetti R richiesti da un algoritmo con backend R e non installati.
missing_r_packages <- function(spec) {
  pk <- unlist(spec$r_packages %||% character())
  pk[!vapply(pk, requireNamespace, logical(1), quietly = TRUE)]
}

# Stato "pronto all'uso" di un algoritmo, per l'interfaccia.
algorithm_ready <- function(spec, cfg, lang = default_lang()) {
  if (spec$backend == "r") {
    miss <- missing_r_packages(spec)
    if (length(miss)) {
      return(list(ok = FALSE, msg = tr("r_missing_pkgs", lang,
        paste(miss, collapse = ", "), paste0('"', miss, '"', collapse = ", "))))
    }
    return(list(ok = TRUE, msg = tr("r_ready", lang)))
  }
  if (python_env_exists(spec, cfg)) {
    list(ok = TRUE, msg = tr("py_ready", lang, spec$python_env))
  } else {
    list(ok = FALSE, msg = tr("py_missing", lang, spec$python_env))
  }
}
