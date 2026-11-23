# Repeat the whole procedure on new train/test splits: features, tuning by
# cross-validation on the training part, final fit, evaluation on the test part.
#
#   Rscript scripts/run_splits.R
#
# Writes results/splits.rds. About 4 minutes per split on two cores.

source("R/features.R")
source("R/protocol.R")
source("R/metrics.R")
source("R/models.R")
source("R/decision.R")

n_splits  <- as.integer(Sys.getenv("N_SPLITS", 10))
n_configs <- as.integer(Sys.getenv("N_CONFIGS", 20))
r_grid <- exp(seq(log(0.05), log(1), length.out = 40))

x <- readRDS("data/credit.rds")
x_raw <- raw_features(x)
x_eng <- build_features(x)

value_captured <- function(y, E, pred, late, r) {
  t <- cost_threshold(r)
  v <- c(
    keep_all = policy_value(y, E, rep(FALSE, length(y)), r),
    act_all  = 0,
    rule     = policy_value(y, E, late, r),
    logit    = policy_value(y, E, pred$logit_engineered > t, r),
    xgb      = policy_value(y, E, pred$xgb_engineered > t, r),
    oracle   = policy_value(y, E, y == 1, r)
  )
  base <- max(v["keep_all"], v["act_all"])
  (v[c("rule", "logit", "xgb")] - base) / (v["oracle"] - base)
}

one_split <- function(seed) {
  is_test <- stratified_split(x$default, seed = seed)
  y <- x$default[!is_test]
  yt <- x$default[is_test]
  fold <- stratified_folds(y, seed = seed)
  pred <- list(
    constant = rep(mean(y), sum(is_test)),
    rule = {
      late <- x$PAY_1[!is_test] >= 2
      ifelse(x$PAY_1[is_test] >= 2, mean(y[late]), mean(y[!late]))
    }
  )
  for (s in c("raw", "engineered")) {
    df <- if (s == "raw") x_raw else x_eng
    tr <- df[!is_test, , drop = FALSE]
    te <- df[is_test, , drop = FALSE]

    g <- tune_logit(tr, y, fold)
    b <- g[which.min(g$log_loss), ]
    pred[[paste0("logit_", s)]] <- predict(fit_logit(tr, y, b$alpha, b$lambda), te)

    X <- xgb_matrix(tr)
    g <- tune_xgb(X, y, fold, xgb_grid(n_configs, seed = seed), seed = seed)
    b <- g[which.min(g$log_loss), ]
    m <- fit_xgb(X, y, b, b$nrounds, seed = seed)
    pred[[paste0("xgb_", s)]] <- predict(m, xgb_matrix(te))
  }
  E <- pmax(x$BILL_AMT1[is_test], 0)
  late <- x$PAY_1[is_test] >= 2
  list(
    seed = seed,
    scores = t(sapply(pred, function(p) scores(yt, p))),
    value = t(sapply(r_grid, function(r) value_captured(yt, E, pred, late, r))),
    r_grid = r_grid
  )
}

out <- list()
for (i in seq_len(n_splits)) {
  t0 <- Sys.time()
  out[[i]] <- one_split(1000 + i)
  sc <- out[[i]]$scores
  cat(sprintf("split %2d  logit %.4f  xgb %.4f  (%.0f s)\n", i,
              sc["logit_engineered", "log_loss"], sc["xgb_engineered", "log_loss"],
              as.numeric(Sys.time() - t0, units = "secs")))
  saveRDS(out, "results/splits.rds", compress = "xz")
}
