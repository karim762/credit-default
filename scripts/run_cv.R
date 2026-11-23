# Model selection by cross-validation on the training set.
#
#   Rscript scripts/run_cv.R
#
# Writes results/cv.rds, which analysis/02_models.Rmd reads. The test set is
# not touched here.

source("R/features.R")
source("R/protocol.R")
source("R/metrics.R")
source("R/models.R")

n_configs <- as.integer(Sys.getenv("N_CONFIGS", 30))

x <- readRDS("data/credit.rds")
y_all <- x$default
is_test <- stratified_split(y_all)
train <- x[!is_test, ]
y <- train$default
fold <- stratified_folds(y)
K <- max(fold)

sets <- list(
  raw        = raw_features(train),
  engineered = build_features(train)
)
sets$combined <- cbind(sets$raw, sets$engineered[setdiff(names(sets$engineered), c("age"))])

oof <- list()
tuning <- list()
timing <- list()

# benchmarks: a constant and the one-split rule PAY_1 >= 2
oof$constant <- numeric(length(y))
oof$rule <- numeric(length(y))
for (k in 1:K) {
  tr <- fold != k
  oof$constant[!tr] <- mean(y[tr])
  late <- train$PAY_1 >= 2
  oof$rule[!tr] <- ifelse(late[!tr], mean(y[tr & late]), mean(y[tr & !late]))
}

for (s in names(sets)) {
  df <- sets[[s]]

  t0 <- Sys.time()
  grid <- tune_logit(df, y, fold)
  best <- grid[which.min(grid$log_loss), ]
  p <- numeric(length(y))
  for (k in 1:K) {
    tr <- fold != k
    m <- fit_logit(df[tr, , drop = FALSE], y[tr], best$alpha, best$lambda)
    p[!tr] <- predict(m, df[!tr, , drop = FALSE])
  }
  oof[[paste0("logit_", s)]] <- p
  tuning[[paste0("logit_", s)]] <- list(grid = grid, best = best)
  timing[[paste0("logit_", s)]] <- as.numeric(Sys.time() - t0, units = "secs")
  cat(sprintf("logit %-10s  alpha %.1f  lambda %.2e  cv log loss %.4f  oof %.4f\n",
              s, best$alpha, best$lambda, best$log_loss, log_loss(y, p)))

  t0 <- Sys.time()
  X <- xgb_matrix(df)
  grid <- tune_xgb(X, y, fold, xgb_grid(n_configs))
  best <- grid[which.min(grid$log_loss), ]
  p <- numeric(length(y))
  for (k in 1:K) {
    tr <- fold != k
    m <- fit_xgb(X[tr, ], y[tr], best, best$nrounds)
    p[!tr] <- predict(m, X[!tr, ])
  }
  oof[[paste0("xgb_", s)]] <- p
  tuning[[paste0("xgb_", s)]] <- list(grid = grid, best = best)
  timing[[paste0("xgb_", s)]] <- as.numeric(Sys.time() - t0, units = "secs")
  cat(sprintf("xgb   %-10s  depth %d  trees %d  cv log loss %.4f  oof %.4f\n",
              s, best$max_depth, best$nrounds, best$log_loss, log_loss(y, p)))
}

dir.create("results", showWarnings = FALSE)
saveRDS(list(y = y, fold = fold, is_test = is_test, oof = oof, tuning = tuning, timing = timing),
        "results/cv.rds", compress = "xz")
