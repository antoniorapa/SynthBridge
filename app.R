# SynthBridge - laboratorio per la generazione di dati sintetici (R + Python).
#
# Avvio:  shiny::runApp()   (dalla cartella del progetto, o da RStudio con "Run App")
#
# Struttura:
#   app.R              interfaccia (questo file)
#   R/                 logica: registro algoritmi, form parametri, esecuzione, valutazione, traduzioni
#   bridge/            ponti verso gli algoritmi (Python e R) - non toccare
#   algorithms/<id>/   UN ALGORITMO PER CARTELLA  <- qui lavorano gli studenti
#   tools/             script da console: nuovo algoritmo, controllo, test, ambienti
#
# Lingua: pulsanti IT / EN nella barra in alto; default in config.yaml (language).
# I testi stanno in R/i18n.R.

library(shiny)
library(bslib)

options(synthbridge.root = normalizePath(getwd(), winslash = "/"))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f, local = TRUE, encoding = "UTF-8")

cfg <- load_config()
options(shiny.maxRequestSize = (cfg$max_upload_mb %||% 200) * 1024^2)
dir.create(cfg$runs_dir, showWarnings = FALSE, recursive = TRUE)

example_datasets <- list(
  iris = list(dims = "150 x 5", kind = "ds_mixed", load = function() iris),
  mtcars = list(dims = "32 x 11", kind = "ds_numeric", load = function() {
    d <- mtcars
    for (n in c("cyl", "vs", "am", "gear", "carb")) d[[n]] <- as.integer(d[[n]])
    d
  }),
  airquality = list(dims = "153 x 6", kind = "ds_with_na", load = function() airquality),
  ToothGrowth = list(dims = "60 x 3", kind = "ds_mixed", load = function() ToothGrowth),
  esoph = list(dims = "88 x 5", kind = "ds_categorical", load = function() {
    d <- esoph
    for (n in c("agegp", "alcgp", "tobgp")) d[[n]] <- factor(as.character(d[[n]]))
    d
  })
)

# Le voci dei menu a tendina non possono contenere HTML: si traducono dal server.
example_choices <- function(lang) {
  setNames(names(example_datasets), vapply(names(example_datasets), function(n) {
    sprintf("%s (%s, %s)", n, example_datasets[[n]]$dims, tr(example_datasets[[n]]$kind, lang))
  }, character(1)))
}
csv_sep_choices <- function(lang) {
  setNames(c(",", ";", "\t"), c(tr("sep_comma", lang), tr("sep_semicolon", lang), tr("sep_tab", lang)))
}
csv_dec_choices <- function(lang) setNames(c(".", ","), c(tr("dec_point", lang), tr("dec_comma", lang)))
algorithm_choices <- function(algs, lang) {
  setNames(as.character(names(algs)), vapply(algs, function(a) loc(a$name, lang), character(1)))
}

L0 <- cfg$language   # lingua iniziale dei controlli che non accettano HTML

# ---------------------------------------------------------------- interfaccia

ui <- page_navbar(
  id = "main",
  title = "SynthBridge",
  window_title = "SynthBridge",
  theme = bs_theme(version = 5, preset = "flatly"),
  # Solo "Genera" si adatta all'altezza della finestra (sidebar fissa). Nelle altre
  # schede il contenuto è più alto dello schermo: se fossero "fillable", bslib
  # schiaccerebbe l'ultima card (es. "Dettaglio per colonna") fino a renderla invisibile.
  fillable = "generate",
  header = tagList(
    i18n_head(cfg$language),
    tags$head(tags$style(HTML("
      .param-help { margin-top: -0.6rem; margin-bottom: 0.6rem; }
      .advanced-params summary { cursor: pointer; font-weight: 500; margin: 0.5rem 0; }
      pre.sb-log { max-height: 320px; overflow-y: auto; font-size: 0.78rem; background: var(--bs-light); }
      .alg-desc { font-size: 0.9rem; }
      .sb-lang .btn { color: rgba(255,255,255,.75); border-color: rgba(255,255,255,.45); padding: .1rem .5rem; }
      .sb-lang .btn:hover { color: #fff; border-color: #fff; }
      .sb-lang .btn.active { color: var(--bs-primary); background: #fff; border-color: #fff; }
    ")))
  ),

  nav_panel(tr_ui("nav_generate"), value = "generate", icon = icon("wand-magic-sparkles"),
    layout_sidebar(
      sidebar = sidebar(width = 380, open = "always",
        h6(tr_ui("step_data")),
        radioButtons("data_source", NULL, inline = TRUE,
                     choiceNames = list(tr_ui("src_example"), tr_ui("src_upload")),
                     choiceValues = c("example", "upload")),
        conditionalPanel("input.data_source == 'example'",
          selectInput("example", NULL, example_choices(L0))),
        conditionalPanel("input.data_source == 'upload'",
          i18n_placeholder(
            fileInput("csv", NULL, accept = ".csv", buttonLabel = tr_ui("browse"), placeholder = tr("no_file", L0)),
            "no_file"
          ),
          layout_columns(
            selectInput("csv_sep", tr_ui("csv_sep"), csv_sep_choices(L0)),
            selectInput("csv_dec", tr_ui("csv_dec"), csv_dec_choices(L0))
          )
        ),
        hr(),
        h6(tr_ui("step_algorithm")),
        selectInput("algorithm", NULL, choices = NULL),
        uiOutput("algorithm_info"),
        hr(),
        h6(tr_ui("step_params")),
        uiOutput("params_ui"),
        actionLink("reset_params", tr_ui("reset_params"), icon = icon("rotate-left")),
        hr(),
        layout_columns(
          numericInput("n_rows", tr_ui("n_rows"), value = NA, min = 1),
          numericInput("seed", tr_ui("seed"), value = 42)
        ),
        layout_columns(
          actionButton("run", tr_ui("run"), icon = icon("play"), class = "btn-primary"),
          actionButton("cancel", tr_ui("cancel"), icon = icon("stop"), class = "btn-outline-danger")
        )
      ),
      layout_columns(col_widths = c(6, 6),
        card(full_screen = TRUE,
          card_header(textOutput("real_title", inline = TRUE)),
          DT::DTOutput("real_preview")
        ),
        card(full_screen = TRUE,
          card_header(tr_ui("execution")),
          uiOutput("job_status"),
          verbatimTextOutput("job_log") |> tagAppendAttributes(class = "sb-log")
        )
      ),
      card(full_screen = TRUE,
        card_header(class = "d-flex justify-content-between align-items-center",
          textOutput("synth_title", inline = TRUE),
          downloadButton("download", tr_ui("download_csv"), class = "btn-sm btn-outline-primary")
        ),
        DT::DTOutput("synth_preview")
      )
    )
  ),

  nav_panel(tr_ui("nav_evaluate"), value = "evaluate", icon = icon("chart-column"),
    uiOutput("eval_empty"),
    conditionalPanel("output.has_result",
      layout_columns(col_widths = c(4, 4, 4),
        value_box(tr_ui("vb_dist_title"), textOutput("vb_dist"), p(tr_ui("vb_dist_help")), theme = "primary"),
        value_box(tr_ui("vb_cor_title"), textOutput("vb_cor"), p(tr_ui("vb_cor_help")), theme = "secondary"),
        value_box(tr_ui("vb_copy_title"), textOutput("vb_copy"), p(tr_ui("vb_copy_help")), theme = "warning")
      ),
      layout_columns(col_widths = c(6, 6),
        card(full_screen = TRUE,
          card_header(tr_ui("card_marginal")),
          selectInput("eval_col", NULL, choices = NULL),
          plotOutput("marginal_plot", height = 340)
        ),
        card(full_screen = TRUE,
          card_header(tr_ui("card_cor")),
          plotOutput("cor_plot", height = 400)
        )
      ),
      card(card_header(tr_ui("card_fidelity")), DT::DTOutput("fidelity_table"))
    )
  ),

  nav_panel(tr_ui("nav_algorithms"), value = "algorithms", icon = icon("puzzle-piece"),
    card(
      card_header(class = "d-flex justify-content-between align-items-center",
        tr_ui("alg_registered"),
        actionButton("reload", tr_ui("reload"), icon = icon("arrows-rotate"), class = "btn-sm")
      ),
      p(class = "text-muted", tr_ui("alg_help")),
      DT::DTOutput("algorithms_table")
    ),
    uiOutput("algorithm_errors")
  ),

  nav_panel(tr_ui("nav_history"), value = "history", icon = icon("clock-rotate-left"),
    card(
      card_header(class = "d-flex justify-content-between align-items-center",
        tr_ui("runs_title"),
        div(
          actionButton("refresh_runs", tr_ui("refresh"), icon = icon("arrows-rotate"), class = "btn-sm"),
          actionButton("load_run", tr_ui("open_in_eval"), icon = icon("folder-open"), class = "btn-sm btn-primary")
        )
      ),
      DT::DTOutput("runs_table"),
      verbatimTextOutput("run_detail") |> tagAppendAttributes(class = "sb-log")
    )
  ),

  nav_spacer(),
  nav_item(tags$small(class = "text-muted", tr_ui("tagline"))),
  nav_item(lang_switch())
)

# ------------------------------------------------------------------- server

server <- function(input, output, session) {

  # lingua scelta da chi usa l'app (arriva dal browser, vedi R/i18n.R)
  lang <- reactive(if (isTRUE(input$lang %in% LANGS)) input$lang else cfg$language)

  registry <- reactiveVal(load_algorithms())
  job <- reactiveVal(NULL)          # run in corso
  job_state <- reactiveVal(NULL)    # ultimo esito di poll_job()
  result <- reactiveVal(NULL)       # list(real, synthetic, run_dir, spec)
  setup_job <- reactiveVal(NULL)    # preparazione ambiente Python in corso
  params_version <- reactiveVal(0)  # per "ripristina default"
  runs_version <- reactiveVal(0)

  dt_options <- function(...) c(list(...), list(language = dt_language(lang())))

  # --- menu tradotti dal server ----------------------------------------------
  observe({
    l <- lang()
    updateSelectInput(session, "example", choices = example_choices(l), selected = isolate(input$example))
    updateSelectInput(session, "csv_sep", choices = csv_sep_choices(l), selected = isolate(input$csv_sep))
    updateSelectInput(session, "csv_dec", choices = csv_dec_choices(l), selected = isolate(input$csv_dec))
  })

  # --- algoritmi -----------------------------------------------------------
  observe({
    choices <- algorithm_choices(registry()$algorithms, lang())
    sel <- isolate(input$algorithm)
    updateSelectInput(session, "algorithm", choices = choices,
                      selected = if (isTRUE(sel %in% choices)) sel else NULL)
  })

  observeEvent(input$reload, {
    registry(load_algorithms())
    n_err <- length(registry()$errors)
    showNotification(
      paste0(tr("n_loaded", lang(), length(registry()$algorithms)),
             if (n_err) tr("n_with_errors", lang(), n_err) else ""),
      type = if (n_err) "warning" else "message"
    )
  })

  spec <- reactive({
    req(input$algorithm)
    # dopo "Ricarica" l'algoritmo selezionato potrebbe non esistere più
    req(registry()$algorithms[[input$algorithm]])
  })

  readiness <- reactive({
    setup_job()             # ricalcola quando finisce una preparazione
    algorithm_ready(spec(), cfg, lang())
  })

  output$algorithm_info <- renderUI({
    s <- spec(); r <- readiness(); l <- lang()
    tagList(
      div(class = "alg-desc mb-2",
        span(class = "badge text-bg-secondary me-1", toupper(s$backend)),
        if (!is.null(s$reference)) tags$a(href = s$reference, target = "_blank", tr("reference", l)),
        markdown(loc(s$description, l))
      ),
      if (r$ok) {
        div(class = "text-success small", icon("circle-check"), r$msg)
      } else {
        div(class = "small",
          div(class = "text-warning mb-1", icon("triangle-exclamation"), r$msg),
          if (s$backend == "python") actionButton("setup_env", tr("setup_env", l),
                                                  icon = icon("download"), class = "btn-sm btn-warning")
        )
      }
    )
  })

  # non dipende dalla lingua: le etichette contengono già tutte le lingue
  output$params_ui <- renderUI({
    params_version()
    params_panel(spec())
  })

  observeEvent(input$reset_params, params_version(params_version() + 1))

  # --- preparazione ambiente Python ------------------------------------------
  observeEvent(input$setup_env, {
    if (!is.null(setup_job())) return(showNotification(tr("setup_already", lang()), type = "warning"))
    sj <- tryCatch(start_env_setup(spec(), cfg, lang = lang()),
                   error = function(e) { showNotification(conditionMessage(e), type = "error"); NULL })
    req(sj)
    setup_job(sj)
    showNotification(tr("setup_started", lang()), duration = 8)
  })

  observe({
    sj <- setup_job(); req(sj)
    invalidateLater(1000)
    if (sj$process$is_alive()) {
      job_state(list(state = "setup", log = tail_file(sj$log, 60),
                     elapsed = as.numeric(difftime(Sys.time(), sj$started, units = "secs"))))
      return()
    }
    ok <- identical(sj$process$get_exit_status(), 0L)
    l <- isolate(lang())
    showNotification(
      if (ok) tr("setup_ok_notif", l) else tr("setup_fail_notif", l),
      type = if (ok) "message" else "error", duration = NULL
    )
    job_state(list(state = if (ok) "setup_done" else "setup_failed", log = tail_file(sj$log, 60)))
    setup_job(NULL)
  })

  # --- dati reali --------------------------------------------------------
  real_data <- reactive({
    if (input$data_source == "example") {
      req(input$example %in% names(example_datasets))
      list(name = input$example, data = example_datasets[[input$example]]$load())
    } else {
      req(input$csv)
      d <- tryCatch(
        utils::read.csv(input$csv$datapath, sep = input$csv_sep, dec = input$csv_dec,
                        stringsAsFactors = TRUE, check.names = FALSE, na.strings = c("", "NA")),
        error = function(e) {
          showNotification(tr("csv_unreadable", isolate(lang()), conditionMessage(e)), type = "error")
          NULL
        }
      )
      req(d)
      list(name = input$csv$name, data = normalize_data(d))
    }
  })

  observe({
    updateNumericInput(session, "n_rows", value = nrow(real_data()$data))
  })

  output$real_title <- renderText({
    d <- real_data()
    tr("real_title", lang(), d$name, nrow(d$data), ncol(d$data))
  })

  output$real_preview <- DT::renderDT(preview_table(real_data()$data))

  preview_table <- function(df) {
    DT::datatable(utils::head(df, cfg$preview_rows %||% 200), rownames = FALSE,
                  options = dt_options(pageLength = 8, scrollX = TRUE, dom = "tip"), class = "compact stripe")
  }

  # --- esecuzione ----------------------------------------------------------
  observeEvent(input$run, {
    l <- lang()
    if (!is.null(job())) return(showNotification(tr("job_busy", l), type = "warning"))
    s <- spec()
    r <- readiness()
    if (!r$ok) return(showNotification(r$msg, type = "error", duration = 10))
    p <- collect_params(s, input, l)
    if (length(p$errors)) {
      return(showNotification(
        HTML(paste(c(paste0("<b>", tr("invalid_params", l), "</b>"), htmltools::htmlEscape(p$errors)), collapse = "<br>")),
        type = "error", duration = 10))
    }
    n <- input$n_rows
    if (is.null(n) || is.na(n) || n < 1) return(showNotification(tr("invalid_n_rows", l), type = "error"))
    d <- real_data()
    j <- tryCatch(start_job(s, d$data, p$values, n, input$seed, cfg, dataset_name = d$name, lang = l),
                  error = function(e) { showNotification(conditionMessage(e), type = "error"); NULL })
    req(j)
    job(j)
    job_state(list(state = "running", log = "", elapsed = 0))
  })

  observeEvent(input$cancel, {
    j <- job(); req(j)
    cancel_job(j, lang())
    job(NULL)
    job_state(list(state = "cancelled", log = tail_file(file.path(j$run_dir, "log.txt"))))
    runs_version(runs_version() + 1)
  })

  # polling del processo in background
  observe({
    j <- job(); req(j)
    invalidateLater(700)
    l <- isolate(lang())
    st <- poll_job(j, cfg, l)
    job_state(st)
    if (st$state != "running") {
      job(NULL)
      runs_version(isolate(runs_version()) + 1)   # isolate: non dipendere da runs_version
      if (st$state == "done") {
        result(list(real = j$real, synthetic = st$synthetic, run_dir = j$run_dir, spec = j$spec))
        showNotification(tr("done_notif", l, nrow(st$synthetic), st$elapsed), type = "message")
      } else {
        showNotification(st$error, type = "error", duration = NULL)
      }
    }
  })

  output$job_status <- renderUI({
    st <- job_state(); l <- lang()
    if (is.null(st)) return(p(class = "text-muted", tr("no_runs_yet", l)))
    switch(st$state,
      running = {
        pr <- st$progress
        tagList(
          p(icon("spinner", class = "fa-spin"), tr("running_for", l, st$elapsed),
            if (!is.null(pr$message)) span(class = "text-muted", " · ", pr$message)),
          if (!is.null(pr$fraction)) div(class = "progress mb-2",
            div(class = "progress-bar", style = sprintf("width:%.0f%%", 100 * pr$fraction)))
        )
      },
      setup = p(icon("spinner", class = "fa-spin"), tr("setup_running", l, st$elapsed)),
      setup_done = p(class = "text-success", icon("circle-check"), tr("setup_done", l)),
      setup_failed = p(class = "text-danger", icon("circle-xmark"), tr("setup_failed", l)),
      done = p(class = "text-success", icon("circle-check"), tr("completed_in", l, st$elapsed)),
      cancelled = p(class = "text-muted", icon("ban"), tr("cancelled", l)),
      p(class = "text-danger", icon("circle-xmark"), " ", st$error)
    )
  })

  output$job_log <- renderText(job_state()$log %||% "")

  output$synth_title <- renderText({
    r <- result(); l <- lang()
    if (is.null(r)) tr("synth_title", l) else
      tr("synth_title_full", l, loc(r$spec$name, l), nrow(r$synthetic), basename(r$run_dir))
  })

  output$synth_preview <- DT::renderDT({
    r <- result(); req(r)
    preview_table(r$synthetic)
  })

  output$download <- downloadHandler(
    filename = function() paste0(tr("download_prefix", lang()), basename(result()$run_dir %||% "data"), ".csv"),
    content = function(file) { req(result()); utils::write.csv(result()$synthetic, file, row.names = FALSE) }
  )

  # --- valutazione ---------------------------------------------------------
  output$has_result <- reactive(!is.null(result()))
  outputOptions(output, "has_result", suspendWhenHidden = FALSE)

  output$eval_empty <- renderUI({
    if (is.null(result())) div(class = "p-4 text-muted", tr("eval_empty", lang()))
  })

  metrics <- reactive({ r <- result(); req(r); overview_metrics(r$real, r$synthetic) })
  output$vb_dist <- renderText(sprintf("%.3f", metrics()$mean_distance))
  output$vb_cor <- renderText(if (is.na(metrics()$cor_diff)) tr("not_available", lang()) else sprintf("%.3f", metrics()$cor_diff))
  output$vb_copy <- renderText(sprintf("%.1f %%", 100 * metrics()$exact_copies))

  observe({
    r <- result(); req(r)
    updateSelectInput(session, "eval_col", choices = names(r$real))
  })

  output$marginal_plot <- renderPlot({
    r <- result(); req(r, input$eval_col %in% names(r$real))
    plot_marginal(r$real, r$synthetic, input$eval_col, lang())
  })

  output$cor_plot <- renderPlot({ r <- result(); req(r); plot_correlation_diff(r$real, r$synthetic, lang()) })

  output$fidelity_table <- DT::renderDT({
    r <- result(); req(r)
    DT::datatable(localize_fidelity(fidelity_table(r$real, r$synthetic), lang()), rownames = FALSE,
                  # niente paginazione: con dom = "t" non ci sono i controlli per sfogliare,
                  # e con più di 20 colonne le righe in eccesso sparivano senza avviso
                  options = dt_options(paging = FALSE, dom = "t", scrollX = TRUE), class = "compact stripe")
  })

  # --- scheda Algoritmi -------------------------------------------------------
  message_table <- function(key) {
    m <- data.frame(tr(key, lang())); names(m) <- tr("col_message", lang())
    DT::datatable(m, rownames = FALSE, options = dt_options(dom = "t"))
  }

  output$algorithms_table <- DT::renderDT({
    setup_job()
    algs <- registry()$algorithms; l <- lang()
    if (!length(algs)) return(message_table("no_valid_alg"))
    tab <- do.call(rbind, lapply(algs, function(a) {
      r <- algorithm_ready(a, cfg, l)
      data.frame(
        id = a$id, name = loc(a$name, l), backend = a$backend,
        env = if (a$backend == "python") a$python_env else "-",
        params = length(a$params),
        authors = paste(unlist(a$authors %||% "-"), collapse = ", "),
        ready = if (r$ok) tr("yes", l) else tr("no", l),
        stringsAsFactors = FALSE
      )
    }))
    names(tab) <- c("id", tr("col_name", l), "backend", tr("col_env", l), tr("col_params", l),
                    tr("col_authors", l), tr("col_ready", l))
    DT::datatable(tab, rownames = FALSE, options = dt_options(dom = "ft", pageLength = 100), class = "compact stripe")
  })

  output$algorithm_errors <- renderUI({
    errs <- registry()$errors; l <- lang()
    if (!length(errs)) return(NULL)
    card(class = "border-danger",
      card_header(class = "text-bg-danger", tr("errors_card", l, length(errs))),
      lapply(names(errs), function(n) tagList(tags$b(paste0("algorithms/", n)), tags$pre(format_msgs(errs[[n]], l))))
    )
  })

  # --- storico ----------------------------------------------------------------
  runs <- reactive({ runs_version(); input$refresh_runs; list_runs(cfg, lang()) })

  output$runs_table <- DT::renderDT({
    if (!nrow(runs())) return(message_table("no_runs_yet"))
    DT::datatable(runs(), rownames = FALSE, selection = "single",
                  options = dt_options(pageLength = 15, scrollX = TRUE, order = list()), class = "compact stripe")
  })

  selected_run <- reactive({
    i <- input$runs_table_rows_selected; req(i, "run" %in% names(runs()))
    file.path(cfg$runs_dir, runs()$run[i])
  })

  output$run_detail <- renderText({
    d <- selected_run()
    paste0(tr("run_folder", lang()), d, "\n\n", tail_file(file.path(d, "log.txt"), 30))
  })

  observeEvent(input$load_run, {
    d <- selected_run()
    if (!file.exists(file.path(d, "synthetic.csv"))) {
      return(showNotification(tr("run_no_output", lang()), type = "error"))
    }
    lr <- load_run(d)
    s <- registry()$algorithms[[lr$job$algorithm]] %||% list(name = lr$job$algorithm_name %||% lr$job$algorithm)
    result(list(real = lr$real, synthetic = lr$synthetic, run_dir = d, spec = s))
    nav_select("main", "evaluate")
  })
}

shinyApp(ui, server)
