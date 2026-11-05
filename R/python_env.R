# Gestione degli ambienti virtuali Python.
#
# Ogni algoritmo Python gira nel SUO ambiente virtuale (envs/<python_env>),
# creato da requirements.txt. Così CTGAN, TabDDPM, GReaT... possono richiedere
# versioni diverse e incompatibili di torch/pandas senza pestarsi i piedi.
# Più algoritmi possono condividere un ambiente dichiarando lo stesso
# `python_env` nel loro algorithm.yaml (es. tutti quelli basati su SDV).

find_base_python <- function(cfg) {
  base <- cfg$python$base_interpreter %||% "auto"
  if (!identical(base, "auto")) {
    if (!file.exists(base)) stop(tr("base_interp_missing", default_lang(), base))
    return(normalizePath(base, winslash = "/"))
  }
  for (cand in c("python3", "python", "py")) {
    p <- Sys.which(cand)
    if (nzchar(p)) {
      # Su Windows "python" può essere il finto alias del Microsoft Store: lo scartiamo.
      ok <- tryCatch(
        processx::run(p, c("--version"), error_on_status = FALSE, timeout = 10)$status == 0,
        error = function(e) FALSE
      )
      if (ok) return(unname(p))
    }
  }
  stop(tr("no_python", default_lang()))
}

find_uv <- function(cfg) {
  mode <- cfg$python$use_uv %||% "auto"
  if (identical(mode, "no") || isFALSE(mode)) return("")
  unname(Sys.which("uv"))
}

python_env_dir <- function(spec, cfg) file.path(cfg$python$envs_dir, spec$python_env)

python_env_interpreter <- function(spec, cfg) {
  d <- python_env_dir(spec, cfg)
  if (is_windows()) file.path(d, "Scripts", "python.exe") else file.path(d, "bin", "python")
}

# File che segna un ambiente installato fino in fondo. ".sdg_ready" è il nome
# usato prima del cambio di nome in SynthBridge: gli ambienti già creati restano validi.
READY_MARKER <- ".synthbridge_ready"
LEGACY_READY_MARKERS <- ".sdg_ready"

python_env_exists <- function(spec, cfg) {
  d <- python_env_dir(spec, cfg)
  file.exists(python_env_interpreter(spec, cfg)) &&
    any(file.exists(file.path(d, c(READY_MARKER, LEGACY_READY_MARKERS))))
}

# Crea (o ricrea) l'ambiente e installa requirements.txt.
# Funzione sincrona: dall'interfaccia viene lanciata in un processo separato
# (tools/setup_env.R), da console si può chiamare direttamente.
setup_python_env <- function(spec, cfg, force = FALSE, echo = TRUE) {
  env_dir <- python_env_dir(spec, cfg)
  req <- file.path(spec$path, "requirements.txt")
  marker <- file.path(env_dir, READY_MARKER)

  if (force && dir.exists(env_dir)) unlink(env_dir, recursive = TRUE)
  dir.create(cfg$python$envs_dir, showWarnings = FALSE, recursive = TRUE)

  uv <- find_uv(cfg)
  run <- function(cmd, args) {
    if (echo) cat("\n$", cmd, paste(args, collapse = " "), "\n")
    res <- processx::run(cmd, args, echo = echo, error_on_status = FALSE, stderr_to_stdout = TRUE)
    if (res$status != 0) stop(tr("cmd_failed", default_lang(), res$status, paste(cmd, paste(args, collapse = " "))))
    invisible(res)
  }

  py_version <- spec$python_version   # facoltativo, es. "3.11" (rispettato solo con uv)
  if (!file.exists(python_env_interpreter(spec, cfg))) {
    if (nzchar(uv)) {
      args <- c("venv", env_dir)
      if (!is.null(py_version)) args <- c(args, "--python", as.character(py_version))
      run(uv, args)
    } else {
      base <- find_base_python(cfg)
      args <- c("-m", "venv", env_dir)
      if (basename(base) %in% c("py", "py.exe") && !is.null(py_version)) {
        args <- c(paste0("-", py_version), args)
      }
      run(base, args)
    }
  }

  py <- python_env_interpreter(spec, cfg)
  if (nzchar(uv)) {
    run(uv, c("pip", "install", "--python", py, "pandas", "numpy"))
    if (file.size(req) > 0) run(uv, c("pip", "install", "--python", py, "-r", req))
  } else {
    run(py, c("-m", "pip", "install", "--upgrade", "pip"))
    run(py, c("-m", "pip", "install", "pandas", "numpy"))
    if (file.size(req) > 0) run(py, c("-m", "pip", "install", "-r", req))
  }

  writeLines(format(Sys.time()), marker)
  if (echo) cat("\n", tr("env_ready_at", default_lang(), env_dir), "\n", sep = "")
  invisible(py)
}

# Avvia la preparazione dell'ambiente in background (usato dall'interfaccia).
start_env_setup <- function(spec, cfg, force = FALSE, lang = default_lang()) {
  dir.create(cfg$python$envs_dir, showWarnings = FALSE, recursive = TRUE)
  log <- file.path(cfg$python$envs_dir, paste0(spec$python_env, ".setup.log"))
  args <- c(project_path("tools", "setup_env.R"), spec$id)
  if (force) args <- c(args, "--force")
  proc <- processx::process$new(
    rscript_path(), args,
    wd = project_root(), stdout = log, stderr = "2>&1", cleanup = TRUE,
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep), SYNTHBRIDGE_LANG = lang)
  )
  list(process = proc, log = log, algorithm = spec$id, started = Sys.time())
}
