# What do the personal attributes add? Both selected models are refitted
# without education, marital status and age, with the hyperparameters of
# part 2, out of fold on the training set and once on the test set.
#
#   Rscript scripts/run_ablation.R
#
# Writes results/ablation.rds.

source("R/features.R")
source("R/metrics.R")
source("R/models.R")

cv <- readRDS("results/cv.rds")
x <- readRDS("data/credit.rds")
is_test <- cv$is_test
y <- cv$y
fold <- cv$fold
personal <- c("education", "marriage", "age")

f_all <- build_features(x)
f_beh <- f_all[setdiff(names(f_all), personal)]
bx <- cv$tuning$xgb_engineered$best
bl <- cv$tuning$logit_engineered$best

run <- function(df) {
  tr <- df[!is_test, , drop = FALSE]
  te <- df[is_test, , drop = FALSE]
  X <- xgb_matrix(tr)
  oof <- list(logit = numeric(length(y)), xgb = numeric(length(y)))
  for (k in sort(unique(fold))) {
    a <- fold != k
    oof$logit[!a] <- predict(fit_logit(tr[a, ], y[a], bl$alpha, bl$lambda), tr[!a, ])
    oof$xgb[!a] <- predict(fit_xgb(X[a, ], y[a], bx, bx$nrounds), X[!a, ])
  }
  test <- list(
    logit = predict(fit_logit(tr, y, bl$alpha, bl$lambda), te),
    xgb = predict(fit_xgb(X, y, bx, bx$nrounds), xgb_matrix(te))
  )
  list(oof = oof, test = test)
}

res <- list(behaviour_only = run(f_beh))
saveRDS(res, "results/ablation.rds", compress = "xz")
for (m in c("logit", "xgb")) {
  cat(m, "oof log loss without personal attributes:", round(log_loss(y, res$behaviour_only$oof[[m]]), 4), "\n")
}
