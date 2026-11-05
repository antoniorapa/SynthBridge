# Valutazione di base: dati reali vs sintetici.
# Volutamente semplice e solo in R base: è un punto di partenza che gli studenti
# possono estendere (es. TSTR, distanza dal record più vicino, metriche di sdmetrics).

# Colonne con nomi interni fissi (in inglese); per mostrarla usare localize_fidelity().
fidelity_table <- function(real, synth) {
  cols <- intersect(names(real), names(synth))
  rows <- lapply(cols, function(n) {
    x <- real[[n]]; y <- synth[[n]]
    if (is.numeric(x)) {
      ks <- suppressWarnings(tryCatch(
        unname(stats::ks.test(x[!is.na(x)], y[!is.na(y)])$statistic), error = function(e) NA_real_
      ))
      data.frame(
        column = n, type = "numeric",
        mean_real = signif(mean(x, na.rm = TRUE), 4), mean_synth = signif(mean(y, na.rm = TRUE), 4),
        sd_real = signif(stats::sd(x, na.rm = TRUE), 4), sd_synth = signif(stats::sd(y, na.rm = TRUE), 4),
        metric = "KS", distance = round(ks, 3),
        na_real = round(mean(is.na(x)), 3), na_synth = round(mean(is.na(y)), 3)
      )
    } else {
      lv <- union(unique(as.character(x)), unique(as.character(y)))
      px <- table(factor(as.character(x), levels = lv)) / length(x)
      py <- table(factor(as.character(y), levels = lv)) / length(y)
      data.frame(
        column = n, type = "categorical",
        mean_real = NA, mean_synth = NA, sd_real = NA, sd_synth = NA,
        metric = "TVD", distance = round(0.5 * sum(abs(px - py)), 3),
        na_real = round(mean(is.na(x)), 3), na_synth = round(mean(is.na(y)), 3)
      )
    }
  })
  do.call(rbind, rows)
}

# Nomi delle colonne e tipi nella lingua scelta.
localize_fidelity <- function(ft, lang = default_lang()) {
  if (is.null(ft) || !nrow(ft)) return(ft)
  ft$type <- ifelse(ft$type == "numeric", tr("type_numeric", lang), tr("type_categorical", lang))
  names(ft) <- vapply(names(ft), function(n) tr(paste0("ft_", n), lang), character(1))
  ft
}

# Indicatori sintetici mostrati in cima alla scheda "Valuta".
overview_metrics <- function(real, synth) {
  ft <- fidelity_table(real, synth)
  num <- names(real)[vapply(real, is.numeric, logical(1))]
  cor_diff <- NA
  if (length(num) >= 2) {
    cr <- suppressWarnings(stats::cor(real[num], use = "pairwise.complete.obs"))
    cs <- suppressWarnings(stats::cor(synth[num], use = "pairwise.complete.obs"))
    cor_diff <- mean(abs(cr - cs)[upper.tri(cr)], na.rm = TRUE)
  }
  # quante righe sintetiche sono copie esatte di una riga reale (rischio privacy)
  key <- function(df) do.call(paste, c(lapply(df, as.character), sep = "\r"))
  copies <- mean(key(synth[names(real)]) %in% key(real))
  list(
    mean_distance = mean(ft$distance, na.rm = TRUE),
    cor_diff = cor_diff,
    exact_copies = copies
  )
}

plot_marginal <- function(real, synth, col, lang = default_lang()) {
  x <- real[[col]]; y <- synth[[col]]
  colors <- c("#1f4e79cc", "#e07b39aa")
  legend_labels <- c(tr("plot_real", lang), tr("plot_synthetic", lang))
  if (is.numeric(x)) {
    rng <- range(c(x, y), na.rm = TRUE, finite = TRUE)
    if (diff(rng) == 0) rng <- rng + c(-0.5, 0.5)
    br <- pretty(rng, n = 30)
    hx <- graphics::hist(x, breaks = br, plot = FALSE)
    hy <- graphics::hist(y[y >= min(br) & y <= max(br)], breaks = br, plot = FALSE)
    ymax <- max(hx$density, hy$density, na.rm = TRUE)
    plot(hx, freq = FALSE, col = colors[1], border = "white", ylim = c(0, ymax * 1.1),
         main = col, xlab = "", ylab = tr("plot_density", lang))
    plot(hy, freq = FALSE, col = colors[2], border = "white", add = TRUE)
  } else {
    lv <- union(levels(factor(x)), levels(factor(y)))
    m <- rbind(
      as.numeric(table(factor(as.character(x), levels = lv))) / length(x),
      as.numeric(table(factor(as.character(y), levels = lv))) / length(y)
    )
    colnames(m) <- lv
    graphics::barplot(m, beside = TRUE, col = colors, border = NA, main = col,
                      ylab = tr("plot_proportion", lang), las = 2)
  }
  graphics::legend("topright", legend = legend_labels, fill = colors, border = NA, bty = "n")
}

plot_correlation_diff <- function(real, synth, lang = default_lang()) {
  num <- names(real)[vapply(real, is.numeric, logical(1))]
  if (length(num) < 2) {
    plot.new(); text(0.5, 0.5, tr("plot_need_two_num", lang)); return(invisible())
  }
  cr <- suppressWarnings(stats::cor(real[num], use = "pairwise.complete.obs"))
  cs <- suppressWarnings(stats::cor(synth[num], use = "pairwise.complete.obs"))
  d <- abs(cr - cs)
  k <- length(num)
  op <- graphics::par(mar = c(8, 8, 3, 2)); on.exit(graphics::par(op))
  pal <- grDevices::colorRampPalette(c("#f7f7f7", "#f4a261", "#9b2226"))(50)
  graphics::image(1:k, 1:k, pmin(d[, k:1], 1), zlim = c(0, 1), col = pal, axes = FALSE, xlab = "", ylab = "",
                  main = tr("plot_cor_title", lang))
  graphics::axis(1, 1:k, num, las = 2, tick = FALSE)
  graphics::axis(2, 1:k, rev(num), las = 2, tick = FALSE)
  for (i in 1:k) for (j in 1:k) graphics::text(i, k - j + 1, sprintf("%.2f", d[i, j]), cex = 0.8)
}
