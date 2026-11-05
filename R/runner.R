# Esecuzione degli algoritmi.
#
# Ogni esecuzione ("run") ha una cartella runs/<timestamp>_<algoritmo>/ con:
#   input.csv, job.json            -> scritti qui
#   synthetic.csv, status.json     -> scritti dal bridge (Python o R)
#   progress.json (facoltativo), log.txt
# L'algoritmo gira sempre in un processo separato: l'interfaccia resta reattiva,
# un crash dell'algoritmo non fa cadere l'app e il run si può interrompere.

new_run_dir <- function(spec, cfg) {
  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  base <- file.path(cfg$runs_dir, paste0(stamp, "_", spec$id))
  d <- base
  i <- 1
  while (dir.exists(d)) { d <- paste0(base, "-", i); i <- i + 1 }
  dir.create(d, recursive = TRUE)
  normalizePath(d, winslash = "/")
}

# Avvia un run e restituisce un oggetto "job" da passare a poll_job().
start_job <- function(spec, data, params, n_rows, seed, cfg, dataset_name = "", lang = default_lang()) {
  run_dir <- new_run_dir(spec, cfg)
  data <- normalize_data(data)
  utils::write.csv(data, file.path(run_dir, "input.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  # una lista vuota diventerebbe [] in JSON; serve {} (un dict in Python)
  if (length(params) == 0) params <- structure(list(), names = character())

  job <- list(
    algorithm = spec$id,
    algorithm_name = spec$name,       # testo o mappa per lingua, come in algorithm.yaml
    dataset = dataset_name,
    entry = spec$entry,
    `function` = spec$`function`,
    n_rows = as.integer(n_rows),
    seed = if (is.na(seed %||% NA)) NULL else as.integer(seed),
    params = params,
    schema = data_schema(data),
    created = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
  write_json_file(job, file.path(run_dir, "job.json"))

  if (spec$backend == "python") {
    if (!python_env_exists(spec, cfg)) stop(tr("py_env_not_ready", lang, spec$id))
    cmd <- python_env_interpreter(spec, cfg)
    args <- c("-u", project_path("bridge", "synthbridge.py"),
              "--algorithm-dir", spec$path, "--run-dir", run_dir)
    env <- c(PYTHONIOENCODING = "utf-8", PYTHONUNBUFFERED = "1")
  } else {
    cmd <- rscript_path()
    args <- c(project_path("bridge", "synthbridge.R"), spec$path, run_dir)
    # stesse librerie dell'app (renv, .libPaths() personalizzati): algorithm_ready()
    # controlla i pacchetti in questo processo, il bridge deve vederli uguali
    env <- c(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  }

  proc <- processx::process$new(
    cmd, args,
    wd = run_dir,
    stdout = file.path(run_dir, "log.txt"), stderr = "2>&1",
    env = c("current", env, SYNTHBRIDGE_LANG = lang),   # lingua dei messaggi del bridge
    cleanup = TRUE, cleanup_tree = TRUE   # chiudendo l'app si chiude anche l'algoritmo
  )
  list(process = proc, run_dir = run_dir, spec = spec, started = Sys.time(), real = data)
}

# Stato attuale del job: "running", "done", "failed", "timeout".
poll_job <- function(job, cfg, lang = default_lang()) {
  log <- tail_file(file.path(job$run_dir, "log.txt"))
  progress <- read_json_safely(file.path(job$run_dir, "progress.json"))
  elapsed <- as.numeric(difftime(Sys.time(), job$started, units = "secs"))

  if (job$process$is_alive()) {
    limit <- (cfg$timeout_minutes %||% 60) * 60
    if (elapsed > limit) {
      job$process$kill_tree()
      return(list(state = "timeout", log = log, elapsed = elapsed,
                  error = tr("timeout", lang, format(limit / 60))))
    }
    return(list(state = "running", log = log, elapsed = elapsed, progress = progress))
  }

  status <- read_json_safely(file.path(job$run_dir, "status.json"))
  synth_path <- file.path(job$run_dir, "synthetic.csv")
  if (isTRUE(status$ok) && file.exists(synth_path)) {
    synth <- utils::read.csv(synth_path, stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA"),
                             fileEncoding = "UTF-8")
    synth <- coerce_like(synth, job$real)
    return(list(state = "done", log = log, elapsed = elapsed, synthetic = synth))
  }
  err <- status$error %||% tr("no_result", lang, format(job$process$get_exit_status()))
  list(state = "failed", log = log, elapsed = elapsed, error = err)
}

cancel_job <- function(job, lang = default_lang()) {
  if (!is.null(job$process) && job$process$is_alive()) job$process$kill_tree()
  write_json_file(list(ok = FALSE, error = tr("cancelled_by_user", lang)), file.path(job$run_dir, "status.json"))
}

# Versione sincrona, usata da tools/run_algorithm.R e dai test degli studenti.
run_algorithm_sync <- function(spec, data, params = NULL, n_rows = nrow(data), seed = 42,
                               cfg = load_config(), echo = TRUE) {
  params <- params %||% default_params(spec)
  job <- start_job(spec, data, params, n_rows, seed, cfg, dataset_name = "console")
  if (echo) cat("Run:", job$run_dir, "\n")
  printed <- 0
  repeat {
    Sys.sleep(0.5)
    st <- poll_job(job, cfg)
    if (echo && file.exists(file.path(job$run_dir, "log.txt"))) {
      lines <- readLines(file.path(job$run_dir, "log.txt"), warn = FALSE)
      if (length(lines) > printed) { cat(lines[(printed + 1):length(lines)], sep = "\n"); printed <- length(lines) }
    }
    if (st$state != "running") break
  }
  if (st$state != "done") stop(st$error, call. = FALSE)
  st$synthetic
}

# Ricarica un run passato (dati reali con i tipi originali + sintetici).
load_run <- function(run_dir) {
  job <- read_json_safely(file.path(run_dir, "job.json"))
  real <- utils::read.csv(file.path(run_dir, "input.csv"), stringsAsFactors = FALSE, check.names = FALSE,
                          fileEncoding = "UTF-8")
  if (!is.null(job$schema)) {
    for (i in seq_len(nrow(job$schema))) {
      n <- job$schema$name[i]
      real[[n]] <- switch(job$schema$type[i],
        categorical = factor(real[[n]]), integer = as.integer(real[[n]]),
        numeric = as.numeric(real[[n]]), logical = as.logical(real[[n]]), real[[n]])
    }
  }
  synth <- utils::read.csv(file.path(run_dir, "synthetic.csv"), stringsAsFactors = FALSE, check.names = FALSE, na.strings = c("", "NA"),
                           fileEncoding = "UTF-8")
  list(real = real, synthetic = coerce_like(synth, real), run_dir = run_dir, job = job)
}

# Elenco dei run passati, per la scheda "Storico".
list_runs <- function(cfg, lang = default_lang()) {
  dirs <- list.dirs(cfg$runs_dir, recursive = FALSE)
  if (!length(dirs)) return(data.frame())
  rows <- lapply(rev(sort(dirs)), function(d) {
    job <- read_json_safely(file.path(d, "job.json"))
    st <- read_json_safely(file.path(d, "status.json"))
    if (is.null(job)) return(NULL)
    outcome <- if (is.null(st)) "outcome_running" else if (isTRUE(st$ok)) "outcome_ok" else "outcome_error"
    row <- data.frame(
      run = basename(d),
      when = job$created %||% "",
      algorithm = loc(job$algorithm_name %||% job$algorithm, lang) %||% "",
      dataset = job$dataset %||% "",
      rows = job$n_rows %||% NA,
      outcome = tr(outcome, lang),
      seconds = st$elapsed %||% NA,
      params = as.character(jsonlite::toJSON(job$params, auto_unbox = TRUE)),
      stringsAsFactors = FALSE
    )
    # la colonna "run" resta con lo stesso nome: l'app la usa per aprire il run
    names(row) <- c("run", tr("col_when", lang), tr("col_algorithm", lang), tr("col_dataset", lang),
                    tr("col_rows", lang), tr("col_outcome", lang), tr("col_seconds", lang), tr("col_params", lang))
    row
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) data.frame() else out   # nessuna cartella con job.json
}
